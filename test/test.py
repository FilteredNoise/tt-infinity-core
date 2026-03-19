import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


# Safely set a single bit in the 8-bit input array
def set_pin(dut, pin_idx, val):
    current = int(dut.ui_in.value) if dut.ui_in.value.is_resolvable else 0
    if val:
        dut.ui_in.value = current | (1 << pin_idx)
    else:
        dut.ui_in.value = current & ~(1 << pin_idx)


# Helper function to simulate a human turning the knob
async def turn_encoder(dut, pin_a_idx, pin_b_idx, direction="CW", clicks=1):
    for _ in range(clicks):
        if direction == "CW":
            set_pin(dut, pin_a_idx, 1)
            await ClockCycles(dut.clk, 20)
            set_pin(dut, pin_b_idx, 1)
            await ClockCycles(dut.clk, 20)
            set_pin(dut, pin_a_idx, 0)
            await ClockCycles(dut.clk, 20)
            set_pin(dut, pin_b_idx, 0)
            await ClockCycles(dut.clk, 20)
        else:
            set_pin(dut, pin_b_idx, 1)
            await ClockCycles(dut.clk, 20)
            set_pin(dut, pin_a_idx, 1)
            await ClockCycles(dut.clk, 20)
            set_pin(dut, pin_b_idx, 0)
            await ClockCycles(dut.clk, 20)
            set_pin(dut, pin_a_idx, 0)
            await ClockCycles(dut.clk, 20)


@cocotb.test()
async def test_infinity_core_master(dut):
    dut._log.info("Starting Infinity Core Master Validation Test")

    # Start 50MHz Clock
    clock = Clock(dut.clk, 20, units="ns")
    cocotb.start_soon(clock.start())

    # 1. Power On & Reset
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    # 2. The Boot & Init Sequence
    dut._log.info("Waiting for hardware boot sequence (~5.24 ms)...")
    # 270,000 cycles safely covers the 5.24ms boot + SPI Init transmission
    await ClockCycles(dut.clk, 270000)
    dut._log.info("Boot complete. OLED should now be initialized.")

    # 3. Turning the Knobs
    dut._log.info("Twisting Encoder 1 CW (Increasing Max Brightness/Density)...")
    await turn_encoder(dut, 1, 2, direction="CW", clicks=10)  # 128 + (10 * 8) = 208

    dut._log.info("Twisting Encoder 2 CCW (Setting Decay to Fastest)...")
    await turn_encoder(dut, 3, 4, direction="CCW", clicks=20)  # Drops to 0 (Fastest)

    # Give it a short pause before the music hits
    await ClockCycles(dut.clk, 50000)

    # 4. The Audio Trigger
    dut._log.info("BOOM! Firing Audio Trigger.")
    set_pin(dut, 0, 1)  # Hit!
    await ClockCycles(dut.clk, 10)
    set_pin(dut, 0, 0)  # Release

    # 5. Frame Draw & Decay Observation
    dut._log.info("Audio hit registered. SPI should be blasting noise_byte.")
    dut._log.info("Simulating for another 45 ms (2.25 million cycles)...")
    dut._log.info("This takes a moment. Please wait...")

    # 2.25M cycles gives enough time to see the frame finish drawing,
    # the brightness decay significantly, AND the next natural frame tick!
    await ClockCycles(dut.clk, 2250000)

    dut._log.info("Simulation complete! Go check GTKWave.")
