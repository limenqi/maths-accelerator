

module apply_damping #(
    parameter integer PRESS_W = 16
)(
    input  wire                      clk,
    input  wire                      rstn,
    input  wire                      valid_in,

    input  wire signed [PRESS_W-1:0] p_raw,
    input  wire        [8:0]         damp_q8,

    output reg                       valid_out,
    output reg signed [PRESS_W-1:0]  p_damped
);

    wire signed [9:0] damp_signed = {1'b0, damp_q8};

    wire signed [PRESS_W+9:0] product =
        p_raw * damp_signed;

    wire signed [PRESS_W+9:0] shifted =
        product >>> 8;

    always @(posedge clk) begin
        if (!rstn) begin
            valid_out <= 1'b0;
            p_damped  <= {PRESS_W{1'b0}};
        end
        else begin
            valid_out <= valid_in;
            p_damped  <= shifted[PRESS_W-1:0];
        end
    end

endmodule
