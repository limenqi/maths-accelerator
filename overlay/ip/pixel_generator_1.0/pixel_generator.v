module pixel_generator #(
parameter AXI_LITE_ADDR_WIDTH = 8,
parameter REG_FILE_SIZE = 8
)(
input           out_stream_aclk,
input           s_axi_lite_aclk,
input           axi_resetn,
input           periph_resetn,

output [31:0]   out_stream_tdata,
output [3:0]    out_stream_tkeep,
output          out_stream_tlast,
input           out_stream_tready,
output          out_stream_tvalid,
output [0:0]    out_stream_tuser,

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

output [31:0]   cur_bram_a_addr,
output          cur_bram_a_clk,
output [31:0]   cur_bram_a_wrdata,
input  [31:0]   cur_bram_a_rddata,
output          cur_bram_a_en,
output          cur_bram_a_rst,
output [3:0]    cur_bram_a_we,

output [31:0]   cur_bram_b_addr,
output          cur_bram_b_clk,
output [31:0]   cur_bram_b_wrdata,
input  [31:0]   cur_bram_b_rddata,
output          cur_bram_b_en,
output          cur_bram_b_rst,
output [3:0]    cur_bram_b_we,

output [31:0]   prev_bram_a_addr,
output          prev_bram_a_clk,
output [31:0]   prev_bram_a_wrdata,
input  [31:0]   prev_bram_a_rddata,
output          prev_bram_a_en,
output          prev_bram_a_rst,
output [3:0]    prev_bram_a_we,

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
localparam [7:0] DEFAULT_WAVE_SPEED_SQUARED_Q8 = 8'd41;
localparam [8:0] DEFAULT_GLOBAL_DAMP_Q8 = 9'd252;
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
(* ASYNC_REG = "TRUE" *) reg [31:0] gp0_pix_meta, gp0_pix;
(* ASYNC_REG = "TRUE" *) reg [31:0] gp1_pix_meta, gp1_pix;
(* ASYNC_REG = "TRUE" *) reg [31:0] gp4_pix_meta, gp4_pix;
(* ASYNC_REG = "TRUE" *) reg [31:0] gp5_pix_meta, gp5_pix;
(* ASYNC_REG = "TRUE" *) reg [31:0] gp6_pix_meta, gp6_pix;

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

always @(posedge s_axi_lite_aclk) begin

    if (!axi_resetn) begin
        writeState <= AWAIT_WADD_AND_DATA;
    end

    else case (writeState)

        AWAIT_WADD_AND_DATA: begin
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

        AWAIT_WDATA: begin
            if (s_axi_lite_wvalid) begin
                writeData <= s_axi_lite_wdata;
                writeState <= AWAIT_WRITE;
            end
        end

        AWAIT_WADD: begin
            if (s_axi_lite_awvalid) begin
                writeAddr <= s_axi_lite_awaddr[2+:REG_FILE_AWIDTH];
                writeState <= AWAIT_WRITE;
            end
        end

        AWAIT_WRITE: begin
            regfile[writeAddr] <= writeData;
            writeState <= AWAIT_RESP;
        end

        AWAIT_RESP: begin
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

always @(posedge out_stream_aclk) begin
    if (!periph_resetn) begin
        gp0_pix_meta <= 32'd0;
        gp0_pix <= 32'd0;
        gp1_pix_meta <= 32'd0;
        gp1_pix <= 32'd0;
        gp4_pix_meta <= 32'd0;
        gp4_pix <= 32'd0;
        gp5_pix_meta <= 32'd0;
        gp5_pix <= 32'd0;
        gp6_pix_meta <= 32'd0;
        gp6_pix <= 32'd0;
    end
    else begin
        gp0_pix_meta <= regfile[0];
        gp0_pix <= gp0_pix_meta;
        gp1_pix_meta <= regfile[1];
        gp1_pix <= gp1_pix_meta;
        gp4_pix_meta <= regfile[4];
        gp4_pix <= gp4_pix_meta;
        gp5_pix_meta <= regfile[5];
        gp5_pix <= gp5_pix_meta;
        gp6_pix_meta <= regfile[6];
        gp6_pix <= gp6_pix_meta;
    end
end

reg [9:0] x;
reg [8:0] y;
reg swap_memory;
reg [7:0] frame_counter;
reg [7:0] source_age_counter;
reg [5:0] source_phase_counter;
reg gp0_fire_d;
reg gp0_clear_d;

wire [7:0] x_val;
wire [6:0] y_val;

assign x_val = x[9:2];
assign y_val = y[8:2];

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
wire signed [15:0] next_pixel_middle;
wire signed [15:0] next_pixel_middle_damped;
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
reg [6:0] y_val_d;
reg [8:0] left_d;
reg [8:0] right_d;
reg [31:0] destination_addr_d;
reg init_active_d;
reg startup_seed_active_d;
reg center_drive_active_d;
reg signed [8:0] init_fill_value_d;
reg signed [8:0] startup_seed_value_d;
reg signed [8:0] center_drive_value_d;
reg swap_memory_d;

wire [31:0] current_stream_addr = {17'd0, addr_y_plus_2[14:0]};
wire [31:0] previous_center_addr = {17'd0, addr_center[14:0]};
wire init_active = (frame_counter < 8'd2);
wire signed [8:0] current_stream_sample_raw = swap_memory ? prev_bram_a_rddata[8:0] : cur_bram_a_rddata[8:0];
wire signed [8:0] previous_center_sample_raw = swap_memory ? cur_bram_a_rddata[8:0] : prev_bram_a_rddata[8:0];
wire signed [8:0] current_stream_sample = init_active ? 9'sd0 : current_stream_sample_raw;
wire signed [8:0] previous_center_sample = init_active ? 9'sd0 : previous_center_sample_raw;
wire [7:0] source_x = (gp1_pix[9:0] == 10'd0) ? 8'd40 : gp1_pix[9:2];
wire [6:0] source_y = (gp1_pix[18:10] == 9'd0) ? 7'd60 : gp1_pix[18:12];
wire [7:0] source_pulse_duration = (gp5_pix[15:8] == 8'd0) ? 8'd100 : gp5_pix[15:8];
wire [5:0] source_phase_step = (gp5_pix[5:0] == 6'd0) ? 6'd1 : gp5_pix[5:0];
wire source_fire_pulse = gp0_pix[0] && !gp0_fire_d;
wire source_clear_pulse = gp0_pix[1] && !gp0_clear_d;
wire startup_seed_active = init_active && (x_val == source_x) && (y_val == source_y);
wire source_pulse_active = source_age_counter < source_pulse_duration;
wire center_drive_active = source_pulse_active && (x_val == source_x) && (y_val == source_y);
wire [7:0] wave_speed_squared_q8 = (gp6_pix[7:0] == 8'd0) ? DEFAULT_WAVE_SPEED_SQUARED_Q8 : gp6_pix[7:0];
wire [8:0] global_damp_q8 = (gp6_pix[16:8] == 9'd0) ? DEFAULT_GLOBAL_DAMP_Q8 : gp6_pix[16:8];
wire signed [8:0] startup_seed_value = sine_lut_q8({frame_counter[0], 5'd0});
wire signed [8:0] source_amplitude = (gp4_pix[7:0] == 8'd0) ? 9'sd160 : {1'b0, gp4_pix[7:0]};
wire signed [8:0] source_sine_q8 = sine_lut_q8(source_phase_counter);
wire signed [17:0] source_scaled_product = source_amplitude * source_sine_q8;
wire signed [8:0] center_drive_value = source_scaled_product >>> 8;
wire signed [8:0] init_fill_value = startup_seed_active ? startup_seed_value : 9'sd0;
wire [31:0] destination_addr = {17'd0, addr_center[14:0]};
reg signed [15:0] next_pixel_middle_damp_s1;
reg [31:0] destination_addr_s1;
reg [31:0] destination_addr_s2;
reg [31:0] destination_addr_s3;
reg init_active_s1;
reg init_active_s2;
reg init_active_s3;
reg startup_seed_active_s1;
reg startup_seed_active_s2;
reg startup_seed_active_s3;
reg center_drive_active_s1;
reg center_drive_active_s2;
reg center_drive_active_s3;
reg signed [8:0] init_fill_value_s1;
reg signed [8:0] init_fill_value_s2;
reg signed [8:0] init_fill_value_s3;
reg signed [8:0] startup_seed_value_s1;
reg signed [8:0] startup_seed_value_s2;
reg signed [8:0] startup_seed_value_s3;
reg signed [8:0] center_drive_value_s1;
reg signed [8:0] center_drive_value_s2;
reg signed [8:0] center_drive_value_s3;
reg swap_memory_s1;
reg swap_memory_s2;
reg swap_memory_s3;
reg sim_cell_tick_s1;
reg valid_apply_in;
reg [8:0] damp_q8_apply;
wire [8:0] damp_q8;
wire valid_damp;
wire valid_damping_out;
wire [17:0] effective_damp_product = damp_q8 * global_damp_q8;
wire [8:0] effective_damp_q8 = effective_damp_product[17:8];
wire signed [8:0] next_pixel_damped_clamped = clamp_pressure_9(next_pixel_middle_damped);
wire signed [8:0] next_pixel_with_impulse = startup_seed_active_s3 ? startup_seed_value_s3 :
                                            center_drive_active_s3 ? sat_add_pressure_wide(next_pixel_middle_damped, center_drive_value_s3) :
                                            next_pixel_damped_clamped;
wire [31:0] init_destination_wrdata = {{23{init_fill_value_s3[8]}}, init_fill_value_s3};
wire [31:0] destination_wrdata = {{23{next_pixel_with_impulse[8]}}, next_pixel_with_impulse};

function signed [8:0] clamp_pressure_9;
    input signed [15:0] a;
    begin
        if (a > 16'sd255)
            clamp_pressure_9 = 9'sd255;
        else if (a < -16'sd256)
            clamp_pressure_9 = -9'sd256;
        else
            clamp_pressure_9 = a[8:0];
    end
endfunction

function signed [8:0] sat_add_pressure_wide;
    input signed [15:0] a;
    input signed [8:0] b;
    reg signed [16:0] sum;
    begin
        sum = a + b;
        if (sum > 17'sd255)
            sat_add_pressure_wide = 9'sd255;
        else if (sum < -17'sd256)
            sat_add_pressure_wide = -9'sd256;
        else
            sat_add_pressure_wide = sum[8:0];
    end
endfunction

function signed [8:0] sine_lut_q8;
    input [5:0] phase;
    begin
        case (phase)
            6'd0: sine_lut_q8 = 9'sd0;
            6'd1: sine_lut_q8 = 9'sd25;
            6'd2: sine_lut_q8 = 9'sd50;
            6'd3: sine_lut_q8 = 9'sd74;
            6'd4: sine_lut_q8 = 9'sd98;
            6'd5: sine_lut_q8 = 9'sd121;
            6'd6: sine_lut_q8 = 9'sd142;
            6'd7: sine_lut_q8 = 9'sd162;
            6'd8: sine_lut_q8 = 9'sd181;
            6'd9: sine_lut_q8 = 9'sd198;
            6'd10: sine_lut_q8 = 9'sd213;
            6'd11: sine_lut_q8 = 9'sd226;
            6'd12: sine_lut_q8 = 9'sd237;
            6'd13: sine_lut_q8 = 9'sd245;
            6'd14: sine_lut_q8 = 9'sd251;
            6'd15: sine_lut_q8 = 9'sd255;
            6'd16: sine_lut_q8 = 9'sd255;
            6'd17: sine_lut_q8 = 9'sd255;
            6'd18: sine_lut_q8 = 9'sd251;
            6'd19: sine_lut_q8 = 9'sd245;
            6'd20: sine_lut_q8 = 9'sd237;
            6'd21: sine_lut_q8 = 9'sd226;
            6'd22: sine_lut_q8 = 9'sd213;
            6'd23: sine_lut_q8 = 9'sd198;
            6'd24: sine_lut_q8 = 9'sd181;
            6'd25: sine_lut_q8 = 9'sd162;
            6'd26: sine_lut_q8 = 9'sd142;
            6'd27: sine_lut_q8 = 9'sd121;
            6'd28: sine_lut_q8 = 9'sd98;
            6'd29: sine_lut_q8 = 9'sd74;
            6'd30: sine_lut_q8 = 9'sd50;
            6'd31: sine_lut_q8 = 9'sd25;
            6'd32: sine_lut_q8 = 9'sd0;
            6'd33: sine_lut_q8 = -9'sd25;
            6'd34: sine_lut_q8 = -9'sd50;
            6'd35: sine_lut_q8 = -9'sd74;
            6'd36: sine_lut_q8 = -9'sd98;
            6'd37: sine_lut_q8 = -9'sd121;
            6'd38: sine_lut_q8 = -9'sd142;
            6'd39: sine_lut_q8 = -9'sd162;
            6'd40: sine_lut_q8 = -9'sd181;
            6'd41: sine_lut_q8 = -9'sd198;
            6'd42: sine_lut_q8 = -9'sd213;
            6'd43: sine_lut_q8 = -9'sd226;
            6'd44: sine_lut_q8 = -9'sd237;
            6'd45: sine_lut_q8 = -9'sd245;
            6'd46: sine_lut_q8 = -9'sd251;
            6'd47: sine_lut_q8 = -9'sd255;
            6'd48: sine_lut_q8 = -9'sd256;
            6'd49: sine_lut_q8 = -9'sd255;
            6'd50: sine_lut_q8 = -9'sd251;
            6'd51: sine_lut_q8 = -9'sd245;
            6'd52: sine_lut_q8 = -9'sd237;
            6'd53: sine_lut_q8 = -9'sd226;
            6'd54: sine_lut_q8 = -9'sd213;
            6'd55: sine_lut_q8 = -9'sd198;
            6'd56: sine_lut_q8 = -9'sd181;
            6'd57: sine_lut_q8 = -9'sd162;
            6'd58: sine_lut_q8 = -9'sd142;
            6'd59: sine_lut_q8 = -9'sd121;
            6'd60: sine_lut_q8 = -9'sd98;
            6'd61: sine_lut_q8 = -9'sd74;
            6'd62: sine_lut_q8 = -9'sd50;
            6'd63: sine_lut_q8 = -9'sd25;
        endcase
    end
endfunction

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
assign cur_bram_b_en = sim_cell_tick | valid_damping_out;
assign prev_bram_b_en = sim_cell_tick | valid_damping_out;

assign cur_bram_a_addr = swap_memory ? previous_center_addr : current_stream_addr;
assign prev_bram_a_addr = swap_memory ? current_stream_addr : previous_center_addr;

assign cur_bram_b_addr = init_active_s3 ? destination_addr_s3 : (swap_memory_s3 ? destination_addr_s3 : 32'd0);
assign prev_bram_b_addr = init_active_s3 ? destination_addr_s3 : (swap_memory_s3 ? 32'd0 : destination_addr_s3);
assign cur_bram_b_wrdata = init_active_s3 ? init_destination_wrdata : (swap_memory_s3 ? destination_wrdata : 32'd0);
assign prev_bram_b_wrdata = init_active_s3 ? init_destination_wrdata : (swap_memory_s3 ? 32'd0 : destination_wrdata);
assign cur_bram_b_we = init_active_s3 ? (valid_damping_out ? 4'b0011 : 4'b0000) :
                       ((valid_damping_out & swap_memory_s3) ? 4'b0011 : 4'b0000);
assign prev_bram_b_we = init_active_s3 ? (valid_damping_out ? 4'b0011 : 4'b0000) :
                        ((valid_damping_out & !swap_memory_s3) ? 4'b0011 : 4'b0000);

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
    y_val_d = 7'd0;
    left_d = 9'd0;
    right_d = 9'd0;
    destination_addr_d = 32'd0;
    init_active_d = 1'b0;
    startup_seed_active_d = 1'b0;
    center_drive_active_d = 1'b0;
    init_fill_value_d = 9'sd0;
    startup_seed_value_d = 9'sd0;
    center_drive_value_d = 9'sd0;
    swap_memory_d = 1'b0;
    next_pixel_middle_damp_s1 = 9'sd0;
    destination_addr_s1 = 32'd0;
    destination_addr_s2 = 32'd0;
    destination_addr_s3 = 32'd0;
    init_active_s1 = 1'b0;
    init_active_s2 = 1'b0;
    init_active_s3 = 1'b0;
    startup_seed_active_s1 = 1'b0;
    startup_seed_active_s2 = 1'b0;
    startup_seed_active_s3 = 1'b0;
    center_drive_active_s1 = 1'b0;
    center_drive_active_s2 = 1'b0;
    center_drive_active_s3 = 1'b0;
    init_fill_value_s1 = 9'sd0;
    init_fill_value_s2 = 9'sd0;
    init_fill_value_s3 = 9'sd0;
    startup_seed_value_s1 = 9'sd0;
    startup_seed_value_s2 = 9'sd0;
    startup_seed_value_s3 = 9'sd0;
    center_drive_value_s1 = 9'sd0;
    center_drive_value_s2 = 9'sd0;
    center_drive_value_s3 = 9'sd0;
    swap_memory_s1 = 1'b0;
    swap_memory_s2 = 1'b0;
    swap_memory_s3 = 1'b0;
    sim_cell_tick_s1 = 1'b0;
    valid_apply_in = 1'b0;
    damp_q8_apply = 9'd256;
    frame_counter = 8'd0;
    source_age_counter = 8'hFF;
    source_phase_counter = 6'd0;
    gp0_fire_d = 1'b0;
    gp0_clear_d = 1'b0;
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
        y_val_d <= 7'd0;
        left_d <= 9'd0;
        right_d <= 9'd0;
        destination_addr_d <= 32'd0;
        init_active_d <= 1'b0;
        startup_seed_active_d <= 1'b0;
        center_drive_active_d <= 1'b0;
        init_fill_value_d <= 9'sd0;
        startup_seed_value_d <= 9'sd0;
        center_drive_value_d <= 9'sd0;
        swap_memory_d <= 1'b0;
    end
    else if (source_clear_pulse) begin
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
        y_val_d <= 7'd0;
        left_d <= 9'd0;
        right_d <= 9'd0;
        destination_addr_d <= 32'd0;
        init_active_d <= 1'b0;
        startup_seed_active_d <= 1'b0;
        center_drive_active_d <= 1'b0;
        init_fill_value_d <= 9'sd0;
        startup_seed_value_d <= 9'sd0;
        center_drive_value_d <= 9'sd0;
        swap_memory_d <= 1'b0;
    end
    else if (sim_cell_tick) begin
        x_val_d <= x_val;
        y_val_d <= y_val;
        left_d <= left;
        right_d <= right;
        destination_addr_d <= destination_addr;
        init_active_d <= init_active;
        startup_seed_active_d <= startup_seed_active;
        center_drive_active_d <= center_drive_active;
        init_fill_value_d <= init_fill_value;
        startup_seed_value_d <= startup_seed_value;
        center_drive_value_d <= center_drive_value;
        swap_memory_d <= swap_memory;
        prev_pixel_middle_reg <= previous_center_sample;
        if (sim_row_end) begin
            for (col = 0; col < SIM_X_SIZE; col = col + 1) begin
                row_y_minus_1[col] <= row_y[col];
                row_y[col] <= row_y_plus_1[col];
                row_y_plus_1[col] <= row_y_plus_2[col];
            end
        end
        row_y_plus_2[x_val_d] <= current_stream_sample;
        top_center <= (y_val_d == 7'd0) ? row_y[x_val_d] : row_y_minus_1[x_val_d];
        mid_left <= row_y[left_d];
        mid_center <= row_y[x_val_d];
        mid_right <= row_y[right_d];
        bot_center <= (y_val_d == (SIM_Y_SIZE - 1)) ? row_y[x_val_d] : row_y_plus_1[x_val_d];
    end
end

always @(posedge out_stream_aclk) begin
    if (!periph_resetn) begin
        next_pixel_middle_damp_s1 <= 9'sd0;
        destination_addr_s1 <= 32'd0;
        destination_addr_s2 <= 32'd0;
        destination_addr_s3 <= 32'd0;
        init_active_s1 <= 1'b0;
        init_active_s2 <= 1'b0;
        init_active_s3 <= 1'b0;
        startup_seed_active_s1 <= 1'b0;
        startup_seed_active_s2 <= 1'b0;
        startup_seed_active_s3 <= 1'b0;
        center_drive_active_s1 <= 1'b0;
        center_drive_active_s2 <= 1'b0;
        center_drive_active_s3 <= 1'b0;
        init_fill_value_s1 <= 9'sd0;
        init_fill_value_s2 <= 9'sd0;
        init_fill_value_s3 <= 9'sd0;
        startup_seed_value_s1 <= 9'sd0;
        startup_seed_value_s2 <= 9'sd0;
        startup_seed_value_s3 <= 9'sd0;
        center_drive_value_s1 <= 9'sd0;
        center_drive_value_s2 <= 9'sd0;
        center_drive_value_s3 <= 9'sd0;
        swap_memory_s1 <= 1'b0;
        swap_memory_s2 <= 1'b0;
        swap_memory_s3 <= 1'b0;
        sim_cell_tick_s1 <= 1'b0;
        valid_apply_in <= 1'b0;
        damp_q8_apply <= 9'd256;
    end
    else begin
        sim_cell_tick_s1 <= sim_cell_tick;

        if (source_clear_pulse) begin
            next_pixel_middle_damp_s1 <= 9'sd0;
            destination_addr_s1 <= 32'd0;
            destination_addr_s2 <= 32'd0;
            destination_addr_s3 <= 32'd0;
            init_active_s1 <= 1'b0;
            init_active_s2 <= 1'b0;
            init_active_s3 <= 1'b0;
            startup_seed_active_s1 <= 1'b0;
            startup_seed_active_s2 <= 1'b0;
            startup_seed_active_s3 <= 1'b0;
            center_drive_active_s1 <= 1'b0;
            center_drive_active_s2 <= 1'b0;
            center_drive_active_s3 <= 1'b0;
            init_fill_value_s1 <= 9'sd0;
            init_fill_value_s2 <= 9'sd0;
            init_fill_value_s3 <= 9'sd0;
            startup_seed_value_s1 <= 9'sd0;
            startup_seed_value_s2 <= 9'sd0;
            startup_seed_value_s3 <= 9'sd0;
            center_drive_value_s1 <= 9'sd0;
            center_drive_value_s2 <= 9'sd0;
            center_drive_value_s3 <= 9'sd0;
            swap_memory_s1 <= 1'b0;
            swap_memory_s2 <= 1'b0;
            swap_memory_s3 <= 1'b0;
            valid_apply_in <= 1'b0;
            damp_q8_apply <= 9'd256;
        end
        else begin
            if (sim_cell_tick) begin
                destination_addr_s1 <= destination_addr_d;
                init_active_s1 <= init_active_d;
                startup_seed_active_s1 <= startup_seed_active_d;
                center_drive_active_s1 <= center_drive_active_d;
                init_fill_value_s1 <= init_fill_value_d;
                startup_seed_value_s1 <= startup_seed_value_d;
                center_drive_value_s1 <= center_drive_value_d;
                swap_memory_s1 <= swap_memory_d;
            end

            if (sim_cell_tick_s1) begin
                next_pixel_middle_damp_s1 <= next_pixel_middle;
            end

            valid_apply_in <= valid_damp;
            damp_q8_apply <= effective_damp_q8;

            if (valid_damp) begin
                destination_addr_s2 <= destination_addr_s1;
                init_active_s2 <= init_active_s1;
                startup_seed_active_s2 <= startup_seed_active_s1;
                center_drive_active_s2 <= center_drive_active_s1;
                init_fill_value_s2 <= init_fill_value_s1;
                startup_seed_value_s2 <= startup_seed_value_s1;
                center_drive_value_s2 <= center_drive_value_s1;
                swap_memory_s2 <= swap_memory_s1;
            end

            if (valid_apply_in) begin
                destination_addr_s3 <= destination_addr_s2;
                init_active_s3 <= init_active_s2;
                startup_seed_active_s3 <= startup_seed_active_s2;
                center_drive_active_s3 <= center_drive_active_s2;
                init_fill_value_s3 <= init_fill_value_s2;
                startup_seed_value_s3 <= startup_seed_value_s2;
                center_drive_value_s3 <= center_drive_value_s2;
                swap_memory_s3 <= swap_memory_s2;
            end
        end
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
    .reflection_to_wall(9'sd0),
    .transmission_to_wall(9'sd0),
    .reflection_to_air(9'sd0),
    .transmission_to_air(9'sd0),
    .wave_speed_squared(wave_speed_squared_q8),
    .wall_case(5'd0),
    .next_pixel_middle(next_pixel_middle)
);

boundary_damping_coeff #(
    .WIDTH(320),
    .HEIGHT(240),
    .BORDER(50)
) damping_coeff (
    .clk(out_stream_aclk),
    .rstn(periph_resetn),
    .valid_in(sim_cell_tick),
    .x({1'b0, x_val_d, 1'b0}),
    .y({1'b0, y_val_d, 1'b0}),
    .valid_out(valid_damp),
    .damp_q8(damp_q8)
);

apply_damping #(
    .PRESS_W(16)
) damping (
    .clk(out_stream_aclk),
    .rstn(periph_resetn),
    .valid_in(valid_apply_in),
    .p_raw(next_pixel_middle_damp_s1),
    .damp_q8(damp_q8_apply),
    .valid_out(valid_damping_out),
    .p_damped(next_pixel_middle_damped)
);

always @(posedge out_stream_aclk) begin
    if (!periph_resetn) begin
        swap_memory <= 1'b0;
        frame_counter <= 8'd0;
        source_age_counter <= 8'hFF;
        source_phase_counter <= 6'd0;
        gp0_fire_d <= 1'b0;
        gp0_clear_d <= 1'b0;
    end
    else begin
        gp0_fire_d <= gp0_pix[0];
        gp0_clear_d <= gp0_pix[1];

        if (source_clear_pulse) begin
            swap_memory <= 1'b0;
            frame_counter <= 8'd0;
            source_age_counter <= 8'hFF;
            source_phase_counter <= 6'd0;
        end
        else begin
            if (source_fire_pulse) begin
                source_age_counter <= 8'd0;
                source_phase_counter <= 6'd0;
            end

            if (sim_cell_tick & (lastx) & (lasty)) begin
                swap_memory <= ~swap_memory;
                if (!source_fire_pulse && source_age_counter < source_pulse_duration) begin
                    source_age_counter <= source_age_counter + 8'd1;
                    source_phase_counter <= source_phase_counter + source_phase_step;
                end
                if (frame_counter != 8'hFF) begin
                    frame_counter <= frame_counter + 8'd1;
                end
            end
        end
    end
end

wire [8:0] mag;
wire [10:0] mag_scaled;
wire [7:0] vis;
wire [7:0] inv_vis;
wire [7:0] wave_r;
wire [7:0] wave_g;
wire [7:0] wave_b;

assign mag = (cur_pixel_middle > 0) ? cur_pixel_middle : -cur_pixel_middle;
assign mag_scaled = {mag, 2'b00};
assign vis = (mag_scaled > 11'd255) ? 8'hFF : mag_scaled[7:0];
assign inv_vis = 8'hFF - vis;
assign wave_r = (cur_pixel_middle < 0) ? inv_vis : 8'hFF;
assign wave_g = inv_vis;
assign wave_b = (cur_pixel_middle > 0) ? inv_vis : 8'hFF;

assign r = wave_r;
assign g = wave_g;
assign b = wave_b;

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
