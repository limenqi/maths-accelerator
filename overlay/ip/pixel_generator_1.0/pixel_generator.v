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


module pixel_generator #(
parameter AXI_LITE_ADDR_WIDTH = 8,
parameter REG_FILE_SIZE = 8
)(
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
localparam REG_FILE_AWIDTH = $clog2(REG_FILE_SIZE);

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


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////



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
wire port_b_write_active;
reg port_b_write_active_d;
wire display_read_prime = port_b_write_active_d & !port_b_write_active;
wire valid_int = !(port_b_write_active | port_b_write_active_d);

wire sim_x_last = (x[1:0] == 2'b11);
wire sim_y_last = (y[1:0] == 2'b11);
wire start_pixel_calc = ready & valid_int & sim_x_last & sim_y_last;


// advance display pixel coordinates
always @(posedge out_stream_aclk) begin
    if (periph_resetn) begin
        if (ready & valid_int) begin
            if (lastx) begin
                x <= 10'd0;
                // wrap to next line, if at end of last line wrap to top
                if (lasty) y <= 9'd0;
                else y <= y + 9'd1;
            end
            else begin
                x <= x + 10'd1;
            end
        end
    end
    // on reset, start at the top-left corner, note active low reset
    else begin
        x <= 10'd0;
        y <= 9'd0;
    end
end

localparam PRESS_FRAC = 6;
wire [7:0] r, g, b;
wire signed [17:0] next_pixel_middle;
wire signed [15:0] cur_pixel_middle;
wire signed [15:0] solver_pixel_middle;
wire signed [15:0] cur_pixel_top;
wire signed [15:0] cur_pixel_bottom;
wire signed [15:0] cur_pixel_left;
wire signed [15:0] cur_pixel_right;
wire signed [15:0] prev_pixel_middle;

// gives row below current row, clamps to current row if bottom row.
wire [7:0] y_plus_1 = (y_val < (SIM_Y_SIZE - 1)) ? (y_val + 1) : y_val;

wire [16:0] addr_center = y_val * SIM_X_SIZE + x_val;
wire [7:0] window_center_x_for_read = (x_val == 8'd0) ? 8'd0 : (x_val - 8'd1);
wire [16:0] addr_previous_center = y_val * SIM_X_SIZE + window_center_x_for_read;

wire [16:0] addr_y_plus_1 = y_plus_1 * SIM_X_SIZE + x_val;
wire [31:0] current_bottom_row_addr = {17'd0, addr_y_plus_1[14:0]};
wire [31:0] previous_center_addr = {17'd0, addr_previous_center[14:0]};
wire [31:0] destination_write_addr = {17'd0, addr_center[14:0]};
wire [31:0] display_center_addr = {17'd0, addr_center[14:0]};

// First 2 frames are init frames used to clear/fill memory.
wire init_active = (frame_counter < 8'd2);

reg [31:0] gp0_video_meta;
reg [31:0] gp0_video;
reg [31:0] gp1_video_meta;
reg [31:0] gp1_video;
reg [31:0] gp4_video_meta;
reg [31:0] gp4_video;
reg [31:0] gp5_video_meta;
reg [31:0] gp5_video;
reg gp0_fire_prev;
reg source_active;
reg [7:0] source_frames_left;

wire [9:0] source_x_video = gp1_video[9:0];
wire [8:0] source_y_video = gp1_video[18:10];
wire [7:0] source_sim_x_video = source_x_video[9:2];
wire [6:0] source_sim_y_video = source_y_video[8:2];
wire signed [8:0] source_gain_video = gp4_video[8:0];
// Gain register is in display units; convert to Q6 state units.
wire signed [15:0] source_gain_q6 = {{7{source_gain_video[8]}}, source_gain_video} <<< PRESS_FRAC;
wire [7:0] source_duration_video = (gp5_video[15:8] == 8'd0) ? 8'd1 : gp5_video[15:8];
wire gp0_fire_now = gp0_video[0] & ~gp0_fire_prev;
wire signed [15:0] startup_seed_value = 16'sd0;

always @(posedge out_stream_aclk) begin
    if (!periph_resetn) begin
        gp0_video_meta <= 32'd0;
        gp0_video <= 32'd0;
        gp1_video_meta <= 32'd0;
        gp1_video <= 32'd0;
        gp4_video_meta <= 32'd0;
        gp4_video <= 32'd0;
        gp5_video_meta <= 32'd0;
        gp5_video <= 32'd0;
        gp0_fire_prev <= 1'b0;
        source_active <= 1'b0;
        source_frames_left <= 8'd0;
    end
    else begin
        gp0_video_meta <= regfile[0];
        gp0_video <= gp0_video_meta;
        gp1_video_meta <= regfile[1];
        gp1_video <= gp1_video_meta;
        gp4_video_meta <= regfile[4];
        gp4_video <= gp4_video_meta;
        gp5_video_meta <= regfile[5];
        gp5_video <= gp5_video_meta;
        gp0_fire_prev <= gp0_video[0];

        if (gp0_fire_now) begin
            source_active <= 1'b1;
            source_frames_left <= source_duration_video;
        end
        else if (start_pixel_calc & lastx & lasty & source_active) begin
            if (source_frames_left <= 8'd1) begin
                source_active <= 1'b0;
                source_frames_left <= 8'd0;
            end
            else begin
                source_frames_left <= source_frames_left - 8'd1;
            end
        end
    end
end

// Stage 2 updates this pointer; Stage 0 captures it for the BRAM request.
reg [7:0] col_ptr;

reg bram_sample_valid;
reg [7:0] bram_x;
reg [6:0] bram_y;
reg [7:0] bram_col;
reg [31:0] bram_destination_write_addr;
reg bram_init_active;
reg signed [15:0] bram_startup_seed_value;
reg bram_swap_memory;

always @(posedge out_stream_aclk) begin
    if (!periph_resetn) begin
        bram_sample_valid <= 1'b0;
        bram_x <= 8'd0;
        bram_y <= 7'd0;
        bram_col <= 8'd0;
        bram_destination_write_addr <= 32'd0;
        bram_init_active <= 1'b0;
        bram_startup_seed_value <= 16'sd0;
        bram_swap_memory <= 1'b0;
    end
    else begin
        bram_sample_valid <= start_pixel_calc;

        if (start_pixel_calc) begin
            bram_x <= x_val;
            bram_y <= y_val;
            bram_col <= col_ptr;
            bram_destination_write_addr <= destination_write_addr;
            bram_init_active <= init_active;
            bram_startup_seed_value <= startup_seed_value;
            bram_swap_memory <= swap_memory;
        end
    end
end

assign cur_bram_a_clk = out_stream_aclk;
assign cur_bram_b_clk = out_stream_aclk;
assign prev_bram_a_clk = out_stream_aclk;
assign prev_bram_b_clk = out_stream_aclk;

//reset is disabled
assign cur_bram_a_rst = 1'b0;
assign cur_bram_b_rst = 1'b0;
assign prev_bram_a_rst = 1'b0;
assign prev_bram_b_rst = 1'b0;

//write enable is off and write data is 0 as for A is only for reading.
assign cur_bram_a_wrdata = 32'd0;
assign prev_bram_a_wrdata = 32'd0;
assign cur_bram_a_we = 4'b0000;
assign prev_bram_a_we = 4'b0000;

// enable reading when new simulation pixel starts.
assign cur_bram_a_en = start_pixel_calc;
assign prev_bram_a_en = start_pixel_calc;

// Port A on each BRAM is used for reads. Port B is reserved for writes into the inactive buffer.
// swap_memory determines which BRAM is read from and which is written to, swapping the roles of current and previous buffers each frame.
assign cur_bram_a_addr = swap_memory ? previous_center_addr : current_bottom_row_addr;
assign prev_bram_a_addr = swap_memory ? current_bottom_row_addr : previous_center_addr;


wire signed [15:0] bram_current_bottom_sample =
    bram_init_active ? 16'sd0 :
    (bram_swap_memory ? prev_bram_a_rddata[15:0] : cur_bram_a_rddata[15:0]);

wire signed [15:0] bram_previous_center_sample =
    bram_init_active ? 16'sd0 :
    (bram_swap_memory ? cur_bram_a_rddata[15:0] : prev_bram_a_rddata[15:0]);

reg window_valid;
reg [7:0] window_x;
reg [6:0] window_y;
reg [31:0] window_destination_write_addr;
reg window_init_active;
reg window_startup_seed_active;
reg window_center_drive_active;
reg signed [15:0] window_init_fill_value;
reg signed [15:0] window_startup_seed_value;
reg window_swap_memory;

always @(posedge out_stream_aclk) begin
    if (!periph_resetn) begin
        window_valid <= 1'b0;
        window_x <= 8'd0;
        window_y <= 7'd0;
        window_destination_write_addr <= 32'd0;
        window_init_active <= 1'b0;
        window_startup_seed_active <= 1'b0;
        window_center_drive_active <= 1'b0;
        window_init_fill_value <= 16'sd0;
        window_startup_seed_value <= 16'sd0;
        window_swap_memory <= 1'b0;
    end
    else begin
        window_valid <= bram_sample_valid & (bram_x != 8'd0);

        if (bram_sample_valid) begin
            window_x <= (bram_x == 8'd0) ? 8'd0 : (bram_x - 8'd1);
            window_y <= bram_y;
            window_destination_write_addr <= (bram_x == 8'd0) ? bram_destination_write_addr :
                                             (bram_destination_write_addr - 32'd1);
            window_init_active <= bram_init_active;
            window_startup_seed_active <= 1'b0;
            window_center_drive_active <= source_active &&
                                          (bram_x == (source_sim_x_video + 8'd1)) &&
                                          (bram_y == source_sim_y_video);
            window_init_fill_value <= 16'sd0;
            window_startup_seed_value <= bram_startup_seed_value;
            window_swap_memory <= bram_swap_memory;
        end
    end
end

reg signed [15:0] row_y[0:SIM_X_SIZE-1];
reg signed [15:0] row_y_plus_1[0:SIM_X_SIZE-1];
reg signed [15:0] top_center;
reg signed [15:0] mid_left;
reg signed [15:0] mid_center;
reg signed [15:0] mid_right;
reg signed [15:0] bot_center;
reg signed [15:0] prev_pixel_middle_reg;
reg signed [15:0] render_pixel_middle;

reg signed [15:0] row_y_out;
reg signed [15:0] row_y_plus_1_out;
reg signed [15:0] top0, top1, top2;
reg signed [15:0] mid0, mid1, mid2;
reg signed [15:0] bot0, bot1, bot2;

assign prev_pixel_middle = prev_pixel_middle_reg;

// Simulation/power-up initialization for Stage 2 storage.
integer init_col;
initial begin
    for (init_col = 0; init_col < SIM_X_SIZE; init_col = init_col + 1) begin
        row_y[init_col] = 16'sd0;
        row_y_plus_1[init_col] = 16'sd0;
    end
    col_ptr = 8'd0;
    row_y_out = 16'sd0;
    row_y_plus_1_out = 16'sd0;
    top0 = 16'sd0;
    top1 = 16'sd0;
    top2 = 16'sd0;
    top_center = 16'sd0;
    mid0 = 16'sd0;
    mid1 = 16'sd0;
    mid2 = 16'sd0;
    mid_left = 16'sd0;
    mid_center = 16'sd0;
    mid_right = 16'sd0;
    bot0 = 16'sd0;
    bot1 = 16'sd0;
    bot2 = 16'sd0;
    bot_center = 16'sd0;
    prev_pixel_middle_reg = 16'sd0;
    render_pixel_middle = 16'sd0;
    frame_counter = 8'd0;
end

function signed [15:0] clamp_pressure_q6;
    input signed [17:0] a;
    begin
        if (a > 18'sd16320)
            clamp_pressure_q6 = 16'sd16320;
        else if (a < -18'sd16384)
            clamp_pressure_q6 = -16'sd16384;
        else
            clamp_pressure_q6 = a[15:0];
    end
endfunction

function signed [15:0] sat_add_pressure_wide;
    input signed [17:0] a;
    input signed [15:0] b;
    reg signed [18:0] sum;
    begin
        sum = a + b;
        if (sum > 19'sd16320)
            sat_add_pressure_wide = 16'sd16320;
        else if (sum < -19'sd16384)
            sat_add_pressure_wide = -16'sd16384;
        else
            sat_add_pressure_wide = sum[15:0];
    end
endfunction

//
// Input for the laplacian:
//
//          top_center
// mid_left mid_center mid_right
//          bot_center
//

// row_y          holds an older row
// row_y_plus_1   holds a newer row
// current_sample is the newest bottom row
// during each pixel: 
//
// top    from row_y
// middle from row_y_plus_1
// bottom from bram_current_bottom_sample
//
//
//
always @(posedge out_stream_aclk) begin
    if (!periph_resetn) begin
        for (init_col = 0; init_col < SIM_X_SIZE; init_col = init_col + 1) begin
            row_y[init_col] <= 16'sd0;
            row_y_plus_1[init_col] <= 16'sd0;
        end
        col_ptr <= 8'd0;
        row_y_out <= 16'sd0;
        row_y_plus_1_out <= 16'sd0;
        top0 <= 16'sd0;
        top1 <= 16'sd0;
        top2 <= 16'sd0;
        top_center <= 16'sd0;
        mid0 <= 16'sd0;
        mid1 <= 16'sd0;
        mid2 <= 16'sd0;
        mid_left <= 16'sd0;
        mid_center <= 16'sd0;
        mid_right <= 16'sd0;
        bot0 <= 16'sd0;
        bot1 <= 16'sd0;
        bot2 <= 16'sd0;
        bot_center <= 16'sd0;
        prev_pixel_middle_reg <= 16'sd0;
        render_pixel_middle <= 16'sd0;
    end
    else if (bram_sample_valid) begin
        prev_pixel_middle_reg <= bram_previous_center_sample;
        // 1-row and 2-row delayed stream outputs
        row_y_out <= row_y[bram_col];
        row_y_plus_1_out <= row_y_plus_1[bram_col];
        // push newer rows into delay storage
        row_y[bram_col] <= row_y_plus_1[bram_col];
        row_y_plus_1[bram_col] <= bram_current_bottom_sample;
        if (bram_col == 0) begin
            top0 <= 0; top1 <= 0; top2 <= row_y[bram_col];
            mid0 <= 0; mid1 <= 0; mid2 <= row_y_plus_1[bram_col];
            bot0 <= 0; bot1 <= 0; bot2 <= bram_current_bottom_sample;
            top_center <= 0;
            mid_left   <= 0;
            mid_center <= 0;
            mid_right  <= 0;
            bot_center <= 0;
        end else begin
            // shift the 3 column window left, insert the newest sample on the right
            top0 <= top1; top1 <= top2; top2 <= row_y[bram_col];
            mid0 <= mid1; mid1 <= mid2; mid2 <= row_y_plus_1[bram_col];
            bot0 <= bot1; bot1 <= bot2; bot2 <= bram_current_bottom_sample;
            top_center <= top2;
            mid_left   <= mid1;
            mid_center <= mid2;
            mid_right  <= row_y_plus_1[bram_col];
            bot_center <= bot2;
        end

        // column pointer
        if (bram_col == SIM_X_SIZE - 1)
            col_ptr <= 0;
        else
            col_ptr <= col_ptr + 1;
    end

    if (periph_resetn && ready & valid_int) begin
        render_pixel_middle <= init_active ? 16'sd0 :
                               (swap_memory ? prev_bram_b_rddata[15:0] : cur_bram_b_rddata[15:0]);
    end
end

assign cur_pixel_top     = top_center;
assign cur_pixel_bottom  = bot_center;
assign cur_pixel_left    = mid_left;
assign cur_pixel_right   = mid_right;
assign solver_pixel_middle = mid_center;
assign cur_pixel_middle  = render_pixel_middle;

object_laplacian laplacian(
    .pixel_top(cur_pixel_top),
    .pixel_bottom(cur_pixel_bottom),
    .pixel_left(cur_pixel_left),
    .pixel_right(cur_pixel_right),
    .pixel_middle(solver_pixel_middle),
    .pixel_middle_previous(prev_pixel_middle),
    .reflection_to_wall(16'sd0),
    .transmission_to_wall(16'sd0),
    .reflection_to_air(16'sd0),
    .transmission_to_air(16'sd0),
    .wave_speed_squared(8'd64),
    .wall_case(5'd0),
    .next_pixel_middle(next_pixel_middle)
);

reg signed [17:0] next_pixel_middle_s3;
reg [31:0] destination_write_addr_s3;
reg init_active_s3;
reg startup_seed_active_s3;
reg center_drive_active_s3;
reg signed [15:0] init_fill_value_s3;
reg signed [15:0] startup_seed_value_s3;
reg swap_memory_s3;

always @(posedge out_stream_aclk) begin
    if (!periph_resetn) begin
        next_pixel_middle_s3 <= 18'sd0;
        destination_write_addr_s3 <= 32'd0;
        init_active_s3 <= 1'b0;
        startup_seed_active_s3 <= 1'b0;
        center_drive_active_s3 <= 1'b0;
        init_fill_value_s3 <= 16'sd0;
        startup_seed_value_s3 <= 16'sd0;
        swap_memory_s3 <= 1'b0;
    end
    else begin
        if (window_valid) begin
            next_pixel_middle_s3 <= next_pixel_middle;
            destination_write_addr_s3 <= window_destination_write_addr;
            init_active_s3 <= window_init_active;
            startup_seed_active_s3 <= window_startup_seed_active;
            center_drive_active_s3 <= window_center_drive_active;
            init_fill_value_s3 <= window_init_fill_value;
            startup_seed_value_s3 <= window_startup_seed_value;
            swap_memory_s3 <= window_swap_memory;
        end
    end
end

wire [8:0] damp_q8;
wire valid_damp;
boundary_damping_coeff damping_coeff(
    .clk(out_stream_aclk),
    .rstn(periph_resetn),
    .valid_in(window_valid),
    .x({2'd0, window_x}),
    .y({2'd0, window_y}),
    .valid_out(valid_damp),
    .damp_q8(damp_q8)
);

reg valid_apply_in;
reg [8:0] damp_q8_apply;

reg [31:0] destination_write_addr_s4;
reg init_active_s4;
reg startup_seed_active_s4;
reg center_drive_active_s4;
reg signed [15:0] init_fill_value_s4;
reg signed [15:0] startup_seed_value_s4;
reg swap_memory_s4;

always @(posedge out_stream_aclk) begin
    if (!periph_resetn) begin
        valid_apply_in <= 1'b0;
        damp_q8_apply <= 9'd256;

        destination_write_addr_s4 <= 32'd0;
        init_active_s4 <= 1'b0;
        startup_seed_active_s4 <= 1'b0;
        center_drive_active_s4 <= 1'b0;
        init_fill_value_s4 <= 16'sd0;
        startup_seed_value_s4 <= 16'sd0;
        swap_memory_s4 <= 1'b0;
    end
    else begin
        valid_apply_in <= valid_damp;

        if (valid_damp) begin
            damp_q8_apply <= damp_q8;
        end

        if (valid_damp) begin
            destination_write_addr_s4 <= destination_write_addr_s3;
            init_active_s4 <= init_active_s3;
            startup_seed_active_s4 <= startup_seed_active_s3;
            center_drive_active_s4 <= center_drive_active_s3;
            init_fill_value_s4 <= init_fill_value_s3;
            startup_seed_value_s4 <= startup_seed_value_s3;
            swap_memory_s4 <= swap_memory_s3;
        end
    end
end

wire pixel_calc_ready;
wire signed [17:0] next_pixel_middle_damped;
reg [31:0] destination_write_addr_s5;
reg init_active_s5;
reg startup_seed_active_s5;
reg center_drive_active_s5;
reg signed [15:0] init_fill_value_s5;
reg signed [15:0] startup_seed_value_s5;
reg swap_memory_s5;

apply_damping #(
    .PRESS_W(18)
) damping (
    .clk(out_stream_aclk),
    .rstn(periph_resetn),
    .valid_in(valid_apply_in),
    .p_raw(next_pixel_middle_s3),
    .damp_q8(damp_q8_apply),
    .valid_out(pixel_calc_ready),
    .p_damped(next_pixel_middle_damped)
);

always @(posedge out_stream_aclk) begin
    if (!periph_resetn) begin
        destination_write_addr_s5 <= 32'd0;
        init_active_s5 <= 1'b0;
        startup_seed_active_s5 <= 1'b0;
        center_drive_active_s5 <= 1'b0;
        init_fill_value_s5 <= 16'sd0;
        startup_seed_value_s5 <= 16'sd0;
        swap_memory_s5 <= 1'b0;
    end
    else if (valid_apply_in) begin
        destination_write_addr_s5 <= destination_write_addr_s4;
        init_active_s5 <= init_active_s4;
        startup_seed_active_s5 <= startup_seed_active_s4;
        center_drive_active_s5 <= center_drive_active_s4;
        init_fill_value_s5 <= init_fill_value_s4;
        startup_seed_value_s5 <= startup_seed_value_s4;
        swap_memory_s5 <= swap_memory_s4;
    end
end

wire signed [15:0] next_pixel_damped_clamped_s5 = clamp_pressure_q6(next_pixel_middle_damped);

wire signed [15:0] next_pixel_with_impulse_s5 =
    startup_seed_active_s5 ? startup_seed_value_s5 :
    center_drive_active_s5 ? sat_add_pressure_wide(next_pixel_middle_damped, source_gain_q6) :
    next_pixel_damped_clamped_s5;

wire [31:0] init_destination_wrdata_s5 =
    {{16{init_fill_value_s5[15]}}, init_fill_value_s5};

wire [31:0] destination_wrdata_s5 =
    {{16{next_pixel_with_impulse_s5[15]}}, next_pixel_with_impulse_s5};

wire write_cur_b = init_active_s5 ? pixel_calc_ready : (pixel_calc_ready & swap_memory_s5);
wire write_prev_b = init_active_s5 ? pixel_calc_ready : (pixel_calc_ready & !swap_memory_s5);
assign port_b_write_active = write_cur_b | write_prev_b;

assign cur_bram_b_en = (ready & valid_int) | pixel_calc_ready | display_read_prime;
assign prev_bram_b_en = (ready & valid_int) | pixel_calc_ready | display_read_prime;

assign cur_bram_b_addr =
    write_cur_b ? destination_write_addr_s5 : display_center_addr;

assign prev_bram_b_addr =
    write_prev_b ? destination_write_addr_s5 : display_center_addr;

assign cur_bram_b_wrdata =
    init_active_s5 ? init_destination_wrdata_s5 :
    (swap_memory_s5 ? destination_wrdata_s5 : 32'd0);

assign prev_bram_b_wrdata =
    init_active_s5 ? init_destination_wrdata_s5 :
    (swap_memory_s5 ? 32'd0 : destination_wrdata_s5);

// 4'b0011 writes the lower two bytes, enough for signed 9-bit pressure.
assign cur_bram_b_we =
    write_cur_b ? 4'b0011 : 4'b0000;

assign prev_bram_b_we =
    write_prev_b ? 4'b0011 : 4'b0000;

always @(posedge out_stream_aclk) begin
    if (!periph_resetn) begin
        port_b_write_active_d <= 1'b0;
    end
    else begin
        port_b_write_active_d <= port_b_write_active;
    end
end

always @(posedge out_stream_aclk) begin
    if (!periph_resetn) begin
        swap_memory <= 1'b0;
        frame_counter <= 8'd0;
    end
    else if (start_pixel_calc & (lastx) & (lasty)) begin
        swap_memory <= ~swap_memory;
        if (frame_counter != 8'hFF) begin
            frame_counter <= frame_counter + 8'd1;
        end
    end
end

wire [15:0] mag;
wire [11:0] mag_scaled;
wire [7:0] vis;
wire [7:0] inv_vis;
wire [7:0] wave_r;
wire [7:0] wave_g;
wire [7:0] wave_b;

assign mag = (cur_pixel_middle > 0) ? cur_pixel_middle : -cur_pixel_middle;
assign mag_scaled = mag[15:4];
assign vis = (mag_scaled > 12'd255) ? 8'hFF : mag_scaled[7:0];
assign inv_vis = 8'hFF - vis;
assign wave_r = (cur_pixel_middle < 0) ? inv_vis : 8'hFF;
assign wave_g = inv_vis;
assign wave_b = (cur_pixel_middle > 0) ? inv_vis : 8'hFF;

assign r = wave_r;
assign g = wave_g;
assign b = wave_b;

assign ready = out_stream_tready;
assign out_stream_tdata = {8'd0, b, g, r};
assign out_stream_tkeep = 4'hF;
assign out_stream_tlast = lastx;
assign out_stream_tvalid = periph_resetn & valid_int;
assign out_stream_tuser = periph_resetn & first;

endmodule
