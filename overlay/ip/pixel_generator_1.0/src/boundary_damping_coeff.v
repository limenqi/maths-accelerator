
module boundary_damping_coeff #(
    parameter integer WIDTH  = 320,
    parameter integer HEIGHT = 240,
    parameter integer BORDER = 50
)(
    input  wire       clk,
    input  wire       rstn,
    input  wire       valid_in,

    input  wire [9:0] x,
    input  wire [8:0] y,

    output reg        valid_out,
    output reg  [8:0] damp_q8
);

    // y is 9-bit for 0..479, extend to 10-bit for comparisons/subtractions.
    wire [9:0] y10 = {1'b0, y};

    wire [9:0] dist_left   = x;
    wire [9:0] dist_right  = (WIDTH  - 1) - x;
    wire [9:0] dist_top    = y10;
    wire [9:0] dist_bottom = (HEIGHT - 1) - y10;

    wire [9:0] min_x = (dist_left < dist_right) ? dist_left : dist_right;
    wire [9:0] min_y = (dist_top  < dist_bottom) ? dist_top  : dist_bottom;
    wire [9:0] edge_dist_comb = (min_x < min_y) ? min_x : min_y;

    reg        valid_s1;
    reg [9:0]  edge_dist_s1;

    // 50 entries for BORDER=50. Each entry is Q8 damping, 0..256.
    // For other BORDER values, regenerate damping_lut_q8.mem with the same number of entries.
    (* rom_style = "distributed" *) reg [8:0] damping_lut [0:BORDER-1];

    initial begin
        $readmemh("damping_lut_q8.mem", damping_lut);
    end

    always @(posedge clk) begin
        if (!rstn) begin
            valid_s1    <= 1'b0;
            edge_dist_s1 <= 10'd0;
            valid_out   <= 1'b0;
            damp_q8     <= 9'd256;
        end
        else begin
            // Stage 1: nearest-edge distance.
            valid_s1     <= valid_in;
            edge_dist_s1 <= edge_dist_comb;

            // Stage 2: LUT lookup or full pass-through inside active region.
            valid_out <= valid_s1;

            if (edge_dist_s1 >= BORDER)
                damp_q8 <= 9'd256;              // no boundary damping
            else
                damp_q8 <= damping_lut[edge_dist_s1];
        end
    end

endmodule
