/*
 * unit tests for boundary_damping_coeff
 *
 * this block calculates how close a cell is to the edge of the simulation grid
 * if the cell is inside the border region, it returns a damping value from the
 * LUT
 * if the cell is far enough from the edge, it returns 255
 *
 * the testbench overrides WIDTH and HEIGHT to 320x240 to match the upgraded
 * simulation resolution
 */

#include <array>
#include <cstdint>

#include "base_testbench.h"

unsigned int ticks = 0;

namespace {

constexpr int WIDTH = 320;
constexpr int HEIGHT = 240;
constexpr int BORDER = 24;

constexpr std::array<int, BORDER> DAMPING_LUT = {
    0x000, 0x001, 0x002, 0x004, 0x006, 0x009, 0x00c, 0x010,
    0x014, 0x018, 0x01d, 0x023, 0x028, 0x02e, 0x035, 0x03b,
    0x042, 0x04a, 0x051, 0x058, 0x060, 0x068, 0x070, 0x078,
};

int expectedDamp(int x, int y)
{
    const int distLeft = x;
    const int distRight = (WIDTH - 1) - x;
    const int distTop = y;
    const int distBottom = (HEIGHT - 1) - y;

    int edgeDist = distLeft;
    if (distRight < edgeDist) edgeDist = distRight;
    if (distTop < edgeDist) edgeDist = distTop;
    if (distBottom < edgeDist) edgeDist = distBottom;

    return edgeDist >= BORDER ? 255 : DAMPING_LUT[edgeDist];
}

} // namespace

class BoundaryDampingCoeffTestbench : public BaseTestbench
{
protected:
    void initializeInputs() override
    {
        // start with reset asserted and no valid input
        top->clk = 0;
        top->rstn = 0;
        top->valid_in = 0;
        top->x = 0;
        top->y = 0;
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

    void samplePoint(int x, int y)
    {
        top->rstn = 1;
        top->valid_in = 1;
        top->x = x;
        top->y = y;

        // stage 1 captures the nearest-edge distance
        tick();

        // stage 2 returns the LUT value or full pass-through damping
        tick();
    }
};

TEST_F(BoundaryDampingCoeffTestbench, ResetClearsValidAndSetsDefaultDamping)
{
    // we keep reset asserted and tick the clock
    // the DUT should report no valid output and default damping of 255
    tick();

    EXPECT_EQ(top->valid_out, 0);
    EXPECT_EQ(top->damp_q8, 255);
}

TEST_F(BoundaryDampingCoeffTestbench, TopLeftCornerUsesFirstLutEntry)
{
    // we sample the top-left corner at x=0 y=0
    // the nearest edge distance is zero, so LUT entry 0 should be used
    samplePoint(0, 0);

    EXPECT_EQ(top->valid_out, 1);
    EXPECT_EQ(top->damp_q8, expectedDamp(0, 0));
}

TEST_F(BoundaryDampingCoeffTestbench, NearLeftEdgeUsesEdgeDistance)
{
    // we sample a point 5 cells from the left edge
    // the nearest edge distance should select LUT entry 5
    samplePoint(5, 120);

    EXPECT_EQ(top->valid_out, 1);
    EXPECT_EQ(top->damp_q8, expectedDamp(5, 120));
}

TEST_F(BoundaryDampingCoeffTestbench, NearRightEdgeUses320WideCoordinate)
{
    // we sample the rightmost x coordinate for a 320-wide grid
    // x=319 should be treated as edge distance zero
    samplePoint(319, 120);

    EXPECT_EQ(top->valid_out, 1);
    EXPECT_EQ(top->damp_q8, expectedDamp(319, 120));
}

TEST_F(BoundaryDampingCoeffTestbench, NearBottomEdgeUses240HighCoordinate)
{
    // we sample the bottom y coordinate for a 240-high grid
    // y=239 should be treated as edge distance zero
    samplePoint(160, 239);

    EXPECT_EQ(top->valid_out, 1);
    EXPECT_EQ(top->damp_q8, expectedDamp(160, 239));
}

TEST_F(BoundaryDampingCoeffTestbench, InteriorPointReturnsFullDamping)
{
    // we sample a point well inside the grid and outside the border region
    // the DUT should return full pass-through damping of 255
    samplePoint(160, 120);

    EXPECT_EQ(top->valid_out, 1);
    EXPECT_EQ(top->damp_q8, 255);
}

TEST_F(BoundaryDampingCoeffTestbench, InvalidInputDelaysToInvalidOutput)
{
    // we hold valid_in low and tick through the two-stage pipeline
    // valid_out should remain low after the delay
    top->rstn = 1;
    top->valid_in = 0;
    top->x = 10;
    top->y = 10;

    tick();
    tick();

    EXPECT_EQ(top->valid_out, 0);
}

int main(int argc, char **argv)
{
    Verilated::traceEverOn(true);
    testing::InitGoogleTest(&argc, argv);
    return RUN_ALL_TESTS();
}
