/*
 * integration tests for pixel_generator
 *
 * this is the top-level module that connects the wave solver pipeline, object
 * boundary detection, boundary damping, and the AXI-stream pixel output
 *
 * all the sub-modules tested individually before (laplacian, object_set,
 * apply_damping, boundary_damping_coeff) are wired together here, so this
 * testbench checks that the module works as a whole system rather than just
 * testing one block in isolation
 *
 * the module has external BRAM ports for its pressure grid; in real hardware
 * these connect to block RAM on the FPGA, but here we just tie all BRAM read
 * data to zero, which keeps pressure everywhere at zero for the whole run
 *
 * with zero pressure the colour mapping produces white, so we expect every
 * output pixel to be 0x00FFFFFF ({8'd0, b=FF, g=FF, r=FF})
 *
 * the AXI-Lite register interface is also exercised so we know the PS can
 * write control parameters and read them back correctly
 */

#include <cstdint>

#include "base_testbench.h"

unsigned int ticks = 0;

class PixelGeneratorTestbench : public BaseTestbench
{
protected:
    void initializeInputs() override
    {
        // both resets are active low, so driving 0 here holds the DUT in reset
        // at the start of every test
        top->out_stream_aclk    = 0;
        top->s_axi_lite_aclk    = 0;
        top->axi_resetn         = 0;
        top->periph_resetn      = 0;

        // pretend the downstream video consumer is always ready so we never
        // have to deal with backpressure in these tests
        top->out_stream_tready  = 1;

        // AXI-Lite starts quiet - no read or write requests in flight
        // bready and rready are held high so the DUT never has to wait for us
        top->s_axi_lite_arvalid = 0;
        top->s_axi_lite_araddr  = 0;
        top->s_axi_lite_awvalid = 0;
        top->s_axi_lite_awaddr  = 0;
        top->s_axi_lite_wvalid  = 0;
        top->s_axi_lite_wdata   = 0;
        top->s_axi_lite_bready  = 1;
        top->s_axi_lite_rready  = 1;

        // the BRAM ports are external - returning all zeros here means the
        // simulation grid has zero pressure everywhere from the start
        top->cur_bram_a_rddata  = 0;
        top->cur_bram_b_rddata  = 0;
        top->prev_bram_a_rddata = 0;
        top->prev_bram_b_rddata = 0;
    }

    void tick()
    {
        // pixel_generator has two separate clock inputs (stream and AXI-Lite)
        // we drive them together so both domains advance at the same rate
        top->out_stream_aclk = 0;
        top->s_axi_lite_aclk = 0;
        top->eval();
        top->out_stream_aclk = 1;
        top->s_axi_lite_aclk = 1;
        top->eval();
        top->out_stream_aclk = 0;
        top->s_axi_lite_aclk = 0;
        top->eval();
        ++ticks;
    }

    void releaseReset()
    {
        // hold both resets for one full clock, then let go
        // this matches how the PYNQ PS would release the peripheral reset
        top->axi_resetn    = 0;
        top->periph_resetn = 0;
        tick();
        top->axi_resetn    = 1;
        top->periph_resetn = 1;
        top->eval();
    }

    // pump the clock until tvalid goes high or we run out of attempts
    // returns true if tvalid actually went high
    bool waitForValid(int max_ticks = 10)
    {
        for (int i = 0; i < max_ticks; i++) {
            if (top->out_stream_tvalid) return true;
            tick();
        }
        return static_cast<bool>(top->out_stream_tvalid);
    }

    // drive an AXI-Lite write transaction to word_addr (0-indexed register number)
    // the regfile byte address is word_addr * 4 because registers are 32-bit aligned
    void axiLiteWrite(uint8_t word_addr, uint32_t data)
    {
        const uint8_t byte_addr = word_addr << 2;

        // present both the write address and write data at the same time
        // the FSM is in AWAIT_WADD_AND_DATA so it will accept both on one clock
        top->s_axi_lite_awvalid = 1;
        top->s_axi_lite_awaddr  = byte_addr;
        top->s_axi_lite_wvalid  = 1;
        top->s_axi_lite_wdata   = data;
        tick(); // FSM moves to AWAIT_WRITE

        // drop the request signals so we don't accidentally re-trigger
        top->s_axi_lite_awvalid = 0;
        top->s_axi_lite_wvalid  = 0;
        tick(); // FSM performs the write and moves to AWAIT_RESP, bvalid goes high

        // bready is always high so the FSM sees the handshake and returns to idle
        tick();
    }

    // drive an AXI-Lite read transaction and return the data the DUT produces
    uint32_t axiLiteRead(uint8_t word_addr)
    {
        const uint8_t byte_addr = word_addr << 2;

        // present the read address; FSM is in AWAIT_RADD so arready is high
        top->s_axi_lite_arvalid = 1;
        top->s_axi_lite_araddr  = byte_addr;
        tick(); // FSM moves to AWAIT_FETCH, readAddr is now the new address

        top->s_axi_lite_arvalid = 0;
        tick(); // FSM moves to AWAIT_READ, readData is latched from regfile, rvalid goes high

        // grab rdata before we tick again - rready is always high so the next
        // clock will return the FSM to idle and rvalid will drop
        const uint32_t result = top->s_axi_lite_rdata;
        tick();
        return result;
    }
};

TEST_F(PixelGeneratorTestbench, ResetHoldsStreamOutputLow)
{
    // the RTL has out_stream_tvalid = periph_resetn & valid_int, so as long as
    // periph_resetn is low the stream should be completely silent
    // this checks that nothing leaks out while the module is held in reset
    top->periph_resetn     = 0;
    top->out_stream_tready = 1;
    tick();

    EXPECT_EQ(top->out_stream_tvalid, 0);
    EXPECT_EQ(top->out_stream_tuser,  0);
    EXPECT_EQ(top->out_stream_tlast,  0);
}

TEST_F(PixelGeneratorTestbench, StreamStartsAfterReset)
{
    // once both resets are released there are no BRAM writes pending, so
    // valid_int is immediately high and with tready=1 the stream should
    // start flowing within just a couple of clocks
    releaseReset();
    const bool went_valid = waitForValid(5);
    EXPECT_TRUE(went_valid);
}

TEST_F(PixelGeneratorTestbench, TuserOnFirstWordOnly)
{
    // tuser is how the downstream video IP knows a new frame is starting
    // it should be high on the very first pixel (x=0, y=0) and then go low
    // and stay low for all the remaining pixels in the frame
    releaseReset();
    waitForValid(5);

    ASSERT_EQ(top->out_stream_tvalid, 1);
    EXPECT_EQ(top->out_stream_tuser,  1); // first pixel of the frame

    tick();

    EXPECT_EQ(top->out_stream_tvalid, 1);
    EXPECT_EQ(top->out_stream_tuser,  0); // second pixel, tuser should be gone
}

TEST_F(PixelGeneratorTestbench, TkeepAlwaysFullWord)
{
    // every word on the stream is a full 4-byte pixel, never a partial one
    // so tkeep should always be 0xf regardless of where we are in the frame
    releaseReset();
    waitForValid(5);

    ASSERT_EQ(top->out_stream_tvalid, 1);
    EXPECT_EQ(top->out_stream_tkeep, 0xf);
}

TEST_F(PixelGeneratorTestbench, TlastAtEndOfFirstLine)
{
    // X_SIZE is 640 so every display line is exactly 640 pixels wide
    // tlast goes high on the last pixel of each line to tell the sink where
    // the line boundary is
    //
    // line y=0 has y[1:0]=00 which means start_pixel_calc never fires on this
    // line, so there are no BRAM writes and valid_int stays high the whole way
    // through - we get 640 clean consecutive words with no gaps
    releaseReset();
    waitForValid(5);

    int count = 1; // we are already sitting on word x=0
    while (!top->out_stream_tlast) {
        ASSERT_EQ(top->out_stream_tvalid, 1)
            << "stream dropped tvalid unexpectedly at word " << count;
        tick();
        ++count;
        ASSERT_LE(count, 641) << "tlast never arrived within one display line";
    }

    // tlast should have appeared on word number 640, not before and not after
    EXPECT_EQ(count, 640);
    EXPECT_EQ(top->out_stream_tvalid, 1);
}

TEST_F(PixelGeneratorTestbench, TuserStaysLowForRestOfFrame)
{
    // tuser is only supposed to be high on word x=0 of the very first line
    // it must stay low for all remaining 639 words of line y=0 and must not
    // reappear at the start of line y=1 (a new line is not a new frame)
    //
    // line y=0 has no sim calc stalls so we get 640 clean consecutive words
    // that are safe to loop through without worrying about valid_int pauses
    releaseReset();
    waitForValid(5);

    ASSERT_EQ(top->out_stream_tvalid, 1);
    ASSERT_EQ(top->out_stream_tuser,  1); // confirmed at x=0

    // step through x=1..639 and check tuser never reappears
    for (int x = 1; x < 640; x++) {
        tick();
        EXPECT_EQ(top->out_stream_tvalid, 1) << "tvalid dropped at x=" << x;
        EXPECT_EQ(top->out_stream_tuser,  0) << "tuser spuriously high at x=" << x;
    }

    // step past tlast into x=0 of line y=1; a new line is not a new frame
    // note: tlast is combinational (x==639) so it can be high during a stall
    // - we check tuser only, not tvalid, to avoid a false failure on a stall cycle
    tick();
    EXPECT_EQ(top->out_stream_tuser, 0);
}

TEST_F(PixelGeneratorTestbench, StreamRecoversAfterSimCalcPauses)
{
    // pixel calc results arrive back through a 5-stage pipeline and each write
    // causes a 2-cycle pause in valid_int; the stream should stall cleanly and
    // then resume so the total number of valid words per line is still 640
    //
    // we skip 3 display lines before counting so that we land on a line that
    // actually has stalls; we skip by counting valid words (not by watching
    // tlast) because tlast = (x==639) is not gated by tvalid - if a stall
    // coincides with x=639, tlast stays high during the stall and a simple
    // while(!tlast) loop would exit at the wrong position
    releaseReset();
    waitForValid(5);

    // skip lines y=0..2: count exactly 640 valid words then tick past tlast
    for (int line = 0; line < 3; line++) {
        int count = 0, budget = 5000;
        while (budget-- > 0) {
            if (top->out_stream_tvalid) {
                count++;
                if (count == 640) { tick(); break; } // tick past tlast then leave
            }
            tick();
        }
    }

    // count valid words on the next line; allow plenty of ticks for stall cycles
    int valid_count = 0, budget = 5000;
    while (budget-- > 0) {
        if (top->out_stream_tvalid) {
            valid_count++;
            if (top->out_stream_tlast) break;
        }
        tick();
    }

    EXPECT_EQ(top->out_stream_tlast, 1) << "tlast never arrived";
    EXPECT_EQ(valid_count, 640);
}

TEST_F(PixelGeneratorTestbench, PixelDataFormatHasZeroPaddingByte)
{
    // tdata is packed as {8'd0, blue, green, red} in the RTL
    // the top byte is hardwired to zero - downstream video IPs rely on this
    // to know the lower three bytes carry 24-bit RGB
    // this checks the packing is correct regardless of what pressure value
    // the simulation happens to hold after reset
    releaseReset();
    waitForValid(5);

    ASSERT_EQ(top->out_stream_tvalid, 1);
    EXPECT_EQ((top->out_stream_tdata >> 24) & 0xFFu, 0u);
}

TEST_F(PixelGeneratorTestbench, AXILiteRegisterWriteAndRead)
{
    // the PS uses the AXI-Lite interface to write parameters like source
    // position and gain into the register file before firing the wave source
    // this checks that a value written through the write channel comes back
    // correctly through the read channel - basic register file sanity
    releaseReset();

    const uint32_t test_value = 0xA5A5A5A5u;
    axiLiteWrite(0, test_value);

    const uint32_t result = axiLiteRead(0);
    EXPECT_EQ(result, test_value);
}

int main(int argc, char **argv)
{
    Verilated::traceEverOn(true);
    testing::InitGoogleTest(&argc, argv);
    return RUN_ALL_TESTS();
}
