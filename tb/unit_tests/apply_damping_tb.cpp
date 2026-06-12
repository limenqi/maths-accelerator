/*
 * unit tests for apply_damping
 *
 * this block is a one-cycle registered multiplier
 * it takes raw pressure, multiplies by a Q8 damping coefficient, then shifts
 * the result down by 8 bits
 *
 * pixel_generator uses PRESS_W=18, so this testbench runs the DUT with the same
 * pressure width
 */

#include <cstdint>

#include "base_testbench.h"

unsigned int ticks = 0;

namespace {

int32_t signed18(uint32_t value)
{
    value &= 0x3ffff;
    return (value & 0x20000) ? static_cast<int32_t>(value | 0xfffc0000) : static_cast<int32_t>(value);
}

int32_t expectedDamped(int32_t pressure, int32_t dampQ8)
{
    return (pressure * dampQ8) >> 8;
}

} // namespace

class ApplyDampingTestbench : public BaseTestbench
{
protected:
    void initializeInputs() override
    {
        // start with reset asserted and all inputs quiet
        top->clk = 0;
        top->rstn = 0;
        top->valid_in = 0;
        top->p_raw = 0;
        top->damp_q8 = 0;
    }

    void tick()
    {
        top->clk = 0;
        top->eval();
        top->clk = 1;
        top->eval();
        top->clk = 0;
        top->eval();
    }
};

TEST_F(ApplyDampingTestbench, ResetClearsOutput)
{
    // we assert reset while valid and pressure inputs are non-zero
    // after one clock, the DUT should clear both valid_out and p_damped
    top->rstn = 0;
    top->valid_in = 1;
    top->p_raw = 100;
    top->damp_q8 = 256;

    tick();

    EXPECT_EQ(top->valid_out, 0);
    EXPECT_EQ(signed18(top->p_damped), 0);
}

TEST_F(ApplyDampingTestbench, ValidFollowsInputAfterClock)
{
    // we drive valid_in high with reset released
    // after one clock, valid_out should follow valid_in
    top->rstn = 1;
    top->valid_in = 1;
    top->p_raw = 100;
    top->damp_q8 = 128;

    tick();

    EXPECT_EQ(top->valid_out, 1);
}

TEST_F(ApplyDampingTestbench, PositivePressureIsDamped)
{
    // we apply positive pressure with damp_q8 = 128
    // because 128 is half scale in Q8, the output should be half the input
    top->rstn = 1;
    top->valid_in = 1;
    top->p_raw = 200;
    top->damp_q8 = 128;

    tick();

    EXPECT_EQ(signed18(top->p_damped), expectedDamped(200, 128));
}

TEST_F(ApplyDampingTestbench, NegativePressureIsDamped)
{
    // we apply negative pressure with damp_q8 = 128
    // this checks that the multiply and shift preserve signed behaviour
    top->rstn = 1;
    top->valid_in = 1;
    top->p_raw = -200;
    top->damp_q8 = 128;

    tick();

    EXPECT_EQ(signed18(top->p_damped), expectedDamped(-200, 128));
}

TEST_F(ApplyDampingTestbench, ZeroDampingProducesZeroPressure)
{
    // we set damp_q8 to zero
    // any input pressure should be fully damped to zero
    top->rstn = 1;
    top->valid_in = 1;
    top->p_raw = -500;
    top->damp_q8 = 0;

    tick();

    EXPECT_EQ(signed18(top->p_damped), 0);
}

TEST_F(ApplyDampingTestbench, FullScaleDampingKeepsPressure)
{
    // we set damp_q8 to 256, which represents 1.0 in Q8
    // the pressure should pass through unchanged
    top->rstn = 1;
    top->valid_in = 1;
    top->p_raw = 1234;
    top->damp_q8 = 256;

    tick();

    EXPECT_EQ(signed18(top->p_damped), 1234);
}

int main(int argc, char **argv)
{
    Verilated::traceEverOn(true);
    testing::InitGoogleTest(&argc, argv);
    return RUN_ALL_TESTS();
}
