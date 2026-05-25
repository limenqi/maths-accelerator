
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

// ================================================================
// EchoVision V7.1 Visual Renderer
// Circular r2 pressure-field renderer.
// Keep AXI-Lite, AXI-Stream, x/y counters, and packer unchanged.
// ================================================================

function [7:0] sat_add8;
    input [7:0] a;
    input [7:0] b;
    reg [8:0] sum;
    begin
        sum = {1'b0, a} + {1'b0, b};
        sat_add8 = sum[8] ? 8'hFF : sum[7:0];
    end
endfunction

function [7:0] sat_sub8;
    input [7:0] a;
    input [7:0] b;
    begin
        sat_sub8 = (a > b) ? (a - b) : 8'd0;
    end
endfunction

function [7:0] absdiff8;
    input [7:0] a;
    input [7:0] b;
    begin
        absdiff8 = (a > b) ? (a - b) : (b - a);
    end
endfunction

// ---------------- Hardcoded V7.1 scene ----------------
localparam signed [11:0] SRC_X = 12'sd120;
localparam signed [11:0] SRC_Y = 12'sd300;

localparam signed [11:0] OBJ_X = 12'sd300;
localparam signed [11:0] OBJ_Y = 12'sd300;

localparam signed [11:0] RX_X  = 12'sd560;
localparam signed [11:0] RX_Y  = 12'sd300;

localparam [23:0] OBJ_R2_INNER = 24'd1296; // 36*36
localparam [23:0] OBJ_R2       = 24'd1444; // 38*38
localparam [23:0] OBJ_R2_OUTER = 24'd1600; // 40*40

localparam [7:0] HIT_DIST = 8'd142;

// Current pixel as signed numbers.
wire signed [11:0] px = {2'b00, x};
wire signed [11:0] py = {3'b000, y};

// Local video-clock-domain animation pulse.
reg [7:0] pulse_counter;

always @(posedge out_stream_aclk) begin
    if (!periph_resetn) begin
        pulse_counter <= 8'd0;
    end
    else if (first && ready) begin
        pulse_counter <= pulse_counter + 8'd1;
    end
end

wire [7:0] pulse = pulse_counter;

// ================================================================
// 1. Circular source pressure field using squared distance.
// ================================================================

wire signed [11:0] dx_s_signed = px - SRC_X;
wire signed [11:0] dy_s_signed = py - SRC_Y;

wire signed [23:0] dx_s_sq_signed = dx_s_signed * dx_s_signed;
wire signed [23:0] dy_s_sq_signed = dy_s_signed * dy_s_signed;
wire [23:0] r2_s = dx_s_sq_signed[23:0] + dy_s_sq_signed[23:0];

wire [7:0] source_phase = r2_s[14:7] - pulse;
wire [4:0] source_phase_fold =
    source_phase[4] ? (5'd31 - source_phase[4:0]) : source_phase[4:0];

wire [7:0] source_band_soft =
    (source_phase_fold < 5'd2)  ? 8'd190 :
    (source_phase_fold < 5'd4)  ? 8'd145 :
    (source_phase_fold < 5'd7)  ? 8'd95  :
    (source_phase_fold < 5'd11) ? 8'd42  :
                                  8'd12;

wire [7:0] source_atten =
    (r2_s[23:19] != 5'd0) ? 8'd180 : {2'b00, r2_s[18:13]};

wire [7:0] source_pressure = sat_sub8(source_band_soft, source_atten);

// ================================================================
// 2. Circular object and reflected lobe geometry.
// ================================================================

wire signed [11:0] dx_o_signed = px - OBJ_X;
wire signed [11:0] dy_o_signed = py - OBJ_Y;

wire signed [23:0] dx_o_sq_signed = dx_o_signed * dx_o_signed;
wire signed [23:0] dy_o_sq_signed = dy_o_signed * dy_o_signed;
wire [23:0] obj_r2 = dx_o_sq_signed[23:0] + dy_o_sq_signed[23:0];

wire inside_object = (obj_r2 < OBJ_R2);
wire near_edge = (obj_r2 >= OBJ_R2_INNER) && (obj_r2 <= OBJ_R2_OUTER);

wire behind_object = (px > OBJ_X);
wire [11:0] echo_x_from_obj = behind_object ? (px - OBJ_X) : 12'd0;
wire [23:0] echo_y_limit_r2 =
    ((echo_x_from_obj + 12'd28) * (echo_x_from_obj + 12'd28)) >> 2;

wire echo_lobe_mask = behind_object &&
                      (echo_x_from_obj < 12'd210) &&
                      (dy_o_sq_signed[23:0] < echo_y_limit_r2);

wire echo_active = (pulse > HIT_DIST);
wire [7:0] echo_age = pulse - HIT_DIST;
wire [7:0] echo_phase = obj_r2[13:6] - echo_age;
wire [4:0] echo_phase_fold =
    echo_phase[4] ? (5'd31 - echo_phase[4:0]) : echo_phase[4:0];

wire [7:0] echo_band_soft =
    (echo_phase_fold < 5'd3)  ? 8'd78 :
    (echo_phase_fold < 5'd6)  ? 8'd54 :
    (echo_phase_fold < 5'd10) ? 8'd30 :
                                8'd10;

wire [7:0] echo_atten =
    (echo_x_from_obj > 12'd180) ? 8'd70 : {2'b00, echo_x_from_obj[7:2]};

wire scatter = x[4] ^ y[3] ^ x[6] ^ y[5];
wire [7:0] echo_scatter = scatter ? 8'd10 : 8'd0;
wire [7:0] echo_pressure_raw = sat_sub8(echo_band_soft, echo_atten);
wire [7:0] echo_pressure =
    (echo_active && echo_lobe_mask) ? sat_sub8(echo_pressure_raw, echo_scatter) : 8'd0;

// ================================================================
// 3. Combined pressure intensity and navy background.
// ================================================================

wire [8:0] y_inv = 9'd479 - y;
wire [7:0] bg_blue = 8'd24 + {3'b000, y_inv[8:4]};
wire [7:0] bg_green = 8'd6 + {5'b00000, y_inv[8:6]};

wire [7:0] pressure_intensity = sat_add8(source_pressure, echo_pressure);

// ================================================================
// 4. Pressure-field palette.
// ================================================================

wire [7:0] pal_r =
    (pressure_intensity < 8'd28)  ? 8'd0 :
    (pressure_intensity < 8'd72)  ? 8'd0 :
    (pressure_intensity < 8'd116) ? 8'd18 :
    (pressure_intensity < 8'd170) ? (pressure_intensity + 8'd50) :
                                    8'd255;

wire [7:0] pal_g =
    (pressure_intensity < 8'd28)  ? (8'd18 + (pressure_intensity >> 2)) :
    (pressure_intensity < 8'd72)  ? (8'd70 + pressure_intensity) :
    (pressure_intensity < 8'd116) ? 8'd210 :
    (pressure_intensity < 8'd170) ? 8'd235 :
                                    (8'd235 - (pressure_intensity >> 3));

wire [7:0] pal_b =
    (pressure_intensity < 8'd28)  ? (8'd80 + pressure_intensity) :
    (pressure_intensity < 8'd72)  ? 8'd235 :
    (pressure_intensity < 8'd116) ? 8'd160 :
    (pressure_intensity < 8'd170) ? 8'd40 :
                                    8'd18;

wire [7:0] field_r = (pressure_intensity == 8'd0) ? 8'd0        : pal_r;
wire [7:0] field_g = (pressure_intensity == 8'd0) ? bg_green    : pal_g;
wire [7:0] field_b = (pressure_intensity == 8'd0) ? bg_blue     : pal_b;

// ================================================================
// 5. Hit highlight, source marker, and receiver marker.
// ================================================================

wire [7:0] pulse_hit_diff = absdiff8(pulse, HIT_DIST);
wire pulse_hits_object = (pulse_hit_diff < 8'd10);
wire front_side = (px < OBJ_X);
wire object_hit_highlight = near_edge && front_side && pulse_hits_object;

wire source_marker = (r2_s < 24'd36) ||
                     (((dx_s_signed > -12'sd2) && (dx_s_signed < 12'sd2) &&
                       (dy_s_signed > -12'sd9) && (dy_s_signed < 12'sd9)) ||
                      ((dy_s_signed > -12'sd2) && (dy_s_signed < 12'sd2) &&
                       (dx_s_signed > -12'sd9) && (dx_s_signed < 12'sd9)));

wire signed [11:0] dx_rx_signed = px - RX_X;
wire signed [11:0] dy_rx_signed = py - RX_Y;
wire signed [23:0] dx_rx_sq_signed = dx_rx_signed * dx_rx_signed;
wire signed [23:0] dy_rx_sq_signed = dy_rx_signed * dy_rx_signed;
wire [23:0] rx_r2 = dx_rx_sq_signed[23:0] + dy_rx_sq_signed[23:0];

wire receiver_ring = (rx_r2 > 24'd64) && (rx_r2 < 24'd169);
wire receiver_cross =
    (((dx_rx_signed > -12'sd2) && (dx_rx_signed < 12'sd2) &&
      (dy_rx_signed > -12'sd8) && (dy_rx_signed < 12'sd8)) ||
     ((dy_rx_signed > -12'sd2) && (dy_rx_signed < 12'sd2) &&
      (dx_rx_signed > -12'sd8) && (dx_rx_signed < 12'sd8)));

wire receiver_marker = receiver_ring || receiver_cross;

// ================================================================
// 6. Final layer priority.
// ================================================================

wire [7:0] r, g, b;

assign r =
    receiver_marker        ? 8'd30  :
    source_marker          ? 8'd255 :
    object_hit_highlight   ? 8'd255 :
    near_edge              ? 8'd140 :
    inside_object          ? 8'd54  :
                             field_r;

assign g =
    receiver_marker        ? 8'd225 :
    source_marker          ? 8'd230 :
    object_hit_highlight   ? 8'd245 :
    near_edge              ? 8'd145 :
    inside_object          ? 8'd54  :
                             field_g;

assign b =
    receiver_marker        ? 8'd95  :
    source_marker          ? 8'd45  :
    object_hit_highlight   ? 8'd120 :
    near_edge              ? 8'd150 :
    inside_object          ? 8'd58  :
                             field_b;
packer pixel_packer(    .aclk(out_stream_aclk),
                        .aresetn(periph_resetn),
                        .r(r), .g(g), .b(b),
                        .eol(lastx), .in_stream_ready(ready), .valid(valid_int), .sof(first),
                        .out_stream_tdata(out_stream_tdata), .out_stream_tkeep(out_stream_tkeep),
                        .out_stream_tlast(out_stream_tlast), .out_stream_tready(out_stream_tready),
                        .out_stream_tvalid(out_stream_tvalid), .out_stream_tuser(out_stream_tuser) );

 
endmodule
