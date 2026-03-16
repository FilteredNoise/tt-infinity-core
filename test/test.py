import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


@cocotb.test()
async def test_boot_sequence(dut):
    dut._log.info("Starting Boot Sequence Test")

    # 1. Start a 50MHz clock
    clock = Clock(dut.clk, 20, units="ns")
    cocotb.start_soon(clock.start())

    # 2. Apply Power & Reset
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)

    dut._log.info("Releasing Reset...")
    dut.rst_n.value = 1

    # 3. Wait for the boot sequence and a few SPI bytes to transmit
    # 5000 cycles is plenty of time with our heartbeat[6] hack!
    dut._log.info("Letting the state machine run...")
    await ClockCycles(dut.clk, 5000)

    dut._log.info("Simulation complete.")
