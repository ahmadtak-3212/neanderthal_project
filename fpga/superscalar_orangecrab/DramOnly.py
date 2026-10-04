#!/usr/bin/env python3

# This file is Copyright (c) Greg Davill <greg.davill@gmail.com>
# License: BSD


# This variable defines all the external programs that this module
# relies on.  lxbuildenv reads this variable in order to ensure
# the build will finish without exiting due to missing third-party
# programs.
# LX_DEPENDENCIES = ["riscv", "nextpnr-ecp5", "yosys"]

# Import lxbuildenv to integrate the deps/ directory

import sys
import os
import shutil
import argparse
import subprocess

import inspect

from migen import *
from migen.genlib.resetsync import AsyncResetSynchronizer

from litex_boards.platforms import gsd_orangecrab
#from litex_boards.targets.orangecrab import _CRG

from litex.build.lattice.trellis import trellis_args, trellis_argdict

from litex.build.generic_platform import IOStandard, Subsignal, Pins, Misc

from litex.soc.cores.clock import *
from litex.soc.integration.soc_core import *
#from litex.soc.integration.soc_sdram import *
from litex.soc.integration.builder import *
from litex.soc.interconnect import wishbone
from litex.soc.interconnect.axi import axi_lite

from litedram.modules import MT41K64M16, MT41K128M16, MT41K256M16, MT41K512M16
from litedram.phy import ECP5DDRPHY

from litex.soc.doc import generate_docs


from migen.genlib.cdc import MultiReg



from litex.soc.cores.gpio import GPIOTristate, GPIOOut, GPIOIn

# from valentyusb.usbcore import io as usbio


# # connect all remaninig GPIO pins out
# extras = [
#     ("gpio", 0, Pins("GPIO:0 GPIO:1 GPIO:5 GPIO:6 GPIO:9 GPIO:10 GPIO:11 GPIO:12 GPIO:13  GPIO:18 GPIO:19 GPIO:20 GPIO:21"), 
#         IOStandard("LVCMOS33"), Misc("PULLMODE=DOWN")),
#     ("analog", 0,
#         Subsignal("mux", Pins("F4 F3 F2 H1")),
#         Subsignal("enable", Pins("F1")),
#         Subsignal("ctrl", Pins("G1")),
#         Subsignal("sense_p", Pins("H3"), IOStandard("LVCMOS33D")),
#         Subsignal("sense_n", Pins("G3")),
#         IOStandard("LVCMOS33")
#     )
# ]


# CRG ---------------------------------------------------------------------------------------------

class CRG(Module):
    def __init__(self, platform, sys_clk_freq, with_usb_pll=False):
        self.clock_domains.cd_init     = ClockDomain()
        self.clock_domains.cd_por      = ClockDomain(reset_less=True)
        self.clock_domains.cd_sys      = ClockDomain()
        self.clock_domains.cd_sys2x    = ClockDomain()
        self.clock_domains.cd_sys2x_i  = ClockDomain()


        # # #

        self.stop = Signal()
        self.reset = Signal()

        
        # Use OSCG for generating por clocks.
        osc_g = Signal()
        self.specials += Instance("OSCG",
            p_DIV=6, # 38MHz
            o_OSC=osc_g
        )

        # Clk
        clk48 = platform.request("clk48")
        por_done  = Signal()

        # Power on reset 10ms.
        por_count = Signal(24, reset=int(48e6 * 50e-3))
        self.comb += self.cd_por.clk.eq(osc_g)
        self.comb += por_done.eq(por_count == 0)
        self.sync.por += If(~por_done, por_count.eq(por_count - 1))
        self.comb += self.cd_init.clk.eq(osc_g)

        # PLL
        sys2x_clk_ecsout = Signal()
        self.submodules.pll = pll = ECP5PLL()
        self.comb += pll.reset.eq(~por_done)
        pll.register_clkin(clk48, 48e6)
        pll.create_clkout(self.cd_sys2x_i, 2*sys_clk_freq)
        self.specials += [
            Instance("ECLKBRIDGECS",
                i_CLK0   = self.cd_sys2x_i.clk,
                i_SEL    = 0,
                o_ECSOUT = sys2x_clk_ecsout),
            Instance("ECLKSYNCB",
                i_ECLKI = sys2x_clk_ecsout,
                i_STOP  = self.stop,
                o_ECLKO = self.cd_sys2x.clk),
            Instance("CLKDIVF",
                p_DIV     = "2.0",
                i_ALIGNWD = 0,
                i_CLKI    = self.cd_sys2x.clk,
                i_RST     = self.reset,
                o_CDIVX   = self.cd_sys.clk),
            #AsyncResetSynchronizer(self.cd_sys,   ~pll.locked ),
            #AsyncResetSynchronizer(self.cd_sys2x, ~pll.locked ),
            AsyncResetSynchronizer(self.cd_sys2x_i, ~pll.locked ),
        ]

        # USB PLL
        if with_usb_pll:
            self.clock_domains.cd_usb_12 = ClockDomain()
            self.clock_domains.cd_usb_48 = ClockDomain()
            usb_pll = ECP5PLL()
            self.comb += usb_pll.reset.eq(~por_done)
            self.submodules += usb_pll
            usb_pll.register_clkin(clk48, 48e6)
            usb_pll.create_clkout(self.cd_usb_48, 48e6)
            usb_pll.create_clkout(self.cd_usb_12, 12e6)


# BaseSoC ------------------------------------------------------------------------------------------

class BaseSoC(SoCCore):
    mem_map = {
        # "rom":      0x00000000,  # (default shadow @0x80000000)
        # "sram":     0x10000000,  # (default shadow @0xa0000000)
        # "spiflash": 0x20000000,  # (default shadow @0xa0000000)
        "main_ram": 0x00000000,  # (default shadow @0xc0000000)
        # "csr":      0xe0000000,  # (default shadow @0xe0000000)
    }
    mem_map.update(SoCCore.mem_map)

    # interrupt_map = {
    #     "timer0": 2,
    #     "usb": 3,
    # }
    # interrupt_map.update(SoCCore.interrupt_map)
    #
    def __init__(self, name="Rvtest", sys_clk_freq=int(48e6), toolchain="trellis", **kwargs):
        # Board Revision ---------------------------------------------------------------------------
        revision = kwargs.get("revision", "0.2")
        device = kwargs.get("device", "25F")

        platform = gsd_orangecrab.Platform(revision=revision, device=device ,toolchain=toolchain)

        # platform.add_extension(extras)

        self.submodules.crg = crg = CRG(platform, sys_clk_freq, with_usb_pll=True)
      
        # Disconnect Serial Debug (Stub required so BIOS is kept happy)
        kwargs['uart_name']="stream"

        # SoCCore ----------------------------------------------------------------------------------
        SoCCore.__init__(self, platform, clk_freq=sys_clk_freq, **kwargs)
        axi_bus = axi_lite.AXILiteInterface()
        self.bus.add_master(name="toProc", master=axi_bus)
        platform.add_extension(axi_bus.get_ios("axi"))
        axi_pads = platform.request("axi")
        self.comb += axi_bus.connect_to_pads(axi_pads, mode="slave")

        # connect UART stream to NULL
        self.comb += self.uart.source.ready.eq(1)
        
        # CRG --------------------------------------------------------------------------------------

        # DDR3 SDRAM -------------------------------------------------------------------------------
        if not self.integrated_main_ram_size:
            print("OK doing DRAM")
            available_sdram_modules = {
                "MT41K64M16":  MT41K64M16,
                "MT41K128M16": MT41K128M16,
                "MT41K256M16": MT41K256M16,
                "MT41K512M16": MT41K512M16,
            }
            sdram_module = available_sdram_modules.get(kwargs.get("sdram_device", "MT41K64M16"))

            ddram_pads = platform.request("ddram")
            self.submodules.ddrphy = ECP5DDRPHY(
                pads         = ddram_pads,
                sys_clk_freq = sys_clk_freq)
            self.ddrphy.settings.rtt_nom = "disabled"
            self.add_csr("ddrphy")
            if hasattr(ddram_pads, "vccio"):
                self.comb += ddram_pads.vccio.eq(0b111111)
            if hasattr(ddram_pads, "gnd"):
                self.comb += ddram_pads.gnd.eq(0)
            self.comb += self.crg.stop.eq(self.ddrphy.init.stop)
            self.comb += self.crg.reset.eq(self.ddrphy.init.reset)
            self.add_sdram("sdram",
                phy                     = self.ddrphy,
                module                  = sdram_module(sys_clk_freq, "1:2"),
                origin                  = self.mem_map["main_ram"],
                size                    = kwargs.get("max_sdram_size", 0x40000000),
                l2_cache_size           = 0,
            )

        
        # drive PROGRAMN HIGH
        self.comb += platform.request("rst_n").eq(1)


# Build --------------------------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="LiteX SoC on OrangeCrab")
    parser.add_argument("--gateware-toolchain", dest="toolchain", default="trellis",
        help="gateware toolchain to use, trellis (default) or diamond")
    builder_args(parser)
    soc_core_args(parser)
    trellis_args(parser)
    parser.add_argument("--sys-clk-freq", default=48e6,
                        help="system clock frequency (default=48MHz)")
    parser.add_argument("--revision", default="0.2",
                        help="Board Revision {0.1, 0.2} (default=0.2)")
    parser.add_argument("--device", default="25F",
                        help="ECP5 device (default=25F)")
    parser.add_argument("--sdram-device", default="MT41K64M16",
                        help="ECP5 device (default=MT41K64M16)")
    parser.add_argument("--docs-only", default=False, action='store_true',
                        help="Create docs")
    args = parser.parse_args()

    soc = BaseSoC(toolchain=args.toolchain, sys_clk_freq=int(float(args.sys_clk_freq)),**argdict(args))
    
    if args.docs_only:
        args.no_compile_software = True
        args.no_compile_gateware = True
    builder = Builder(soc, **builder_argdict(args))

    # soc.write_usb_csr(builder.generated_dir)

        
    # Build gateware
    builder_kargs = trellis_argdict(args) if args.toolchain == "trellis" else {}
    vns = builder.build(**builder_kargs)
    soc.do_exit(vns)   

    generate_docs(soc, "build/documentation/", project_name="OrangeCrab Test SoC", author="Greg Davill")

    input_config = os.path.join(builder.output_dir, "gateware", f"{soc.platform.name}.config")

    # create compressed bitstream (ECP5 specific), (Note that `-spimode qspi` sometimes doesn't load over JTAG)
    output_bitstream = os.path.join(builder.gateware_dir, f"{soc.platform.name}.bit")
    os.system(f"ecppack --freq 38.8 --spimode qspi --compress --input {input_config} --bit {output_bitstream}")

    dfu_file = os.path.join(builder.gateware_dir, f"{soc.platform.name}.dfu")
    shutil.copyfile(output_bitstream, dfu_file)
    os.system(f"dfu-suffix -v 1209 -p 5af0 -a {dfu_file}")

def argdict(args):
    r = soc_core_argdict(args)
    for a in ["device", "revision", "sdram_device"]:
        arg = getattr(args, a, None)
        if arg is not None:
            r[a] = arg
    return r

if __name__ == "__main__":
    main()
