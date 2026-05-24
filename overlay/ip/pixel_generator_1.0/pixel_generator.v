
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

wire [7:0] r, g, b;
// ============================================================
// EchoVision V6 click-pulse sonar RGB generation
//
// gp0/regfile[0] = pulse radius
// gp1/regfile[1] = source x[9:0], y[18:10]
// gp2/regfile[2] = object x[9:0], y[18:10]
// gp3/regfile[3] = reflectivity[7:0], radius[17:8]
// gp4/regfile[4] = gain[7:0]
//
// Uses squared distance only.
// No sqrt.
// No division.
// No trig / floating point / exponential.
// ============================================================

// ------------------------------------------------------------
// Register decode with zero defaults
// ------------------------------------------------------------
wire source_default = (gp1_vid[18:0] == 19'd0);
wire object_default = (gp2_vid[18:0] == 19'd0);
wire obj_cfg_default = (gp3_vid[17:0] == 18'd0);

wire [9:0] source_x = source_default ? 10'd320 : gp1_vid[9:0];
wire [8:0] source_y = source_default ? 9'd240  : gp1_vid[18:10];

wire [9:0] object_x = object_default ? 10'd420 : gp2_vid[9:0];
wire [8:0] object_y = object_default ? 9'd240  : gp2_vid[18:10];

wire [9:0] object_radius = obj_cfg_default ? 10'd35  : gp3_vid[17:8];
wire [7:0] reflectivity  = obj_cfg_default ? 8'd220  : gp3_vid[7:0];
wire [7:0] gain          = (gp4_vid == 32'd0) ? 8'd180 : gp4_vid[7:0];

wire [10:0] pulse_radius = {1'b0, gp0_vid[9:0]};
wire [10:0] pulse_inner  = (pulse_radius > 11'd6) ? (pulse_radius - 11'd6) : 11'd0;
wire [10:0] pulse_outer  = pulse_radius + 11'd6;

// ------------------------------------------------------------
// Squared distances
// ------------------------------------------------------------

wire signed [11:0] dx_source  = $signed({2'b00, x})        - $signed({2'b00, source_x});
wire signed [11:0] dy_source  = $signed({3'b000, y})       - $signed({3'b000, source_y});
wire signed [11:0] dx_object  = $signed({2'b00, x})        - $signed({2'b00, object_x});
wire signed [11:0] dy_object  = $signed({3'b000, y})       - $signed({3'b000, object_y});
wire signed [11:0] dx_src_obj = $signed({2'b00, object_x}) - $signed({2'b00, source_x});
wire signed [11:0] dy_src_obj = $signed({3'b000, object_y}) - $signed({3'b000, source_y});

wire [23:0] source_d2 = (dx_source * dx_source) + (dy_source * dy_source);
wire [23:0] object_d2 = (dx_object * dx_object) + (dy_object * dy_object);
wire [23:0] src_obj_d2 = (dx_src_obj * dx_src_obj) + (dy_src_obj * dy_src_obj);

wire [21:0] radius_d2 = object_radius * object_radius;
wire [21:0] pulse_inner_d2 = pulse_inner * pulse_inner;
wire [21:0] pulse_outer_d2 = pulse_outer * pulse_outer;

// ------------------------------------------------------------
// Pulse ring, object mask, and echo boost
// ------------------------------------------------------------
wire pulse_on = (source_d2 >= {2'b00, pulse_inner_d2}) &&
                (source_d2 <= {2'b00, pulse_outer_d2});

wire object_on = (object_d2 < {2'b00, radius_d2});

wire object_pulse_hit = (src_obj_d2 >= {2'b00, pulse_inner_d2}) &&
                        (src_obj_d2 <= {2'b00, pulse_outer_d2});

wire [15:0] echo_boost_full = reflectivity * gain;
wire [7:0] echo_boost = echo_boost_full[15:8];

wire [8:0] object_r_hit = 9'd32 + {1'b0, echo_boost};
wire [8:0] object_g_hit = 9'd72 + {1'b0, echo_boost};
wire [8:0] object_b_hit = 9'd96 + {1'b0, echo_boost[7:1]};

wire [7:0] object_r = (object_on && object_pulse_hit) ? (object_r_hit[8] ? 8'hff : object_r_hit[7:0]) : 8'h18;
wire [7:0] object_g = (object_on && object_pulse_hit) ? (object_g_hit[8] ? 8'hff : object_g_hit[7:0]) : 8'h58;
wire [7:0] object_b = (object_on && object_pulse_hit) ? (object_b_hit[8] ? 8'hff : object_b_hit[7:0]) : 8'h70;

// Subtle fixed range rings from squared-distance bits.
wire range_ring = (source_d2[11:7] == 5'd0);

// ------------------------------------------------------------
// RGB colour priority: object > pulse > range rings > background
// ------------------------------------------------------------
assign r = object_on  ? object_r :
           pulse_on   ? 8'h28 :
           range_ring ? 8'h00 :
                        8'h00;

assign g = object_on  ? object_g :
           pulse_on   ? 8'hff :
           range_ring ? 8'h48 :
                        8'h08;

assign b = object_on  ? object_b :
           pulse_on   ? 8'hb0 :
           range_ring ? 8'h38 :
                        8'h14;
packer pixel_packer(    .aclk(out_stream_aclk),
                        .aresetn(periph_resetn),
                        .r(r), .g(g), .b(b),
                        .eol(lastx), .in_stream_ready(ready), .valid(valid_int), .sof(first),
                        .out_stream_tdata(out_stream_tdata), .out_stream_tkeep(out_stream_tkeep),
                        .out_stream_tlast(out_stream_tlast), .out_stream_tready(out_stream_tready),
                        .out_stream_tvalid(out_stream_tvalid), .out_stream_tuser(out_stream_tuser) );

 
endmodule
