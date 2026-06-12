#pragma once

#include <memory>

#include "Vdut.h"
#include "gtest/gtest.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

extern unsigned int ticks;

class BaseTestbench : public ::testing::Test
{
public:
    void SetUp() override
    {
        top = std::make_unique<Vdut>();
#ifndef __APPLE__  
        tfp = std::make_unique<VerilatedVcdC>();
        Verilated::traceEverOn(true);
        top->trace(tfp.get(), 99);
        tfp->open("waveform.vcd");
#endif
        initializeInputs();
    }

    void TearDown() override
    {     
        top->final();
#ifndef __APPLE__
        tfp->close();
#endif
    }

    virtual void initializeInputs() = 0;

protected:
    std::unique_ptr<Vdut> top;
#ifndef __APPLE__
    std::unique_ptr<VerilatedVcdC> tfp;
#endif
};
