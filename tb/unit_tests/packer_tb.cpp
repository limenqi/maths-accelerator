/*
 * unit tests for packer
 *
 * this block takes incoming 8-bit r, g, b pixel values and packs them into
 * 32-bit AXI-stream words
 *
 * the DUT has a small internal state machine
 * the first pixel is stored but does not produce a valid output word yet
 * later pixels combine their current colour bytes with bytes saved from the
 * previous pixel
 */

#include <cstdint>

#include "base_testbench.h"

unsigned int ticks = 0;

namespace {

uint32_t packed(uint8_t byte3, uint8_t byte2, uint8_t byte1, uint8_t byte0)
{
    return (static_cast<uint32_t>(byte3) << 24)
        | (static_cast<uint32_t>(byte2) << 16)
        | (static_cast<uint32_t>(byte1) << 8)
        | static_cast<uint32_t>(byte0);
}

} // namespace

class PackerTestbench : public BaseTestbench
{
protected:
    void initializeInputs() override
    {
        // start with reset asserted and no active input transfer
        top->aclk = 0;
        top->aresetn = 0;
        top->r = 0;
        top->g = 0;
        top->b = 0;
        top->eol = 0;
        top->valid = 0;
        top->sof = 0;
        top->out_stream_tready = 1;
    }

    void tick()
    {
        top->aclk = 0;
        top->eval();
        top->aclk = 1;
        top->eval();
        top->aclk = 0;
        top->eval();
    }

    void releaseReset()
    {
        // reset is active low, so one clock with aresetn low clears the state machine
        top->aresetn = 0;
        tick();
        top->aresetn = 1;
        top->eval();
    }

    void drivePixel(uint8_t red, uint8_t green, uint8_t blue, bool startOfFrame = false, bool endOfLine = false)
    {
        // drive one pixel into the current cycle
        top->r = red;
        top->g = green;
        top->b = blue;
        top->sof = startOfFrame;
        top->eol = endOfLine;
        top->valid = 1;
        top->eval();
    }
};

TEST_F(PackerTestbench, ResetClearsStateAndOutputSideband)
{
    // we put the DUT in reset while inputs are active
    // after the clock edge, it should return to the first state and clear sof_reg
    top->aresetn = 0;
    top->valid = 1;
    top->sof = 1;
    top->r = 0x12;
    top->g = 0x34;
    top->b = 0x56;

    tick();

    EXPECT_EQ(top->out_stream_tvalid, 0);
    EXPECT_EQ(top->out_stream_tuser, 0);
    EXPECT_EQ(top->in_stream_ready, 1);
}

TEST_F(PackerTestbench, TkeepIsAlwaysFullWord)
{
    // every packed output word should use all four byte lanes
    releaseReset();

    drivePixel(0x01, 0x02, 0x03);

    EXPECT_EQ(top->out_stream_tkeep, 0xf);
}

TEST_F(PackerTestbench, FirstPixelIsAcceptedWithoutOutputWord)
{
    // the first pixel only fills the saved colour registers
    // the output word is not complete yet, so tvalid should be low
    releaseReset();

    drivePixel(0x11, 0x22, 0x33);

    EXPECT_EQ(top->in_stream_ready, 1);
    EXPECT_EQ(top->out_stream_tvalid, 0);
}

TEST_F(PackerTestbench, PacksBytesAcrossFourStateSequence)
{
    // we send four different pixels through the packer
    // each output word should match the byte order used by the RTL state table
    releaseReset();

    drivePixel(0x10, 0x11, 0x12);
    tick();
    top->sof = 0;

    drivePixel(0x20, 0x21, 0x22);
    EXPECT_EQ(top->out_stream_tvalid, 1);
    EXPECT_EQ(top->out_stream_tdata, packed(0x21, 0x10, 0x12, 0x11));
    tick();

    drivePixel(0x30, 0x31, 0x32);
    EXPECT_EQ(top->out_stream_tvalid, 1);
    EXPECT_EQ(top->out_stream_tdata, packed(0x32, 0x31, 0x20, 0x22));
    tick();

    drivePixel(0x40, 0x41, 0x42);
    EXPECT_EQ(top->out_stream_tvalid, 1);
    EXPECT_EQ(top->out_stream_tdata, packed(0x40, 0x42, 0x41, 0x30));
}

TEST_F(PackerTestbench, BackpressureStopsStateAdvance)
{
    // we hold out_stream_tready low while the second pixel is waiting
    // the DUT should keep reporting not-ready and should not advance to the next packing state
    releaseReset();

    drivePixel(0x10, 0x11, 0x12);
    tick();

    top->out_stream_tready = 0;
    drivePixel(0x20, 0x21, 0x22);
    const uint32_t heldWord = packed(0x21, 0x10, 0x12, 0x11);

    EXPECT_EQ(top->out_stream_tvalid, 1);
    EXPECT_EQ(top->in_stream_ready, 0);
    EXPECT_EQ(top->out_stream_tdata, heldWord);

    tick();
    top->eval();

    EXPECT_EQ(top->out_stream_tvalid, 1);
    EXPECT_EQ(top->in_stream_ready, 0);
    EXPECT_EQ(top->out_stream_tdata, heldWord);

    top->out_stream_tready = 1;
    top->eval();

    EXPECT_EQ(top->in_stream_ready, 1);
    EXPECT_EQ(top->out_stream_tdata, heldWord);
}

TEST_F(PackerTestbench, EndOfLineDrivesTlastAndReturnsToFirstState)
{
    // we assert eol on a valid output cycle
    // tlast should follow eol and the next cycle should return to the first state
    releaseReset();

    drivePixel(0x10, 0x11, 0x12);
    tick();

    drivePixel(0x20, 0x21, 0x22, false, true);

    EXPECT_EQ(top->out_stream_tvalid, 1);
    EXPECT_EQ(top->out_stream_tlast, 1);

    tick();
    top->eol = 0;
    drivePixel(0x30, 0x31, 0x32);

    EXPECT_EQ(top->out_stream_tvalid, 0);
    EXPECT_EQ(top->in_stream_ready, 1);
}

TEST_F(PackerTestbench, StartOfFrameAppearsOnNextOutputWord)
{
    // we assert sof on the first pixel of a frame
    // the DUT stores that flag and presents it as tuser on the first valid output word
    releaseReset();

    drivePixel(0x10, 0x11, 0x12, true);
    tick();

    top->sof = 0;
    drivePixel(0x20, 0x21, 0x22);

    EXPECT_EQ(top->out_stream_tvalid, 1);
    EXPECT_EQ(top->out_stream_tuser, 1);

    tick();
    top->eval();

    EXPECT_EQ(top->out_stream_tuser, 0);
}

int main(int argc, char **argv)
{
    Verilated::traceEverOn(true);
    testing::InitGoogleTest(&argc, argv);
    return RUN_ALL_TESTS();
}
