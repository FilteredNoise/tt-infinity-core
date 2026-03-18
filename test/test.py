import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


def set_pin(dut, pin_idx, val):
    current = int(dut.ui_in.value) if dut.ui_in.value.is_resolvable else 0
    if val:
        dut.ui_in.value = current | (1 << pin_idx)
    else:
        dut.ui_in.value = current & ~(1 << pin_idx)


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
async def test_infinity_core_interrupt(dut):
    dut._log.info("Starting Audio Interrupt Test")

    clock = Clock(dut.clk, 20, units="ns")
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 50)

    dut._log.info("1. Setting Brightness/Decay...")
    await turn_encoder(dut, 1, 2, direction="CW", clicks=20)  # High brightness
    await turn_encoder(dut, 3, 4, direction="CCW", clicks=128)  # Super Fast decay

    dut._log.info("2. Waiting 15ms for OLED to boot and idle...")
    await ClockCycles(dut.clk, 750000)  # 15ms wait

    dut._log.info("3. BASS DROP! Firing audio trigger...")
    set_pin(dut, 0, 1)  # audio_trig goes HIGH
    await ClockCycles(dut.clk, 10)
    set_pin(dut, 0, 0)  # audio_trig goes LOW

    dut._log.info("4. Watching the instant reaction...")
    # Wait 5ms (250,000 cycles) to watch it blast the SPI data and start decaying
    await ClockCycles(dut.clk, 250000)

    dut._log.info("Simulation complete!")
