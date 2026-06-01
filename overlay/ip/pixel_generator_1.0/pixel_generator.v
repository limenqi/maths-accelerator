
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 16.05.2024 22:03:08
// Design Name: 
// Module Name: test_block_v
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module pixel_generator(
input           out_stream_aclk,
input           s_axi_lite_aclk,
input           axi_resetn,
input           periph_resetn,

//Stream output
output [31:0]   out_stream_tdata,
output [3:0]    out_stream_tkeep,
output          out_stream_tlast,
input           out_stream_tready,
output          out_stream_tvalid,
output [0:0]    out_stream_tuser, 

//AXI-Lite S
input [AXI_LITE_ADDR_WIDTH-1:0]     s_axi_lite_araddr,
output          s_axi_lite_arready,
input           s_axi_lite_arvalid,

input [AXI_LITE_ADDR_WIDTH-1:0]     s_axi_lite_awaddr,
output          s_axi_lite_awready,
input           s_axi_lite_awvalid,

input           s_axi_lite_bready,
output [1:0]    s_axi_lite_bresp,
output          s_axi_lite_bvalid,

output [31:0]   s_axi_lite_rdata,
input           s_axi_lite_rready,
output [1:0]    s_axi_lite_rresp,
output          s_axi_lite_rvalid,

input  [31:0]   s_axi_lite_wdata,
output          s_axi_lite_wready,
input           s_axi_lite_wvalid

);

localparam X_SIZE = 640;
localparam Y_SIZE = 480;
parameter  REG_FILE_SIZE = 8;
localparam REG_FILE_AWIDTH = $clog2(REG_FILE_SIZE);
parameter  AXI_LITE_ADDR_WIDTH = 8;

localparam AWAIT_WADD_AND_DATA = 3'b000;
localparam AWAIT_WDATA = 3'b001;
localparam AWAIT_WADD = 3'b010;
localparam AWAIT_WRITE = 3'b100;
localparam AWAIT_RESP = 3'b101;

localparam AWAIT_RADD = 2'b00;
localparam AWAIT_FETCH = 2'b01;
localparam AWAIT_READ = 2'b10;

localparam AXI_OK = 2'b00;
localparam AXI_ERR = 2'b10;

reg [31:0]                          regfile [REG_FILE_SIZE-1:0];
reg [REG_FILE_AWIDTH-1:0]           writeAddr, readAddr;
reg [31:0]                          readData, writeData;
reg [1:0]                           readState = AWAIT_RADD;
reg [2:0]                           writeState = AWAIT_WADD_AND_DATA;

//Read from the register file
always @(posedge s_axi_lite_aclk) begin
    
    readData <= regfile[readAddr];

    if (!axi_resetn) begin
    readState <= AWAIT_RADD;
    end

    else case (readState)

        AWAIT_RADD: begin
            if (s_axi_lite_arvalid) begin
                readAddr <= s_axi_lite_araddr[2+:REG_FILE_AWIDTH];
                readState <= AWAIT_FETCH;
            end
        end

        AWAIT_FETCH: begin
            readState <= AWAIT_READ;
        end

        AWAIT_READ: begin
            if (s_axi_lite_rready) begin
                readState <= AWAIT_RADD;
            end
        end

        default: begin
            readState <= AWAIT_RADD;
        end

    endcase
end

assign s_axi_lite_arready = (readState == AWAIT_RADD);
assign s_axi_lite_rresp = (readAddr < REG_FILE_SIZE) ? AXI_OK : AXI_ERR;
assign s_axi_lite_rvalid = (readState == AWAIT_READ);
assign s_axi_lite_rdata = readData;

//Write to the register file, use a state machine to track address write, data write and response read events
always @(posedge s_axi_lite_aclk) begin

    if (!axi_resetn) begin
        writeState <= AWAIT_WADD_AND_DATA;
    end

    else case (writeState)

        AWAIT_WADD_AND_DATA: begin  //Idle, awaiting a write address or data
            case ({s_axi_lite_awvalid, s_axi_lite_wvalid})
                2'b10: begin
                    writeAddr <= s_axi_lite_awaddr[2+:REG_FILE_AWIDTH];
                    writeState <= AWAIT_WDATA;
                end
                2'b01: begin
                    writeData <= s_axi_lite_wdata;
                    writeState <= AWAIT_WADD;
                end
                2'b11: begin
                    writeData <= s_axi_lite_wdata;
                    writeAddr <= s_axi_lite_awaddr[2+:REG_FILE_AWIDTH];
                    writeState <= AWAIT_WRITE;
                end
                default: begin
                    writeState <= AWAIT_WADD_AND_DATA;
                end
            endcase        
        end

        AWAIT_WDATA: begin //Received address, waiting for data
            if (s_axi_lite_wvalid) begin
                writeData <= s_axi_lite_wdata;
                writeState <= AWAIT_WRITE;
            end
        end

        AWAIT_WADD: begin //Received data, waiting for address
            if (s_axi_lite_awvalid) begin
                writeAddr <= s_axi_lite_awaddr[2+:REG_FILE_AWIDTH];
                writeState <= AWAIT_WRITE;
            end
        end

        AWAIT_WRITE: begin //Perform the write
            regfile[writeAddr] <= writeData;
            writeState <= AWAIT_RESP;
        end

        AWAIT_RESP: begin //Wait to send response
            if (s_axi_lite_bready) begin
                writeState <= AWAIT_WADD_AND_DATA;
            end
        end

        default: begin
            writeState <= AWAIT_WADD_AND_DATA;
        end
    endcase
end

assign s_axi_lite_awready = (writeState == AWAIT_WADD_AND_DATA || writeState == AWAIT_WADD);
assign s_axi_lite_wready = (writeState == AWAIT_WADD_AND_DATA || writeState == AWAIT_WDATA);
assign s_axi_lite_bvalid = (writeState == AWAIT_RESP);
assign s_axi_lite_bresp = (writeAddr < REG_FILE_SIZE) ? AXI_OK : AXI_ERR;



reg [9:0] x;
reg [8:0] y;

wire [7:0] x_val;
wire [6:0] y_val;

assign x_val = x[9:2];
assign y_val = y[8:2];

//note here we keep output resolution at 640x480 but we simulate a 160x120 grid of pixels, so each pixel simulated takes up 4x4 block of output. 
//decided to keep this in case other parts of the FPGA is built according to 640x480, don't want to break that.
wire first = (x == 0) & (y==0);
wire lastx = (x == X_SIZE - 1);
wire lasty = (y == Y_SIZE - 1);
wire [7:0] frame = regfile[0];
wire ready;
reg swap_memory;



always @(posedge out_stream_aclk) begin
    if (periph_resetn) begin
        if (ready & valid_int) begin
            if (lastx) begin
                x <= 9'd0;
                if (lasty) y <= 9'd0;
                else y <= y + 9'd1;
            end
            else x <= x + 9'd1;
        end
    end
    else begin
        x <= 0;
        y <= 0;
    end
end

wire valid_int = 1'b1;

wire [7:0] r, g, b;
// assign r = x[7:0] + frame;
// assign g = y[7:0] + frame;
// assign b = x[6:0]+y[6:0] + frame;

//initialize pixel values to 0
integer i, j;
initial begin
    for (i = 0; i < 160; i = i + 1) begin
        for (j = 0; j < 120; j = j + 1) begin
            p_cur[j*160 + i] = 9'sd0;
            p_prev[j*160 + i] = 9'sd0;
        end
    end
    p_cur[60*160 + 80] = 9'sd255; //initial impulse in the middle of the grid, can be changed to other locations or multiple impulses for testing
end

(* ram_style = "block" *) reg signed [8:0] p_prev [0:19199];
(* ram_style = "block" *) reg signed [8:0] p_cur  [0:19199];

wire signed [8:0] next_pixel_middle;
wire signed [8:0] next_pixel_middle_damped;
wire signed [8:0] cur_pixel_middle;
wire signed [8:0] cur_pixel_top;
wire signed [8:0] cur_pixel_bottom;
wire signed [8:0] cur_pixel_left;
wire signed [8:0] cur_pixel_right;
wire signed [8:0] prev_pixel_middle;

// using swap memory as a flag to determine which memory to read from and write to. 
// to save space on reg file, only use 2 arrays to store pixel values and we swap their roles every frame.


wire [8:0] left = (x_val > 0) ? x_val - 1 : 0;
wire [8:0] right = (x_val < 159) ? x_val + 1 : 159;
wire [7:0] top = (y_val > 0) ? y_val - 1 : 0;
wire [7:0] bottom = (y_val < 119) ? y_val + 1 : 119;


assign prev_pixel_middle = swap_memory ? p_cur[addr_center]  : p_prev[addr_center];
wire [16:0] addr_center = y_val * 160 + x_val;

//row cache

reg signed [8:0] row_y_minus_1[0:159];
reg signed [8:0] row_y[0:159];
reg signed [8:0] row_y_plus_1[0:159];
reg signed [8:0] row_y_plus_2[0:159];

reg signed [8:0] top_left, top_center, top_right;
reg signed [8:0] mid_left, mid_center, mid_right;
reg signed [8:0] bot_left, bot_center, bot_right;

// assign cur_pixel_top     = swap_memory ? p_prev[addr_top] : p_cur[addr_top];
// assign cur_pixel_bottom  = swap_memory ? p_prev[addr_bottom] : p_cur[addr_bottom];
// assign cur_pixel_left    = swap_memory ? p_prev[addr_left] : p_cur[addr_left];
// assign cur_pixel_right   = swap_memory ? p_prev[addr_right] : p_cur[addr_right]; 

wire [7:0] y_plus_2 = (y_val < 118) ? y_val + 2 : 8'd119;
wire [16:0] addr_y_plus_2 = y_plus_2 * 160 + x_val;

always @(posedge out_stream_aclk) begin
    if (ready & valid_int) begin
        if(x_val!=159) begin
            top_center <= row_y_minus_1[x_val];
            mid_left   <= row_y[left];
            mid_center <= row_y[x_val];
            mid_right  <= row_y[right];
            bot_center <= row_y_plus_1[x_val];
            row_y_plus_2[x_val] <= swap_memory ? p_prev[addr_y_plus_2] : p_cur[addr_y_plus_2];
        end
    end
    
end

assign cur_pixel_top     = top_center;
assign cur_pixel_bottom  = bot_center;
assign cur_pixel_left    = mid_left;
assign cur_pixel_right   = mid_right;
assign cur_pixel_middle  = mid_center;
// boundary conditions still not handled currently
integer col;
initial begin
    for (col = 0; col < 160; col = col + 1) 
        begin
        row_y_minus_1[col] = p_cur[col];
        row_y[col] = p_cur[col];
        row_y_plus_1[col] = p_cur[160 + col];
        row_y_plus_2[col] = p_cur[320 + col];
        end
end


always @(posedge out_stream_aclk) begin
    if (ready & valid_int) begin
        if(x_val ==159) begin
            for(col = 0; col < 159; col = col + 1) begin
                row_y_minus_1[col] <= row_y[col];
                row_y[col] <= row_y_plus_1[col];
                row_y_plus_1[col] <= row_y_plus_2[col];
            end
        end
    end
end

object_laplacian laplacian(  .pixel_top(cur_pixel_top), .pixel_bottom(cur_pixel_bottom), .pixel_left(cur_pixel_left), .pixel_right(cur_pixel_right),
                        .pixel_middle(cur_pixel_middle), .pixel_middle_previous(prev_pixel_middle),
                        .reflection_to_wall(0), .transmission_to_wall(0), .reflection_to_air(0), .transmission_to_air(0),
                        .wave_speed_squared(0), .wall_case(0),
                        .next_pixel_middle(next_pixel_middle) );

//boundary conditions

wire [8:0] damp_q8;
wire valid_damp;
boundary_damping_coeff damping_coeff( .clk(out_stream_aclk), .rstn(periph_resetn), .valid_in(valid_int), .x(x_val), .y(y_val),
                                    .valid_out(valid_damp), .damp_q8(damp_q8) );

apply_damping damping( .clk(out_stream_aclk), .rstn(periph_resetn), .valid_in(valid_damp), .p_raw(next_pixel_middle), .damp_q8(damp_q8),
                        .valid_out(), .p_damped(next_pixel_middle_damped) );

always @(posedge out_stream_aclk) begin 
    if(!periph_resetn)
        swap_memory <= 1'b0;
    else if (x_val==159 && y_val==119)
        if (ready & valid_int) begin
            swap_memory <= ~swap_memory;
        end
    if (ready && valid_int) begin
        if (x_val != 159) begin
            if (!swap_memory) begin
                if (x_val == 80 && y_val == 60)
                    p_prev[addr_center] <= next_pixel_middle_damped + 9'sd40;
                else
                    p_prev[addr_center] <= next_pixel_middle_damped;
            end
            else begin
                if (x_val == 80 && y_val == 60)
                    p_cur[addr_center] <= next_pixel_middle_damped + 9'sd40;
                else
                    p_cur[addr_center] <= next_pixel_middle_damped;
            end
        end
    end
end
wire [8:0] mag;
assign mag = (cur_pixel_middle > 0) ? cur_pixel_middle : -cur_pixel_middle;
// magnitude is aboslute value of pressure, how positive pressure is determines red value and how negative pressure is determines blue value, green is not used.
assign r = (cur_pixel_middle > 0) ? mag[7:0] : 0;
assign g = 0;
assign b = (cur_pixel_middle < 0) ? mag[7:0] : 0;

packer pixel_packer(    .aclk(out_stream_aclk),
                        .aresetn(periph_resetn),
                        .r(r), .g(g), .b(b),
                        .eol(lastx), .in_stream_ready(ready), .valid(valid_int), .sof(first),
                        .out_stream_tdata(out_stream_tdata), .out_stream_tkeep(out_stream_tkeep),
                        .out_stream_tlast(out_stream_tlast), .out_stream_tready(out_stream_tready),
                        .out_stream_tvalid(out_stream_tvalid), .out_stream_tuser(out_stream_tuser) );

 
endmodule
