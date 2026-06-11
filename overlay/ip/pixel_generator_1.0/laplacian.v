module object_laplacian(

input  wire signed [15:0] pixel_top,
input  wire signed [15:0] pixel_bottom,
input  wire signed [15:0] pixel_left,
input  wire signed [15:0] pixel_right,
input  wire signed [15:0] pixel_middle,
input  wire signed [15:0] pixel_middle_previous,

// Q8 fixed-point coefficients. Widened to 11-bit signed so that a
// transmission coefficient of T=1.2 (Q8 = 307) fits; signed[8:0] only
// reached +255 which overflowed for any T>~1.0.
input wire signed [10:0] reflection_to_wall,
input wire signed [10:0] transmission_to_wall,
input wire signed [10:0] reflection_to_air,
input wire signed [10:0] transmission_to_air,

input wire [7:0] wave_speed_squared, // c^2 * 256

input wire [4:0] wall_case, //determined by another module

output reg signed [17:0] next_pixel_middle // Pixel to be updated, Q6
);

// Conditioning
reg signed [15:0] up_eff, down_eff, left_eff, right_eff;
reg signed [19:0] laplacian;
reg signed [27:0] wave_term;
reg signed [27:0] next_temp;
always @(*) begin

    up_eff    = pixel_top;
    down_eff  = pixel_bottom;
    left_eff  = pixel_left;
    right_eff = pixel_right;

  case(wall_case)

    5'd0: begin                      //do not feedbackground case since wrong wave speed will be used, background is not my job
        up_eff    = pixel_top;
        down_eff  = pixel_bottom;
        left_eff  = pixel_left;
        right_eff = pixel_right;
    end

    5'd1: begin
        down_eff = (($signed(pixel_middle) * $signed({reflection_to_wall})) +
                    ($signed(pixel_bottom) * $signed({transmission_to_wall}))) >>> 8;
    end

    5'd2: begin
        right_eff = (($signed(pixel_middle) * $signed({ reflection_to_wall})) +
                     ($signed(pixel_right) * $signed({ transmission_to_wall}))) >>> 8;
    end

    5'd3: begin
        up_eff = (($signed(pixel_middle) * $signed({reflection_to_wall})) +
                  ($signed(pixel_top) * $signed({ transmission_to_wall}))) >>> 8;
    end

    5'd4: begin
        left_eff = (($signed(pixel_middle) * $signed({ reflection_to_wall})) +
                    ($signed(pixel_left) * $signed({ transmission_to_wall}))) >>> 8;
    end

    5'd5: begin
        down_eff = (($signed(pixel_middle) * $signed({ reflection_to_air})) +
                    ($signed(pixel_bottom) * $signed({ transmission_to_air}))) >>> 8;
    end

    5'd6: begin
        right_eff = (($signed(pixel_middle) * $signed({ reflection_to_air})) +
                     ($signed(pixel_right) * $signed({ transmission_to_air}))) >>> 8;
    end

    5'd7: begin
        up_eff = (($signed(pixel_middle) * $signed({reflection_to_air})) +
                  ($signed(pixel_top) * $signed({transmission_to_air}))) >>> 8;
    end

    5'd8: begin
        left_eff = (($signed(pixel_middle) * $signed({reflection_to_air})) +
                    ($signed(pixel_left) * $signed({transmission_to_air}))) >>> 8;
    end

    5'd9: begin
        up_eff    = pixel_top;
        down_eff  = pixel_bottom;
        left_eff  = pixel_left;
        right_eff = pixel_right;
    end

    5'd10: begin
        up_eff    = (($signed(pixel_middle) * $signed({reflection_to_air})) +
                  ($signed(pixel_top) * $signed({transmission_to_air}))) >>> 8;

        left_eff = (($signed(pixel_middle) * $signed({reflection_to_air})) +
                    ($signed(pixel_left) * $signed({transmission_to_air}))) >>> 8;
    end

    5'd11: begin
        up_eff    = (($signed(pixel_middle) * $signed({reflection_to_air})) +
                  ($signed(pixel_top) * $signed({transmission_to_air}))) >>> 8;

        right_eff = (($signed(pixel_middle) * $signed({ reflection_to_air})) +
                     ($signed(pixel_right) * $signed({ transmission_to_air}))) >>> 8;
    end

    5'd12: begin
        left_eff = (($signed(pixel_middle) * $signed({reflection_to_air})) +
                    ($signed(pixel_left) * $signed({transmission_to_air}))) >>> 8;

        down_eff = (($signed(pixel_middle) * $signed({ reflection_to_air})) +
                    ($signed(pixel_bottom) * $signed({ transmission_to_air}))) >>> 8;

    end

    5'd13: begin
        right_eff = (($signed(pixel_middle) * $signed({ reflection_to_air})) +
                     ($signed(pixel_right) * $signed({ transmission_to_air}))) >>> 8;

        down_eff = (($signed(pixel_middle) * $signed({ reflection_to_air})) +
                    ($signed(pixel_bottom) * $signed({ transmission_to_air}))) >>> 8;

    end

   5'd14: begin
        right_eff = (($signed(pixel_middle) * $signed({ reflection_to_air})) +
                     ($signed(pixel_right) * $signed({ transmission_to_air}))) >>> 8;

        down_eff = (($signed(pixel_middle) * $signed({ reflection_to_air})) +
                    ($signed(pixel_bottom) * $signed({ transmission_to_air}))) >>> 8;

        left_eff = (($signed(pixel_middle) * $signed({reflection_to_air})) +
                    ($signed(pixel_left) * $signed({transmission_to_air}))) >>> 8;

        up_eff    = (($signed(pixel_middle) * $signed({reflection_to_air})) +
                  ($signed(pixel_top) * $signed({transmission_to_air}))) >>> 8;
   end

    default: begin
        up_eff    = pixel_top;
        down_eff  = pixel_bottom;
        left_eff  = pixel_left;
        right_eff = pixel_right;
    end

endcase

laplacian = $signed(up_eff) + $signed(down_eff) + $signed(left_eff) +
            $signed(right_eff) - ($signed(pixel_middle) * 4);

wave_term = ($signed({1'b0, wave_speed_squared}) * laplacian) >>> 8;

// p_next = 2*p_cur - p_prev + ((K * laplacian) >>> 8).
next_temp = ($signed(pixel_middle) * 2) - $signed(pixel_middle_previous) + wave_term;
next_pixel_middle = next_temp[17:0];

end

endmodule
