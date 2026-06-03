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
input           s_axi_lite_wvalid,

// BRAM port A on the physical p_cur memory block
output [31:0]   cur_bram_a_addr,
output          cur_bram_a_clk,
output [31:0]   cur_bram_a_wrdata,
input  [31:0]   cur_bram_a_rddata,
output          cur_bram_a_en,
output          cur_bram_a_rst,
output [3:0]    cur_bram_a_we,

// BRAM port B on the physical p_cur memory block
output [31:0]   cur_bram_b_addr,
output          cur_bram_b_clk,
output [31:0]   cur_bram_b_wrdata,
input  [31:0]   cur_bram_b_rddata,
output          cur_bram_b_en,
output          cur_bram_b_rst,
output [3:0]    cur_bram_b_we,

// BRAM port A on the physical p_prev memory block
output [31:0]   prev_bram_a_addr,
output          prev_bram_a_clk,
output [31:0]   prev_bram_a_wrdata,
input  [31:0]   prev_bram_a_rddata,
output          prev_bram_a_en,
output          prev_bram_a_rst,
output [3:0]    prev_bram_a_we,

// BRAM port B on the physical p_prev memory block
output [31:0]   prev_bram_b_addr,
output          prev_bram_b_clk,
output [31:0]   prev_bram_b_wrdata,
input  [31:0]   prev_bram_b_rddata,
output          prev_bram_b_en,
output          prev_bram_b_rst,
output [3:0]    prev_bram_b_we

);

localparam X_SIZE = 640;
localparam Y_SIZE = 480;
localparam SIM_X_SIZE = 160;
localparam SIM_Y_SIZE = 120;
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
reg swap_memory;
reg [7:0] frame_counter;

wire [7:0] x_val;
wire [6:0] y_val;

assign x_val = x[9:2];
assign y_val = y[8:2];

//note here we keep output resolution at 640x480 but we simulate a 160x120 grid of pixels, so each pixel simulated takes up 4x4 block of output.
//decided to keep this in case other parts of the FPGA is built according to 640x480, don't want to break that.
wire first = (x == 0) & (y == 0);
wire lastx = (x == X_SIZE - 1);
wire lasty = (y == Y_SIZE - 1);
wire ready;
wire valid_int = 1'b1;

wire sim_x_last = (x[1:0] == 2'b11);
wire sim_y_last = (y[1:0] == 2'b11);
wire sim_cell_tick = ready & valid_int & sim_x_last & sim_y_last;
wire sim_row_end = sim_cell_tick & (x_val == (SIM_X_SIZE - 1));

always @(posedge out_stream_aclk) begin
    if (periph_resetn) begin
        if (ready & valid_int) begin
            if (lastx) begin
                x <= 10'd0;
                if (lasty) y <= 9'd0;
                else y <= y + 9'd1;
            end
            else begin
                x <= x + 10'd1;
            end
        end
    end
    else begin
        x <= 10'd0;
        y <= 9'd0;
    end
end

wire [7:0] r, g, b;
wire signed [8:0] next_pixel_middle;
wire signed [8:0] next_pixel_middle_damped;
wire signed [8:0] cur_pixel_middle;
wire signed [8:0] cur_pixel_top;
wire signed [8:0] cur_pixel_bottom;
wire signed [8:0] cur_pixel_left;
wire signed [8:0] cur_pixel_right;
wire signed [8:0] prev_pixel_middle;

wire [8:0] left = (x_val > 0) ? x_val - 1 : 0;
wire [8:0] right = (x_val < (SIM_X_SIZE - 1)) ? x_val + 1 : (SIM_X_SIZE - 1);
wire [7:0] y_plus_2 = (y_val < (SIM_Y_SIZE - 2)) ? y_val + 2 : (SIM_Y_SIZE - 1);
wire [16:0] addr_center = y_val * SIM_X_SIZE + x_val;
wire [16:0] addr_y_plus_2 = y_plus_2 * SIM_X_SIZE + x_val;

reg signed [8:0] row_y_minus_1[0:SIM_X_SIZE-1];
reg signed [8:0] row_y[0:SIM_X_SIZE-1];
reg signed [8:0] row_y_plus_1[0:SIM_X_SIZE-1];
reg signed [8:0] row_y_plus_2[0:SIM_X_SIZE-1];
reg signed [8:0] top_center;
reg signed [8:0] mid_left;
reg signed [8:0] mid_center;
reg signed [8:0] mid_right;
reg signed [8:0] bot_center;
reg signed [8:0] prev_pixel_middle_reg;
reg [7:0] x_val_d;

wire [31:0] current_stream_addr = {15'd0, addr_y_plus_2, 2'b00};
wire [31:0] previous_center_addr = {15'd0, addr_center, 2'b00};
wire init_active = (frame_counter < 8'd2);
wire signed [8:0] current_stream_sample_raw = swap_memory ? prev_bram_a_rddata[8:0] : cur_bram_a_rddata[8:0];
wire signed [8:0] previous_center_sample_raw = swap_memory ? cur_bram_a_rddata[8:0] : prev_bram_a_rddata[8:0];
wire signed [8:0] current_stream_sample = init_active ? 9'sd0 : current_stream_sample_raw;
wire signed [8:0] previous_center_sample = init_active ? 9'sd0 : previous_center_sample_raw;
wire center_region = (x_val >= 8'd78) && (x_val <= 8'd82) && (y_val >= 7'd58) && (y_val <= 7'd62);
wire startup_seed_active = init_active && center_region;
wire center_drive_active = (x_val == 8'd80) && (y_val == 7'd60);
wire signed [8:0] startup_seed_value = frame_counter[0] ? -9'sd220 : 9'sd220;
wire signed [8:0] init_fill_value = startup_seed_active ? startup_seed_value : 9'sd0;
wire signed [8:0] next_pixel_with_impulse = startup_seed_active ? startup_seed_value :
                                            center_drive_active ? (next_pixel_middle_damped + 9'sd160) :
                                            next_pixel_middle_damped;
wire [31:0] destination_addr = {15'd0, addr_center, 2'b00};
wire [31:0] init_destination_wrdata = {{23{init_fill_value[8]}}, init_fill_value};
wire [31:0] destination_wrdata = {{23{next_pixel_with_impulse[8]}}, next_pixel_with_impulse};

assign prev_pixel_middle = prev_pixel_middle_reg;

assign cur_bram_a_clk = out_stream_aclk;
assign cur_bram_b_clk = out_stream_aclk;
assign prev_bram_a_clk = out_stream_aclk;
assign prev_bram_b_clk = out_stream_aclk;

assign cur_bram_a_rst = 1'b0;
assign cur_bram_b_rst = 1'b0;
assign prev_bram_a_rst = 1'b0;
assign prev_bram_b_rst = 1'b0;

assign cur_bram_a_wrdata = 32'd0;
assign prev_bram_a_wrdata = 32'd0;
assign cur_bram_a_we = 4'b0000;
assign prev_bram_a_we = 4'b0000;

assign cur_bram_a_en = sim_cell_tick;
assign prev_bram_a_en = sim_cell_tick;
assign cur_bram_b_en = sim_cell_tick;
assign prev_bram_b_en = sim_cell_tick;

// Port A on each BRAM is used for reads. Port B is reserved for writes into the inactive buffer.
assign cur_bram_a_addr = swap_memory ? previous_center_addr : current_stream_addr;
assign prev_bram_a_addr = swap_memory ? current_stream_addr : previous_center_addr;

assign cur_bram_b_addr = init_active ? destination_addr : (swap_memory ? destination_addr : 32'd0);
assign prev_bram_b_addr = init_active ? destination_addr : (swap_memory ? 32'd0 : destination_addr);
assign cur_bram_b_wrdata = init_active ? init_destination_wrdata : (swap_memory ? destination_wrdata : 32'd0);
assign prev_bram_b_wrdata = init_active ? init_destination_wrdata : (swap_memory ? 32'd0 : destination_wrdata);
assign cur_bram_b_we = init_active ? (sim_cell_tick ? 4'b0011 : 4'b0000) :
                       ((sim_cell_tick & swap_memory) ? 4'b0011 : 4'b0000);
assign prev_bram_b_we = init_active ? (sim_cell_tick ? 4'b0011 : 4'b0000) :
                        ((sim_cell_tick & !swap_memory) ? 4'b0011 : 4'b0000);

integer init_col;
integer col;
initial begin
    for (init_col = 0; init_col < SIM_X_SIZE; init_col = init_col + 1) begin
        row_y_minus_1[init_col] = 9'sd0;
        row_y[init_col] = 9'sd0;
        row_y_plus_1[init_col] = 9'sd0;
        row_y_plus_2[init_col] = 9'sd0;
    end

    top_center = 9'sd0;
    mid_left = 9'sd0;
    mid_center = 9'sd0;
    mid_right = 9'sd0;
    bot_center = 9'sd0;
    prev_pixel_middle_reg = 9'sd0;
    x_val_d = 8'd0;
    frame_counter = 8'd0;
end

always @(posedge out_stream_aclk) begin
    if (!periph_resetn) begin
        for (col = 0; col < SIM_X_SIZE; col = col + 1) begin
            row_y_minus_1[col] <= 9'sd0;
            row_y[col] <= 9'sd0;
            row_y_plus_1[col] <= 9'sd0;
            row_y_plus_2[col] <= 9'sd0;
        end
        top_center <= 9'sd0;
        mid_left <= 9'sd0;
        mid_center <= 9'sd0;
        mid_right <= 9'sd0;
        bot_center <= 9'sd0;
        prev_pixel_middle_reg <= 9'sd0;
        x_val_d <= 8'd0;
    end
    else if (sim_cell_tick) begin
        x_val_d <= x_val;
        prev_pixel_middle_reg <= previous_center_sample;
        if (sim_row_end) begin
            for (col = 0; col < SIM_X_SIZE; col = col + 1) begin
                row_y_minus_1[col] <= row_y[col];
                row_y[col] <= row_y_plus_1[col];
                row_y_plus_1[col] <= row_y_plus_2[col];
            end
        end
        row_y_plus_2[x_val_d] <= current_stream_sample;
        top_center <= row_y_minus_1[x_val];
        mid_left <= row_y[left];
        mid_center <= row_y[x_val];
        mid_right <= row_y[right];
        bot_center <= row_y_plus_1[x_val];
    end
end

assign cur_pixel_top     = top_center;
assign cur_pixel_bottom  = bot_center;
assign cur_pixel_left    = mid_left;
assign cur_pixel_right   = mid_right;
assign cur_pixel_middle  = mid_center;

object_laplacian laplacian(
    .pixel_top(cur_pixel_top),
    .pixel_bottom(cur_pixel_bottom),
    .pixel_left(cur_pixel_left),
    .pixel_right(cur_pixel_right),
    .pixel_middle(cur_pixel_middle),
    .pixel_middle_previous(prev_pixel_middle),
    .reflection_to_wall(0),
    .transmission_to_wall(0),
    .reflection_to_air(0),
    .transmission_to_air(0),
    .wave_speed_squared(64),
    .wall_case(0),
    .next_pixel_middle(next_pixel_middle)
);

wire [8:0] damp_q8;
wire valid_damp;
boundary_damping_coeff damping_coeff(
    .clk(out_stream_aclk),
    .rstn(periph_resetn),
    .valid_in(sim_cell_tick),
    .x(x_val),
    .y(y_val),
    .valid_out(valid_damp),
    .damp_q8(damp_q8)
);

apply_damping damping(
    .clk(out_stream_aclk),
    .rstn(periph_resetn),
    .valid_in(sim_cell_tick),
    .p_raw(next_pixel_middle),
    .damp_q8(damp_q8),
    .valid_out(),
    .p_damped(next_pixel_middle_damped)
);

always @(posedge out_stream_aclk) begin
    if (!periph_resetn) begin
        swap_memory <= 1'b0;
        frame_counter <= 8'd0;
    end
    else if (sim_cell_tick & (lastx) & (lasty)) begin
        swap_memory <= ~swap_memory;
        if (frame_counter != 8'hFF) begin
            frame_counter <= frame_counter + 8'd1;
        end
    end
end

wire [8:0] mag;
wire [10:0] mag_scaled;
wire [7:0] vis;

assign mag = (cur_pixel_middle > 0) ? cur_pixel_middle : -cur_pixel_middle;
assign mag_scaled = {mag, 2'b00};  // x4 boost
assign vis = (mag_scaled > 11'd255) ? 8'hFF : mag_scaled[7:0];

assign r = (cur_pixel_middle > 0) ? vis : 8'h00;
assign g = 8'h00;
assign b = (cur_pixel_middle < 0) ? vis : 8'h00;

packer pixel_packer(
    .aclk(out_stream_aclk),
    .aresetn(periph_resetn),
    .r(r), .g(g), .b(b),
    .eol(lastx), .in_stream_ready(ready), .valid(valid_int), .sof(first),
    .out_stream_tdata(out_stream_tdata), .out_stream_tkeep(out_stream_tkeep),
    .out_stream_tlast(out_stream_tlast), .out_stream_tready(out_stream_tready),
    .out_stream_tvalid(out_stream_tvalid), .out_stream_tuser(out_stream_tuser)
);

endmodule
