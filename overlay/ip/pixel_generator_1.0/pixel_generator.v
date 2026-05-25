
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
// EchoVision V7 Visual Renderer
// Visual-only sonar pressure-field style output.
// Keep AXI-Lite, AXI-Stream, x/y counters, and packer unchanged.
// ================================================================

function [11:0] abs12;
    input signed [11:0] value;
    begin
        abs12 = value[11] ? (~value[11:0] + 12'd1) : value[11:0];
    end
endfunction

function [11:0] max12;
    input [11:0] a;
    input [11:0] b;
    begin
        max12 = (a > b) ? a : b;
    end
endfunction

function [11:0] min12;
    input [11:0] a;
    input [11:0] b;
    begin
        min12 = (a < b) ? a : b;
    end
endfunction

function [7:0] sat_add8;
    input [7:0] a;
    input [7:0] b;
    reg [8:0] sum;
    begin
        sum = {1'b0, a} + {1'b0, b};
        sat_add8 = sum[8] ? 8'hFF : sum[7:0];
    end
endfunction

function [7:0] absdiff8;
    input [7:0] a;
    input [7:0] b;
    begin
        absdiff8 = (a > b) ? (a - b) : (b - a);
    end
endfunction

// ---------------- Hardcoded V7 scene ----------------
// Start hardcoded first. Register-controlled positions can come later.
localparam signed [11:0] SRC_X = 12'sd120;
localparam signed [11:0] SRC_Y = 12'sd300;

localparam signed [11:0] OBJ_X = 12'sd300;
localparam signed [11:0] OBJ_Y = 12'sd300;

localparam signed [11:0] RX_X  = 12'sd560;
localparam signed [11:0] RX_Y  = 12'sd300;

// Object radius = 38 px.
// Use precomputed squares to save hardware.
localparam [23:0] OBJ_R2_INNER = 24'd1296; // 36*36
localparam [23:0] OBJ_R2       = 24'd1444; // 38*38
localparam [23:0] OBJ_R2_OUTER = 24'd1600; // 40*40

// Source-to-object front-surface distance:
// object front x = 300 - 38 = 262
// source x = 120
// distance = 142
localparam [7:0] HIT_DIST = 8'd142;

// Current pixel as signed numbers.
wire signed [11:0] px = {2'b00, x};
wire signed [11:0] py = {3'b000, y};

// gp0 controls animation/pulse.
wire [7:0] pulse = regfile[0][7:0];

// ================================================================
// 1. Source distance approximation
// dist ~= max(abs(dx),abs(dy)) + min(abs(dx),abs(dy))/2
// This avoids sqrt.
// ================================================================

wire signed [11:0] dx_s_signed = px - SRC_X;
wire signed [11:0] dy_s_signed = py - SRC_Y;

wire [11:0] abs_dx_s = abs12(dx_s_signed);
wire [11:0] abs_dy_s = abs12(dy_s_signed);

wire [11:0] max_s = max12(abs_dx_s, abs_dy_s);
wire [11:0] min_s = min12(abs_dx_s, abs_dy_s);

wire [11:0] dist_s = max_s + (min_s >> 1);
wire [11:0] dist_s_q2 = dist_s >> 2;

// ================================================================
// 2. Background gradient + source glow
// ================================================================

wire [8:0] y_inv = 9'd479 - y;
wire [7:0] bg_vert = {3'b000, y_inv[8:4]};  // 0 to about 29

wire [7:0] src_glow = (dist_s < 12'd280) ? (8'd70 - dist_s_q2[7:0]) : 8'd0;
wire [7:0] bg_lum_0 = sat_add8(8'd22, bg_vert);
wire [7:0] bg_lum   = sat_add8(bg_lum_0, src_glow);
wire [7:0] bg_blue  = sat_add8(bg_lum, 8'd42);

// ================================================================
// 3. Moving outgoing source rings
// ================================================================

wire [11:0] phase_full = dist_s - {4'd0, pulse};
wire [4:0] ring_phase = phase_full[4:0];

wire ring_hit = (ring_phase <= 5'd2) || (ring_phase >= 5'd30);

wire [7:0] ring_gain = (dist_s < 12'd620) ? (8'd180 - dist_s_q2[7:0]) : 8'd0;
wire [7:0] ring_intensity = ring_hit ? ring_gain : 8'd0;

// ================================================================
// 4. Circular object
// ================================================================

wire signed [11:0] dx_o_signed = px - OBJ_X;
wire signed [11:0] dy_o_signed = py - OBJ_Y;

wire signed [23:0] dx_o_sq_signed = dx_o_signed * dx_o_signed;
wire signed [23:0] dy_o_sq_signed = dy_o_signed * dy_o_signed;

wire [23:0] obj_d2 = dx_o_sq_signed[23:0] + dy_o_sq_signed[23:0];

wire inside_object = (obj_d2 < OBJ_R2);
wire near_edge = (obj_d2 >= OBJ_R2_INNER) && (obj_d2 <= OBJ_R2_OUTER);

// ================================================================
// 5. Hit highlight on front surface
// Source is on the left, so front side = left side of object.
// ================================================================

wire [7:0] pulse_hit_diff = absdiff8(pulse, HIT_DIST);
wire pulse_hits_object = (pulse_hit_diff < 8'd12);
wire front_side = (px < OBJ_X);

wire object_hit_highlight = near_edge && front_side && pulse_hits_object;

// ================================================================
// 6. Fake reflected echo cloud behind object
// This is visual-only, not a real acoustic solver.
// ================================================================

wire echo_active = (pulse > HIT_DIST);
wire [7:0] echo_age = pulse - HIT_DIST;

wire [11:0] abs_dx_o = abs12(dx_o_signed);
wire [11:0] abs_dy_o = abs12(dy_o_signed);
wire [11:0] max_o = max12(abs_dx_o, abs_dy_o);
wire [11:0] min_o = min12(abs_dx_o, abs_dy_o);
wire [11:0] dist_o = max_o + (min_o >> 1);

wire [11:0] echo_x_from_obj = (px > OBJ_X) ? (px - OBJ_X) : 12'd0;
wire [11:0] echo_y_from_obj = abs_dy_o;

// Cone/cloud region behind object.
wire echo_zone = (px > OBJ_X) &&
                 (px < (OBJ_X + 12'sd190)) &&
                 (echo_y_from_obj < ((echo_x_from_obj >> 1) + 12'd10));

// Broken/scattered echo ring.
wire [7:0] echo_diff = absdiff8(dist_o[7:0], echo_age);
wire echo_ring = (echo_diff < 8'd11);

wire scatter = x[3] ^ y[4] ^ x[5] ^ y[2];

wire [7:0] echo_intensity =
    (echo_active && echo_zone && echo_ring && scatter) ? 8'd135 : 8'd0;

// ================================================================
// 7. Combined pressure intensity
// ================================================================

wire [7:0] pressure_intensity = sat_add8(ring_intensity, echo_intensity);

// ================================================================
// 8. Sonar colour palette
// low: blue/cyan
// mid: green/yellow
// high: orange/red
// ================================================================

wire [7:0] pal_r =
    (pressure_intensity < 8'd40)  ? 8'd0 :
    (pressure_intensity < 8'd90)  ? 8'd0 :
    (pressure_intensity < 8'd150) ? (pressure_intensity + 8'd60) :
                                    8'd255;

wire [7:0] pal_g =
    (pressure_intensity < 8'd40)  ? (8'd20 + pressure_intensity) :
    (pressure_intensity < 8'd90)  ? (8'd80 + (pressure_intensity >> 1)) :
    (pressure_intensity < 8'd150) ? 8'd220 :
                                    (8'd220 - (pressure_intensity >> 2));

wire [7:0] pal_b =
    (pressure_intensity < 8'd40)  ? (8'd100 + pressure_intensity) :
    (pressure_intensity < 8'd90)  ? 8'd255 :
    (pressure_intensity < 8'd150) ? 8'd90 :
                                    8'd40;

wire [7:0] field_r = (pressure_intensity == 8'd0) ? 8'd0          : pal_r;
wire [7:0] field_g = (pressure_intensity == 8'd0) ? (bg_lum >> 2) : pal_g;
wire [7:0] field_b = (pressure_intensity == 8'd0) ? bg_blue       : pal_b;

// ================================================================
// 9. Source marker
// ================================================================

wire source_cross =
    ((abs_dx_s < 12'd2) && (abs_dy_s < 12'd12)) ||
    ((abs_dy_s < 12'd2) && (abs_dx_s < 12'd12));

wire source_marker = (dist_s < 12'd6) || source_cross;

// ================================================================
// 10. Receiver marker
// Separate receiver on right side.
// ================================================================

wire signed [11:0] dx_rx_signed = px - RX_X;
wire signed [11:0] dy_rx_signed = py - RX_Y;

wire [11:0] abs_dx_rx = abs12(dx_rx_signed);
wire [11:0] abs_dy_rx = abs12(dy_rx_signed);

wire [11:0] max_rx = max12(abs_dx_rx, abs_dy_rx);
wire [11:0] min_rx = min12(abs_dx_rx, abs_dy_rx);
wire [11:0] dist_rx = max_rx + (min_rx >> 1);

wire receiver_ring = (dist_rx > 12'd8) && (dist_rx < 12'd14);

wire receiver_cross =
    ((abs_dx_rx < 12'd2) && (abs_dy_rx < 12'd9)) ||
    ((abs_dy_rx < 12'd2) && (abs_dx_rx < 12'd9));

wire receiver_marker = receiver_ring || receiver_cross;

// ================================================================
// 11. Final layer priority
// Later visual layers override earlier field colour.
// ================================================================

wire [7:0] r, g, b;

assign r =
    source_marker          ? 8'd255 :
    receiver_marker        ? 8'd40  :
    object_hit_highlight   ? 8'd255 :
    near_edge              ? 8'd165 :
    inside_object          ? 8'd75  :
                             field_r;

assign g =
    source_marker          ? 8'd220 :
    receiver_marker        ? 8'd255 :
    object_hit_highlight   ? 8'd235 :
    near_edge              ? 8'd165 :
    inside_object          ? 8'd75  :
                             field_g;

assign b =
    source_marker          ? 8'd45  :
    receiver_marker        ? 8'd80  :
    object_hit_highlight   ? 8'd80  :
    near_edge              ? 8'd155 :
    inside_object          ? 8'd75  :
                             field_b;
packer pixel_packer(    .aclk(out_stream_aclk),
                        .aresetn(periph_resetn),
                        .r(r), .g(g), .b(b),
                        .eol(lastx), .in_stream_ready(ready), .valid(valid_int), .sof(first),
                        .out_stream_tdata(out_stream_tdata), .out_stream_tkeep(out_stream_tkeep),
                        .out_stream_tlast(out_stream_tlast), .out_stream_tready(out_stream_tready),
                        .out_stream_tvalid(out_stream_tvalid), .out_stream_tuser(out_stream_tuser) );

 
endmodule
