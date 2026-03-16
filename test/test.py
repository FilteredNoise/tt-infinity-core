import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

# Safely set a single bit in the 8-bit input array
def set_pin(dut, pin_idx, val):
    # Read current 8-bit value (default to 0 if undefined)
    current = int(dut.ui_in.value) if dut.ui_in.value.is_resolvable else 0
    if val:
        dut.ui_in.value = current | (1 << pin_idx)  # Set bit to 1
    else:
        dut.ui_in.value = current & ~(1 << pin_idx) # Set bit to 0

# Helper function to simulate a human turning the knob
async def turn_encoder(dut, pin_a_idx, pin_b_idx, direction="CW", clicks=1):
    for _ in range(clicks):
        if direction == "CW":
            # Clockwise Sequence: A leads B
            set_pin(dut, pin_a_idx, 1); await ClockCycles(dut.clk, 20)
            set_pin(dut, pin_b_idx, 1); await ClockCycles(dut.clk, 20)
            set_pin(dut, pin_a_idx, 0); await ClockCycles(dut.clk, 20)
            set_pin(dut, pin_b_idx, 0); await ClockCycles(dut.clk, 20)
        else:
            # Counter-Clockwise Sequence: B leads A
            set_pin(dut, pin_b_idx, 1); await ClockCycles(dut.clk, 20)
            set_pin(dut, pin_a_idx, 1); await ClockCycles(dut.clk, 20)
            set_pin(dut, pin_b_idx, 0); await ClockCycles(dut.clk, 20)
            set_pin(dut, pin_a_idx, 0); await ClockCycles(dut.clk, 20)

@cocotb.test()
async def test_encoders(dut):
    dut._log.info("Starting Rotary Encoder Test")

    clock = Clock(dut.clk, 20, units="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 50)

    dut._log.info("Turning Encoder 1 Clockwise (3 clicks)...")
    await turn_encoder(dut, 1, 2, direction="CW", clicks=3)

    dut._log.info("Turning Encoder 2 Counter-Clockwise (5 clicks)...")
    await turn_encoder(dut, 3, 4, direction="CCW", clicks=5)

    # Trigger the audio beat to see the new Brightness value being used!
    dut._log.info("Triggering audio hit...")
    set_pin(dut, 0, 1) # Set ui_in[0] to 1
    await ClockCycles(dut.clk, 5)
    set_pin(dut, 0, 0) # Set ui_in[0] to 0

    # Wait long enough to see everything process
    await ClockCycles(dut.clk, 1000)
    dut._log.info("Simulation complete.")
