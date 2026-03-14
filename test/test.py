import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge


@cocotb.test()
async def test_infinity_core(dut):
    dut._log.info("Starting Infinity Core Simulation")

    # 1. Start a 50MHz clock (20ns period)
    clock = Clock(dut.clk, 20, units="ns")
    cocotb.start_soon(clock.start())

    # 2. Reset the system
    dut.ena.value = 1
    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)

    # 3. Simulate an Audio Beat
    dut._log.info("Firing Audio Trigger...")
    dut.ui_in.value = 1  # ui_in[0] = 1
    await ClockCycles(dut.clk, 1)
    dut.ui_in.value = 0  # Release trigger

    # 4. Observe the PWM output
    # Since brightness is now 255 (FF), the PWM signal should be
    # high almost all the time.
    dut._log.info("Observing PWM output for 200'000 cycles...")
    for i in range(200000):
        await RisingEdge(dut.clk)
        # You can uncomment the line below to see every clock cycle in the terminal
        # dut._log.info(f"Cycle {i}: PWM={dut.uo_out[0].value}")

    dut._log.info("Simulation complete.")
