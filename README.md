# Neanderthal 2170XR: two-wide superscalar RISC-V core

A **two-wide, in-order superscalar RV32I processor with instruction and data caches**, written in **Bluespec SystemVerilog** and tested in simulation against a RISC-V test suite. A port to the **OrangeCrab** (Lattice ECP5) FPGA board is in progress. It was built in spring 2023 for MIT's Constructive Computer Architecture course (6.1920).

**Team:** Ahmad Taka and Neel Mondal. Development history lives in the original repo, [`nmondal417/Neanderthal2170XR`](https://github.com/nmondal417/Neanderthal2170XR); this repo is a reorganized copy made with Neel's permission. MIT license; see [LICENSE](LICENSE).

## Status

| Area | Status |
|---|---|
| Cache (lab) | ✅ Passes the randomized cache test |
| Pipelined core + caches | ✅ Passes the test programs |
| Superscalar core + caches | ✅ Passes all 11 test programs in simulation |
| Superscalar with 16-byte lines | 🟡 Some tests pass |
| OrangeCrab FPGA port | 🟡 Compiles to Verilog with a 1 KB block-RAM main memory; LiteDRAM not integrated; no bitstream committed |

## How the design evolved

Each folder under `fpga/` is a self-contained snapshot, with its own `Makefile`, test programs and `elf2hex`.

| Folder | What it adds |
|---|---|
| [`fpga/cache_lab`](fpga/cache_lab) | Direct-mapped, write-back, write-allocate cache: 128 lines × 64 B (8 KB). Data lives in block RAM; tags, valid and dirty bits in registers. A store buffer is written but disabled. It's tested in isolation against an ideal memory with random requests (`./Beveren`). |
| [`fpga/processor_cache`](fpga/processor_cache) | Multicycle and 4-stage pipelined RV32I cores connected to the caches |
| [`fpga/processor_cache_test`](fpga/processor_cache_test) | A working copy of `processor_cache` that adds `Supfifo.bsv`, the two-entry FIFO the superscalar pipeline is built on |
| [`fpga/superscalar_cache`](fpga/superscalar_cache) | **The main design**: two-wide superscalar core, 1 KB instruction cache returning two words, 1 KB data cache |
| [`fpga/superscalar_cache_small`](fpga/superscalar_cache_small) | Same core with 4-word (16 B) cache lines and a 128-bit memory interface, aimed at fitting the FPGA (`arrange_mem.py` repacks memory images). Work in progress. |
| [`fpga/superscalar_orangecrab`](fpga/superscalar_orangecrab) | OrangeCrab r0.2 top level (`OrangeCrabTop.bsv`) with a USB-serial console and an RGB LED. Main memory is a preloaded 16 × 512-bit block RAM. |

## Microarchitecture (`fpga/superscalar_cache`)

```
 fetch ──► decode ──► execute 1 ──► writeback
 (2/cyc)   (scoreboard  execute 2      (2/cyc if
            + epoch)    (ALU/branch)    no load/store)
     ▲                                     │
     └──── redirect on mispredict (epoch++) ◄┘
```

- **Fetch** sends one request per cycle for the PC. If PC+4 is in the same 64-byte line, the instruction cache returns both words and two instructions are fetched (PC += 8); otherwise one is fetched. The next PC is always predicted as sequential.
- **Decode** reads the register file and checks a 32-entry **scoreboard**. Both instructions issue when neither has a pending source or destination and the second doesn't read the first's result. Otherwise only the first issues. Instructions from the wrong path are dropped by comparing their **epoch** tag with the current one.
- **Execute** has two lanes, written as two separate Bluespec rules so both can fire in one cycle. Lane 2 handles only ALU and branch instructions; loads and stores go through lane 1. A mispredicted branch or jump bumps the epoch and redirects the PC.
- **Writeback** retires two instructions per cycle when neither is a memory operation. It clears scoreboard bits and writes the register file.
- The PC, register file, scoreboard and epoch are **EHRs** (ephemeral history registers), so rules in the same cycle see each other's updates in a fixed order.
- **Caches:** direct-mapped, write-back, 16 lines × 64 B each, with block RAM for data and a small miss state machine (`Ready → StartMiss → SendFillReq → WaitFillResp`). The instruction cache returns a 65-bit "one or two words" response.
- **Memory-mapped I/O:** `0xF000FFF0` prints a character, `0xF000FFF4` prints an integer, `0xF000FFF8` ends the test with pass/fail.
- **Instrumentation:** counters for how often execute and writeback handle two instructions, and **Konata** pipeline traces (`output.log`, open in the Konata viewer).

## Running the simulation

Needs the [Bluespec compiler `bsc`](https://github.com/B-Lang-org/bsc) and, to rebuild the test programs, a `riscv64-unknown-elf-gcc` toolchain.

```bash
cd fpga/superscalar_cache
make                          # builds ./top_pipelined with bsc -sim
./test.sh add32               # copies test/build/add32.hex to mem.vmh
./top_pipelined               # runs; prints PASS / FAIL
./test_all_pipelined.sh       # runs all 11 programs
```

Test programs (`test/src/*.c`): `add`, `and`, `or`, `sub`, `xor`, `hello`, `mul`, `reverse`, `thelie`, `thuemorse` and `matmul`. They are compiled for `rv32i` and turned into 512-bit-wide hex files (one cache line per line) by SiFive's `elf2hex`. Prebuilt `.hex` files are in `test/build/`. To rebuild them:

```bash
cd test && make
```

The cache lab runs on its own: `cd fpga/cache_lab && make && ./Beveren`.

## FPGA build (`fpga/superscalar_orangecrab`)

The target is the OrangeCrab r0.2 (ECP5-25F, CSFBGA285), built with the open-source toolchain:

```bash
./TestBuildUsb.sh             # bsc -verilog OrangeCrabTop.bsv into build/, copies the USB core, BRAM/FIFO Verilog, pins and Makefile
cd build
make                          # yosys synth_ecp5 → nextpnr-ecp5 (usborange.pcf) → ecppack → color.dfu
make dfu                      # dfu-util upload to the OrangeCrab bootloader
```

The core's character and integer output goes to the host over USB serial, using the TinyFPGA BX USB-serial core in `tinyfpga_bx_usbserial/`.

`TestBuildUsb.sh` sets `USBCORE` to an absolute path from the original Linux machine; point it at `tinyfpga_bx_usbserial/` before use. `Litedram.bsv`, `litedram.v` and `DramOnly.py` are the start of an unfinished LiteDRAM (DDR3) main-memory integration.

## Notes

- Bluespec build outputs (`build/`, `*.bo`, `*.so` and the generated simulator launchers such as `top_pipelined`) are git-ignored; `make` regenerates them. The prebuilt test programs in `test/build/*.hex` are kept.
- `docs/STRUCTURE.md` describes the folder conventions shared across my projects.
