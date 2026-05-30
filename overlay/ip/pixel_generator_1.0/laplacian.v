module object_laplacian(                 

input  wire signed [8:0] pixel_top;      // note that pressure should actually be -1 to 1
input  wire signed [8:0] pixel_bottom;
input  wire signed [8:0] pixel_left;
input  wire signed [8:0] pixel_right;
input  wire signed [8:0] pixel_middle;
input  wire signed [8:0] pixel_middle_previous;

input wire signed [8:0] reflection_to_wall,
input wire signed [8:0] transmission_to_wall,
input wire signed [8:0] reflection_to_air,
input wire signed [8:0] transmission_to_air,

input wire [7:0] wave_speed_squared, // c^2 * 256

input wire [4:0] wall_case, //determined by another module

output reg signed [8:0] next_pixel_middle // Pixel to be updated
);

// Conditioning
reg signed [8:0] up_eff, down_eff, left_eff, right_eff;
reg signed [11:0] laplacian;
reg signed [20:0] wave_term;
reg signed [20:0] next_temp;

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

laplacian = up_eff + down_eff + left_eff + right_eff - (pixel_middle * 4);

wave_term = ($signed({1'b0, wave_speed_squared}) * laplacian) >>> 8;

next_temp = (pixel_middle * 2) - pixel_middle_previous + wave_term;

 if (next_temp > 21'sd255)
     next_pixel_middle = 9'sd255;

 else if (next_temp < -21'sd256)
     next_pixel_middle = -9'sd256;

 else
     next_pixel_middle = next_temp[8:0];

end

endmodule
    
