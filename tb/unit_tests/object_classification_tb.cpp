/*
 * unit tests for object_set in object_classification.v
 *
 * what this RTL block does:
 *   object_set looks at the acoustic impedance of the current cell and its 4 direct neighbours
 *   it converts those 5 impedance values into the wall_case code that object_laplacian uses later
 *
 * important detail:
 *   the RTL treats 2'b01 as background
 *   any other 2-bit impedance value counts as an object cell
 *
 * stencil order in the RTL:
 *   merged = {top_obj, left_obj, bottom_obj, right_obj, middle_obj}
 */

#include <cstdint>

#include "base_testbench.h"

unsigned int ticks = 0;

namespace {

constexpr uint8_t BACKGROUND = 0b01;
constexpr uint8_t OBJECT = 0b10;
constexpr uint8_t OTHER_OBJECT = 0b00;

} // namespace

class ObjectClassificationTestbench : public BaseTestbench
{
protected:
    void initializeInputs() override
    {
        // start from an all-background neighbourhood
        top->top_impedance = BACKGROUND;
        top->bottom_impedance = BACKGROUND;
        top->left_impedance = BACKGROUND;
        top->right_impedance = BACKGROUND;
        top->middle_impedance = BACKGROUND;
    }

    void setObjectPattern(bool topObj, bool leftObj, bool bottomObj, bool rightObj, bool middleObj)
    {
        top->top_impedance = topObj ? OBJECT : BACKGROUND;
        top->left_impedance = leftObj ? OBJECT : BACKGROUND;
        top->bottom_impedance = bottomObj ? OBJECT : BACKGROUND;
        top->right_impedance = rightObj ? OBJECT : BACKGROUND;
        top->middle_impedance = middleObj ? OBJECT : BACKGROUND;
    }
};

TEST_F(ObjectClassificationTestbench, AllBackgroundMapsToZero)
{
    // we set all five impedance inputs to background
    // this should produce the normal background wall_case 0
    // no object cells around the current point means the normal background case
    setObjectPattern(false, false, false, false, false);

    top->eval();

    EXPECT_EQ(top->wall_case, 0);
}

TEST_F(ObjectClassificationTestbench, SingleNeighbourObjectCases)
{
    // we turn on one object position at a time
    // each simple object location should map to its expected wall_case
    struct Case {
        bool topObj;
        bool leftObj;
        bool bottomObj;
        bool rightObj;
        bool middleObj;
        int expectedWallCase;
        const char *name;
    };

    const Case cases[] = {
        {false, false, true, false, false, 1, "bottom object"},
        {false, false, false, true, false, 2, "right object"},
        {true, false, false, false, false, 3, "top object"},
        {false, true, false, false, false, 4, "left object"},
        {false, false, false, false, true, 14, "middle object only"},
    };

    for (const auto &testCase : cases) {
        SCOPED_TRACE(testCase.name);

        setObjectPattern(
            testCase.topObj,
            testCase.leftObj,
            testCase.bottomObj,
            testCase.rightObj,
            testCase.middleObj);
        top->eval();

        EXPECT_EQ(top->wall_case, testCase.expectedWallCase);
    }
}

TEST_F(ObjectClassificationTestbench, EveryExplicitPatternMatchesWallCaseTable)
{
    // we run every explicit pattern from the RTL case table
    // this checks that the encoded merged pattern maps to the expected wall_case
    // this table mirrors the case(merged) table in object_classification.v
    // pattern order is {top, left, bottom, right, middle}
    struct Case {
        bool topObj;
        bool leftObj;
        bool bottomObj;
        bool rightObj;
        bool middleObj;
        int expectedWallCase;
        const char *name;
    };

    const Case cases[] = {
        {false, false, false, false, false, 0, "00000 background"},
        {false, false, true, false, false, 1, "00100 bottom wall"},
        {false, false, false, true, false, 2, "00010 right wall"},
        {true, false, false, false, false, 3, "10000 top wall"},
        {false, true, false, false, false, 4, "01000 left wall"},
        {true, true, false, true, true, 5, "11011 bottom air"},
        {true, true, true, false, true, 6, "11101 right air"},
        {false, true, true, true, true, 7, "01111 top air"},
        {true, false, true, true, true, 8, "10111 left air"},
        {true, true, true, true, true, 9, "11111 all object"},
        {false, false, true, true, true, 10, "00111 top and left air"},
        {false, true, true, false, true, 11, "01101 top and right air"},
        {true, false, false, true, true, 12, "10011 left and bottom air"},
        {true, true, false, false, true, 13, "11001 right and bottom air"},
        {false, false, false, false, true, 14, "00001 middle object"},
    };

    for (const auto &testCase : cases) {
        SCOPED_TRACE(testCase.name);

        setObjectPattern(
            testCase.topObj,
            testCase.leftObj,
            testCase.bottomObj,
            testCase.rightObj,
            testCase.middleObj);
        top->eval();

        EXPECT_EQ(top->wall_case, testCase.expectedWallCase);
    }
}

TEST_F(ObjectClassificationTestbench, UnknownPatternDefaultsToZero)
{
    // we choose a merged pattern that is not listed in the RTL case table
    // the default branch should return wall_case 0
    // example merged pattern: 00011
    // it is not listed in the RTL case table, so the default branch should return wall_case 0
    setObjectPattern(false, false, false, true, true);

    top->eval();

    EXPECT_EQ(top->wall_case, 0);
}

TEST_F(ObjectClassificationTestbench, AnyNonBackgroundImpedanceCountsAsObject)
{
    // we use 2'b00 as an object impedance instead of 2'b10
    // this checks that any value other than background is treated as object
    // the RTL does not only recognise OBJECT=2'b10
    // it treats anything that is not BACKGROUND=2'b01 as an object cell
    top->top_impedance = BACKGROUND;
    top->left_impedance = BACKGROUND;
    top->bottom_impedance = OTHER_OBJECT;
    top->right_impedance = BACKGROUND;
    top->middle_impedance = BACKGROUND;

    top->eval();

    EXPECT_EQ(top->wall_case, 1);
}

int main(int argc, char **argv)
{
    Verilated::traceEverOn(true);
    testing::InitGoogleTest(&argc, argv);
    return RUN_ALL_TESTS();
}
