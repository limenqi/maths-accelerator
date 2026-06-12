/*
 * unit tests for object_laplacian
 *
 * what the RTL block does:
 *   object_laplacian calculates the next pressure value for one cell in the
 *   wave grid
 *   it only sees the local 5-point stencil:
 *
 *                pixel_top
 *   pixel_left  pixel_middle  pixel_right
 *               pixel_bottom
 *
 *   it also receives pixel_middle_previous, because the wave equation needs the
 *   previous timestep as well as the current one
 *
 *   the DUT is purely combinational
 *   there is no clock, reset, AXI, BRAM, or frame counter involved here
 *   each test sets the inputs, calls top->eval(), then checks next_pixel_middle
 *
 * what the reference model below does:
 *   the helper functions rewrite the same fixed-point maths in C++
 *   if the RTL changes one neighbour incorrectly, uses the wrong coefficient,
 *   or handles a signed value incorrectly, these tests should catch it
 */

#include <cstdint>

#include "base_testbench.h"

unsigned int ticks = 0;

namespace {

constexpr int16_t REFL_WALL = 51;
constexpr int16_t TRANS_WALL = 307;
constexpr int16_t REFL_AIR = -51;
constexpr int16_t TRANS_AIR = 205;
constexpr uint8_t WAVE_SPEED_SQUARED = 64;

// the reflection/transmission coefficients are Q8 fixed-point values
// after multiplying by a Q8 coefficient, the RTL shifts right by 8 bits to get
// back to the pressure scale
int32_t applyCoeff(int32_t middle, int32_t neighbour, int32_t reflection, int32_t transmission)
{
    return ((middle * reflection) + (neighbour * transmission)) >> 8;
}

// reference version of the normal wave update:
//
//   laplacian = top + bottom + left + right - 4*middle
//   next      = 2 * middle - previous + ((waveSpeedSquared * laplacian) >> 8)
//
// for reference:
//   if the middle cell is higher than its neighbours, the laplacian is negative
//   and the next value is pulled down
//   if the neighbours are higher, the middle cell is pushed up
int32_t expectedNext(
    int32_t top,
    int32_t bottom,
    int32_t left,
    int32_t right,
    int32_t middle,
    int32_t previous,
    int32_t waveSpeedSquared)
{
    const int32_t laplacian = top + bottom + left + right - (4 * middle);
    const int32_t waveTerm = (waveSpeedSquared * laplacian) >> 8;
    return (2 * middle) - previous + waveTerm;
}

/*
 * reference version of the wall_case switch in the RTL
 *
 * wall_case tells the DUT whether the current cell is next to an object/wall
 * boundary
 * for normal background cells, the DUT uses top/bottom/left/right directly
 * for boundary cells, it first replaces one or more neighbours with an effective
 * neighbour value:
 *
 *   effective = middle * reflection + neighbour * transmission
 *
 * that models part of the wave reflecting back from the object and part of it
 * transmitting through the boundary
 *
 * the boundary selection logic is kept separate from expectedNext() because if
 * a test fails, it is easier to tell whether the problem is in choosing the
 * affected neighbours or in the final wave equation
 */
int32_t expectedForWallCase(
    int wallCase,
    int32_t top,
    int32_t bottom,
    int32_t left,
    int32_t right,
    int32_t middle,
    int32_t previous,
    int32_t waveSpeedSquared)
{
    int32_t topEff = top;
    int32_t bottomEff = bottom;
    int32_t leftEff = left;
    int32_t rightEff = right;

    switch (wallCase) {
    case 1:
        // wall below the current cell
        bottomEff = applyCoeff(middle, bottom, REFL_WALL, TRANS_WALL);
        break;
    case 2:
        // wall to the right of the current cell
        rightEff = applyCoeff(middle, right, REFL_WALL, TRANS_WALL);
        break;
    case 3:
        // wall above the current cell
        topEff = applyCoeff(middle, top, REFL_WALL, TRANS_WALL);
        break;
    case 4:
        // wall to the left of the current cell
        leftEff = applyCoeff(middle, left, REFL_WALL, TRANS_WALL);
        break;
    case 5:
        // object-to-air boundary below the current cell
        bottomEff = applyCoeff(middle, bottom, REFL_AIR, TRANS_AIR);
        break;
    case 6:
        // object-to-air boundary to the right
        rightEff = applyCoeff(middle, right, REFL_AIR, TRANS_AIR);
        break;
    case 7:
        // object-to-air boundary above the current cell
        topEff = applyCoeff(middle, top, REFL_AIR, TRANS_AIR);
        break;
    case 8:
        // object-to-air boundary to the left
        leftEff = applyCoeff(middle, left, REFL_AIR, TRANS_AIR);
        break;
    case 10:
        // corner case: top and left neighbours are adjusted
        topEff = applyCoeff(middle, top, REFL_AIR, TRANS_AIR);
        leftEff = applyCoeff(middle, left, REFL_AIR, TRANS_AIR);
        break;
    case 11:
        // corner case: top and right neighbours are adjusted
        topEff = applyCoeff(middle, top, REFL_AIR, TRANS_AIR);
        rightEff = applyCoeff(middle, right, REFL_AIR, TRANS_AIR);
        break;
    case 12:
        // corner case: left and bottom neighbours are adjusted
        leftEff = applyCoeff(middle, left, REFL_AIR, TRANS_AIR);
        bottomEff = applyCoeff(middle, bottom, REFL_AIR, TRANS_AIR);
        break;
    case 13:
        // corner case: right and bottom neighbours are adjusted
        rightEff = applyCoeff(middle, right, REFL_AIR, TRANS_AIR);
        bottomEff = applyCoeff(middle, bottom, REFL_AIR, TRANS_AIR);
        break;
    case 14:
        // object middle case: all four neighbours are adjusted
        topEff = applyCoeff(middle, top, REFL_AIR, TRANS_AIR);
        bottomEff = applyCoeff(middle, bottom, REFL_AIR, TRANS_AIR);
        leftEff = applyCoeff(middle, left, REFL_AIR, TRANS_AIR);
        rightEff = applyCoeff(middle, right, REFL_AIR, TRANS_AIR);
        break;
    default:
        // case 0, 9, and any unknown value use the neighbours unchanged
        break;
    }

    return expectedNext(topEff, bottomEff, leftEff, rightEff, middle, previous, waveSpeedSquared);
}

// next_pixel_middle is signed[17:0]
// verilator exposes that 18-bit signal as an unsigned C++ value
// this helper sign-extends it back to a normal int32_t before EXPECT_EQ compares it
int32_t signed18(uint32_t value)
{
    value &= 0x3ffff;
    return (value & 0x20000) ? static_cast<int32_t>(value | 0xfffc0000) : static_cast<int32_t>(value);
}

} // namespace

class ObjectLaplacianTestbench : public BaseTestbench
{
protected:
    void initializeInputs() override
    {
        // start every test from a valid zero state
        // individual tests then override only the signals they care about
        top->pixel_top = 0;
        top->pixel_bottom = 0;
        top->pixel_left = 0;
        top->pixel_right = 0;
        top->pixel_middle = 0;
        top->pixel_middle_previous = 0;

        top->reflection_to_wall = REFL_WALL;
        top->transmission_to_wall = TRANS_WALL;
        top->reflection_to_air = REFL_AIR;
        top->transmission_to_air = TRANS_AIR;

        top->wave_speed_squared = WAVE_SPEED_SQUARED;
        top->wall_case = 0;
    }
};

TEST_F(ObjectLaplacianTestbench, FlatFieldStaysConstant)
{
    // we set the middle, neighbours, and previous value to the same pressure
    // with no gradient, the next pressure should stay constant
    // all five current pressure values are equal, so there is no pressure gradient
    // the laplacian is zero, and because previous == middle, the output stays at 100
    top->pixel_top = 100;
    top->pixel_bottom = 100;
    top->pixel_left = 100;
    top->pixel_right = 100;
    top->pixel_middle = 100;
    top->pixel_middle_previous = 100;
    top->wall_case = 0;

    top->eval();

    EXPECT_EQ(signed18(top->next_pixel_middle), 100);
}

TEST_F(ObjectLaplacianTestbench, BasicLaplacianNoObject)
{
    // we create a single high-pressure middle cell surrounded by zeros
    // this checks the plain wave equation without any object boundary
    // pressure spike example
    //
    // middle cell is high and all neighbours are zero:
    //   laplacian = 0 + 0 + 0 + 0 - 4*100 = -400
    //   waveTerm  = (64 * -400) >> 8 = -100
    //   next      = 2*100 - 100 - 100 = 0
    //
    // so the spike collapses back down
    top->pixel_top = 0;
    top->pixel_bottom = 0;
    top->pixel_left = 0;
    top->pixel_right = 0;
    top->pixel_middle = 100;
    top->pixel_middle_previous = 100;
    top->wall_case = 0;

    top->eval();

    EXPECT_EQ(signed18(top->next_pixel_middle), 0);
}

TEST_F(ObjectLaplacianTestbench, HandlesNegativePressure)
{
    // we mix positive and negative pressure values
    // this checks that signed arithmetic is preserved through the update
    // pressure can be negative
    // this test checks that the RTL and testbench both treat values as signed
    top->pixel_top = -20;
    top->pixel_bottom = 10;
    top->pixel_left = -15;
    top->pixel_right = 5;
    top->pixel_middle = -30;
    top->pixel_middle_previous = -25;
    top->wall_case = 0;

    top->eval();

    const int32_t expected = expectedNext(-20, 10, -15, 5, -30, -25, WAVE_SPEED_SQUARED);
    EXPECT_EQ(signed18(top->next_pixel_middle), expected);
}

TEST_F(ObjectLaplacianTestbench, BottomWallAppliesWallCoefficients)
{
    // we set wall_case 1 so the bottom neighbour is treated as a wall boundary
    // the expected result uses the wall reflection and transmission coefficients
    // wall_case 1 means the bottom neighbour is across a wall boundary
    // the RTL should calculate bottomEff using the wall coefficients first
    top->pixel_top = 20;
    top->pixel_bottom = 80;
    top->pixel_left = 30;
    top->pixel_right = 40;
    top->pixel_middle = 50;
    top->pixel_middle_previous = 45;
    top->wall_case = 1;

    top->eval();

    const int32_t bottomEff = applyCoeff(50, 80, REFL_WALL, TRANS_WALL);
    const int32_t expected = expectedNext(20, bottomEff, 30, 40, 50, 45, WAVE_SPEED_SQUARED);
    EXPECT_EQ(signed18(top->next_pixel_middle), expected);
}

TEST_F(ObjectLaplacianTestbench, RightAirBoundaryAppliesAirCoefficients)
{
    // we set wall_case 6 so the right neighbour is treated as an object-to-air boundary
    // the expected result uses the air reflection and transmission coefficients
    // wall_case 6 means the right neighbour is across an object-to-air boundary
    // this uses the air coefficients rather than the wall coefficients
    top->pixel_top = 20;
    top->pixel_bottom = 25;
    top->pixel_left = 30;
    top->pixel_right = 90;
    top->pixel_middle = 50;
    top->pixel_middle_previous = 45;
    top->wall_case = 6;

    top->eval();

    const int32_t rightEff = applyCoeff(50, 90, REFL_AIR, TRANS_AIR);
    const int32_t expected = expectedNext(20, 25, 30, rightEff, 50, 45, WAVE_SPEED_SQUARED);
    EXPECT_EQ(signed18(top->next_pixel_middle), expected);
}

TEST_F(ObjectLaplacianTestbench, ObjectMiddleAppliesAirCoefficientsToAllNeighbours)
{
    // we set wall_case 14 so all four neighbours are adjusted
    // this checks the object-cell case before the final laplacian calculation
    // wall_case 14 is the object-cell case where all four neighbours are adjusted
    top->pixel_top = 12;
    top->pixel_bottom = 20;
    top->pixel_left = -8;
    top->pixel_right = 16;
    top->pixel_middle = 40;
    top->pixel_middle_previous = 35;
    top->wall_case = 14;

    top->eval();

    const int32_t topEff = applyCoeff(40, 12, REFL_AIR, TRANS_AIR);
    const int32_t bottomEff = applyCoeff(40, 20, REFL_AIR, TRANS_AIR);
    const int32_t leftEff = applyCoeff(40, -8, REFL_AIR, TRANS_AIR);
    const int32_t rightEff = applyCoeff(40, 16, REFL_AIR, TRANS_AIR);
    const int32_t expected = expectedNext(topEff, bottomEff, leftEff, rightEff, 40, 35, WAVE_SPEED_SQUARED);
    EXPECT_EQ(signed18(top->next_pixel_middle), expected);
}

TEST_F(ObjectLaplacianTestbench, EveryWallCaseMatchesReferenceModel)
{
    // we loop through every explicit wall_case and one default case
    // each output is compared against the C++ reference model
    // main coverage test for the wall_case switch
    //
    // inputs are deliberately asymmetric so top/bottom/left/right mistakes are visible
    constexpr int32_t topIn = 17;
    constexpr int32_t bottomIn = -23;
    constexpr int32_t leftIn = 41;
    constexpr int32_t rightIn = -11;
    constexpr int32_t middleIn = 64;
    constexpr int32_t previousIn = 19;

    struct Case {
        int wallCase;
        const char *name;
    };

    // labels used in the failure trace
    const Case cases[] = {
        {0, "background unchanged"},
        {1, "bottom wall"},
        {2, "right wall"},
        {3, "top wall"},
        {4, "left wall"},
        {5, "bottom air"},
        {6, "right air"},
        {7, "top air"},
        {8, "left air"},
        {9, "object interior unchanged"},
        {10, "top and left air"},
        {11, "top and right air"},
        {12, "left and bottom air"},
        {13, "right and bottom air"},
        {14, "all neighbours air"},
        {15, "default unchanged"},
    };

    for (const auto &testCase : cases) {
        // scoped_trace prints the wall case name and index if this iteration fails
        SCOPED_TRACE(testCase.name);
        SCOPED_TRACE(testCase.wallCase);

        top->pixel_top = topIn;
        top->pixel_bottom = bottomIn;
        top->pixel_left = leftIn;
        top->pixel_right = rightIn;
        top->pixel_middle = middleIn;
        top->pixel_middle_previous = previousIn;
        top->wall_case = testCase.wallCase;

        top->eval();

        const int32_t expected = expectedForWallCase(
            testCase.wallCase,
            topIn,
            bottomIn,
            leftIn,
            rightIn,
            middleIn,
            previousIn,
            WAVE_SPEED_SQUARED);
        EXPECT_EQ(signed18(top->next_pixel_middle), expected);
    }
}

int main(int argc, char **argv)
{
    Verilated::traceEverOn(true);
    testing::InitGoogleTest(&argc, argv);
    return RUN_ALL_TESTS();
}
