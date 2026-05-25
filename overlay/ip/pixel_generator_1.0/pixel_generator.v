

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

wire first = (x == 0) & (y==0);
wire lastx = (x == X_SIZE - 1);
wire lasty = (y == Y_SIZE - 1);

reg [31:0] gp0_vid;
reg [31:0] gp1_vid;
reg [31:0] gp2_vid;
reg [31:0] gp3_vid;
reg [31:0] gp4_vid;

wire [7:0] frame = gp0_vid[7:0];
wire ready;

always @(posedge out_stream_aclk) begin
    if (!periph_resetn) begin
        gp0_vid <= 32'd0;
        gp1_vid <= 32'd0;
        gp2_vid <= 32'd0;
        gp3_vid <= 32'd0;
        gp4_vid <= 32'd0;
    end
    else if (first) begin
        gp0_vid <= regfile[0];
        gp1_vid <= regfile[1];
        gp2_vid <= regfile[2];
        gp3_vid <= regfile[3];
        gp4_vid <= regfile[4];
    end
end

always @(posedge out_stream_aclk) begin
    if (periph_resetn) begin
        if (ready & valid_int) begin
            if (lastx) begin
                x <= 10'd0;
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



function [11:0] abs12;
    input signed [11:0] value;
    begin
        abs12 = value[11] ? (~value[11:0] + 12'd1) : value[11:0];
    end
endfunction

function signed [7:0] wave_lut;
    input [4:0] phase;
    begin
        case (phase)
            5'd0:  wave_lut = 8'sd0;
            5'd1:  wave_lut = 8'sd18;
            5'd2:  wave_lut = 8'sd36;
            5'd3:  wave_lut = 8'sd55;
            5'd4:  wave_lut = 8'sd72;
            5'd5:  wave_lut = 8'sd86;
            5'd6:  wave_lut = 8'sd96;
            5'd7:  wave_lut = 8'sd86;
            5'd8:  wave_lut = 8'sd72;
            5'd9:  wave_lut = 8'sd55;
            5'd10: wave_lut = 8'sd36;
            5'd11: wave_lut = 8'sd18;
            5'd12: wave_lut = 8'sd0;
            5'd13: wave_lut = -8'sd12;
            5'd14: wave_lut = -8'sd24;
            5'd15: wave_lut = -8'sd36;
            5'd16: wave_lut = -8'sd48;
            5'd17: wave_lut = -8'sd56;
            5'd18: wave_lut = -8'sd64;
            5'd19: wave_lut = -8'sd56;
            5'd20: wave_lut = -8'sd48;
            5'd21: wave_lut = -8'sd36;
            5'd22: wave_lut = -8'sd24;
            5'd23: wave_lut = -8'sd12;
            5'd24: wave_lut = 8'sd0;
            5'd25: wave_lut = 8'sd10;
            5'd26: wave_lut = 8'sd20;
            5'd27: wave_lut = 8'sd28;
            5'd28: wave_lut = 8'sd20;
            5'd29: wave_lut = 8'sd10;
            5'd30: wave_lut = 8'sd0;
            default: wave_lut = -8'sd8;
        endcase
    end
endfunction

function signed [7:0] attenuate_wave;
    input signed [7:0] wave;
    input [11:0] dist;
    begin
        if (dist < 12'd80) begin
            attenuate_wave = wave;
        end
        else if (dist < 12'd160) begin
            attenuate_wave = wave >>> 1;
        end
        else if (dist < 12'd260) begin
            attenuate_wave = wave >>> 2;
        end
        else begin
            attenuate_wave = wave >>> 3;
        end
    end
endfunction

function signed [8:0] clamp_pressure;
    input signed [9:0] value;
    begin
        if (value > 10'sd127) begin
            clamp_pressure = 9'sd127;
        end
        else if (value < -10'sd96) begin
            clamp_pressure = -9'sd96;
        end
        else begin
            clamp_pressure = value[8:0];
        end
    end
endfunction

function [23:0] pressure_to_rgb;
    input signed [8:0] pressure;
    begin
        if (pressure < -9'sd64) begin
            pressure_to_rgb = {8'd0, 8'd0, 8'd92};
        end
        else if (pressure < -9'sd32) begin
            pressure_to_rgb = {8'd0, 8'd8, 8'd125};
        end
        else if (pressure < -9'sd12) begin
            pressure_to_rgb = {8'd0, 8'd18, 8'd150};
        end
        else if (pressure < 9'sd8) begin
            pressure_to_rgb = {8'd0, 8'd2, 8'd32};
        end
        else if (pressure < 9'sd26) begin
            pressure_to_rgb = {8'd0, 8'd18, 8'd88};
        end
        else if (pressure < 9'sd46) begin
            pressure_to_rgb = {8'd0, 8'd78, 8'd170};
        end
        else if (pressure < 9'sd66) begin
            pressure_to_rgb = {8'd0, 8'd170, 8'd210};
        end
        else if (pressure < 9'sd88) begin
            pressure_to_rgb = {8'd45, 8'd190, 8'd210};
        end
        else if (pressure < 9'sd110) begin
            pressure_to_rgb = {8'd230, 8'd190, 8'd45};
        end
        else begin
            pressure_to_rgb = {8'd255, 8'd90, 8'd16};
        end
    end
endfunction

function [7:0] absdiff8;
    input [7:0] a;
    input [7:0] b;
    begin
        absdiff8 = (a > b) ? (a - b) : (b - a);
    end
endfunction


localparam signed [11:0] SRC_X = 12'sd120;
localparam signed [11:0] SRC_Y = 12'sd300;

localparam signed [11:0] OBJ_X = 12'sd300;
localparam signed [11:0] OBJ_Y = 12'sd300;

localparam signed [11:0] RX_X  = 12'sd560;
localparam signed [11:0] RX_Y  = 12'sd300;

localparam signed [11:0] REF_X = 12'sd319;
localparam signed [11:0] REF_Y = 12'sd300;

localparam [23:0] OBJ_R2_INNER = 24'd1296; 
localparam [23:0] OBJ_R2       = 24'd1444; 
localparam [23:0] OBJ_R2_OUTER = 24'd1600; 

localparam [23:0] SRC_CORE_R2  = 24'd16;   
localparam [23:0] SRC_RING_IN2 = 24'd25;   
localparam [23:0] SRC_RING_OUT2 = 24'd64;  

localparam [23:0] RX_CORE_R2   = 24'd9;   
localparam [23:0] RX_RING_IN2  = 24'd49;   
localparam [23:0] RX_RING_OUT2 = 24'd121;  

localparam [7:0] HIT_DIST = 8'd142;

(* rom_style = "block" *) reg [9:0] sqrt_rom_src [0:8191];
(* rom_style = "block" *) reg [9:0] sqrt_rom_ref [0:8191];

initial begin
    $readmemh("sqrt_lut.mem", sqrt_rom_src);
    $readmemh("sqrt_lut.mem", sqrt_rom_ref);
end


wire signed [11:0] px = {2'b00, x};
wire signed [11:0] py = {3'b000, y};


reg [7:0] pulse_counter;

always @(posedge out_stream_aclk) begin
    if (!periph_resetn) begin
        pulse_counter <= 8'd0;
    end
    else if (first && ready) begin
        pulse_counter <= pulse_counter + 8'd1;
    end
end

wire [7:0] pulse_scaled = pulse_counter;



wire signed [11:0] dx_s_signed = px - SRC_X;
wire signed [11:0] dy_s_signed = py - SRC_Y;
wire signed [23:0] dx_s_sq_signed = dx_s_signed * dx_s_signed;
wire signed [23:0] dy_s_sq_signed = dy_s_signed * dy_s_signed;
wire [23:0] src_r2 = dx_s_sq_signed[23:0] + dy_s_sq_signed[23:0];
wire [12:0] src_sqrt_addr = src_r2[18:6];



wire signed [11:0] dx_o_signed = px - OBJ_X;
wire signed [11:0] dy_o_signed = py - OBJ_Y;
wire signed [23:0] dx_o_sq_signed = dx_o_signed * dx_o_signed;
wire signed [23:0] dy_o_sq_signed = dy_o_signed * dy_o_signed;
wire [23:0] obj_r2 = dx_o_sq_signed[23:0] + dy_o_sq_signed[23:0];

wire inside_object = (obj_r2 <= OBJ_R2);
wire object_rim = (obj_r2 >= OBJ_R2_INNER) && (obj_r2 <= OBJ_R2_OUTER);

wire source_core = (src_r2 <= SRC_CORE_R2);
wire source_ring = (src_r2 >= SRC_RING_IN2) && (src_r2 <= SRC_RING_OUT2);
wire source_marker = source_core || source_ring;

wire signed [11:0] dx_rx_signed = px - RX_X;
wire signed [11:0] dy_rx_signed = py - RX_Y;
wire signed [23:0] dx_rx_sq_signed = dx_rx_signed * dx_rx_signed;
wire signed [23:0] dy_rx_sq_signed = dy_rx_signed * dy_rx_signed;
wire [23:0] rx_r2 = dx_rx_sq_signed[23:0] + dy_rx_sq_signed[23:0];
wire receiver_core = (rx_r2 <= RX_CORE_R2);
wire receiver_ring = (rx_r2 >= RX_RING_IN2) && (rx_r2 <= RX_RING_OUT2);
wire receiver_marker = receiver_core || receiver_ring;



wire signed [11:0] dx_ref_signed = px - REF_X;
wire signed [11:0] dy_ref_signed = py - REF_Y;
wire signed [23:0] dx_ref_sq_signed = dx_ref_signed * dx_ref_signed;
wire signed [23:0] dy_ref_sq_signed = dy_ref_signed * dy_ref_signed;
wire [23:0] ref_r2 = dx_ref_sq_signed[23:0] + dy_ref_sq_signed[23:0];
wire [12:0] ref_sqrt_addr = ref_r2[18:6];

wire behind_object = (px > OBJ_X);
wire [11:0] lobe_x = behind_object ? (px - OBJ_X) : 12'd0;
wire [11:0] lobe_half = (lobe_x >> 1) + 12'd20;
wire [23:0] lobe_half_r2 = lobe_half * lobe_half;
wire lobe_mask = behind_object &&
                 (lobe_x < 12'd230) &&
                 (dy_o_sq_signed[23:0] <= lobe_half_r2);

wire ref_active = (pulse_scaled > HIT_DIST);
wire [7:0] ref_age = pulse_scaled - HIT_DIST;



reg first_d1;
reg lastx_d1;
reg valid_d1;
reg [7:0] pulse_scaled_d1;
reg [7:0] ref_age_d1;
reg [9:0] dist_s_true_d1;
reg [9:0] dist_ref_true_d1;
reg inside_object_d1;
reg object_rim_d1;
reg source_marker_d1;
reg receiver_marker_d1;
reg object_front_d1;
reg lobe_mask_d1;
reg ref_active_d1;

always @(posedge out_stream_aclk) begin
    if (!periph_resetn) begin
        first_d1 <= 1'b0;
        lastx_d1 <= 1'b0;
        valid_d1 <= 1'b0;
        pulse_scaled_d1 <= 8'd0;
        ref_age_d1 <= 8'd0;
        dist_s_true_d1 <= 10'd0;
        dist_ref_true_d1 <= 10'd0;
        inside_object_d1 <= 1'b0;
        object_rim_d1 <= 1'b0;
        source_marker_d1 <= 1'b0;
        receiver_marker_d1 <= 1'b0;
        object_front_d1 <= 1'b0;
        lobe_mask_d1 <= 1'b0;
        ref_active_d1 <= 1'b0;
    end
    else if (ready & valid_int) begin
        first_d1 <= first;
        lastx_d1 <= lastx;
        valid_d1 <= valid_int;
        pulse_scaled_d1 <= pulse_scaled;
        ref_age_d1 <= ref_age;
        dist_s_true_d1 <= sqrt_rom_src[src_sqrt_addr];
        dist_ref_true_d1 <= sqrt_rom_ref[ref_sqrt_addr];
        inside_object_d1 <= inside_object;
        object_rim_d1 <= object_rim;
        source_marker_d1 <= source_marker;
        receiver_marker_d1 <= receiver_marker;
        object_front_d1 <= (px < OBJ_X);
        lobe_mask_d1 <= lobe_mask;
        ref_active_d1 <= ref_active;
    end
end

wire [11:0] phase_s = {2'd0, dist_s_true_d1} - {4'd0, pulse_scaled_d1};
wire signed [7:0] wave_s = wave_lut(phase_s[4:0]);
wire signed [7:0] pressure_src = attenuate_wave(wave_s, {2'd0, dist_s_true_d1});

wire [11:0] phase_ref = {2'd0, dist_ref_true_d1} - {4'd0, ref_age_d1};
wire signed [7:0] wave_ref = wave_lut(phase_ref[4:0]);
wire signed [7:0] pressure_ref_base = attenuate_wave(wave_ref, {2'd0, dist_ref_true_d1});
wire signed [7:0] pressure_ref_weak = pressure_ref_base >>> 1;
wire signed [7:0] pressure_ref =
    (ref_active_d1 && lobe_mask_d1) ? pressure_ref_weak : 8'sd0;

wire signed [7:0] lobe_texture = 8'sd0;



wire signed [9:0] pressure_sum =
    {{2{pressure_src[7]}}, pressure_src} +
    {{2{pressure_ref[7]}}, pressure_ref} +
    {{2{lobe_texture[7]}}, lobe_texture};

wire signed [8:0] pressure_total = clamp_pressure(pressure_sum);
wire [23:0] field_rgb = pressure_to_rgb(pressure_total);

wire [7:0] field_r = field_rgb[23:16];
wire [7:0] field_g = field_rgb[15:8];
wire [7:0] field_b = field_rgb[7:0];


wire [7:0] pulse_hit_diff = absdiff8(pulse_scaled_d1, HIT_DIST);
wire pulse_hits_object = (pulse_hit_diff < 8'd7);
wire object_hit_highlight = object_rim_d1 && object_front_d1 && pulse_hits_object;

wire [7:0] r, g, b;

assign r =
    receiver_marker_d1     ? 8'd25  :
    source_marker_d1       ? 8'd255 :
    object_hit_highlight   ? 8'd255 :
    object_rim_d1          ? 8'd145 :
    inside_object_d1       ? 8'd54  :
                             field_r;

assign g =
    receiver_marker_d1     ? 8'd225 :
    source_marker_d1       ? 8'd232 :
    object_hit_highlight   ? 8'd245 :
    object_rim_d1          ? 8'd145 :
    inside_object_d1       ? 8'd54  :
                             field_g;

assign b =
    receiver_marker_d1     ? 8'd80  :
    source_marker_d1       ? 8'd45  :
    object_hit_highlight   ? 8'd130 :
    object_rim_d1          ? 8'd150 :
    inside_object_d1       ? 8'd58  :
                             field_b;
packer pixel_packer(    .aclk(out_stream_aclk),
                        .aresetn(periph_resetn),
                        .r(r), .g(b), .b(g),
                        .eol(lastx_d1), .in_stream_ready(ready), .valid(valid_d1), .sof(first_d1),
                        .out_stream_tdata(out_stream_tdata), .out_stream_tkeep(out_stream_tkeep),
                        .out_stream_tlast(out_stream_tlast), .out_stream_tready(out_stream_tready),
                        .out_stream_tvalid(out_stream_tvalid), .out_stream_tuser(out_stream_tuser) );

 
endmodule
