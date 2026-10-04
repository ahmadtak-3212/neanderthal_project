#!/bin/bash
# run_tests.sh [design] [mem]  -- build one design with bsc and run all 11 test programs, printing
# PASS/FAIL, cycle count, instructions written back, IPC and how often two instructions retired together.
#   design: a folder under fpga/ (default superscalar_cache); processor_cache gives the single-issue baseline
#           (cycles only, it has no dual-issue counters)
#   mem:    "dual" (default) uses the dual-port simulation memory mkMainMem2;
#           "as-is" keeps whatever top_pipelined.bsv instantiates (the final commit uses mkMainMemFPGA,
#           which hangs on thelie and matmul; see README "Known issues").
# Works on a temporary copy; the repo is not modified. Needs bsc (and tcl8.6) on PATH.
set -e
D=${1:-superscalar_cache}; MEM=${2:-dual}
HERE=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d); cp -r "$HERE/fpga/$D" "$W/d"; cd "$W/d"
find . -type f \( -name '*.bsv' -o -name '*.sh' -o -name Makefile -o -name '*.hex' -o -name '*.vmh' \) -exec sed -i 's/\r$//' {} +
# instrumentation: quiet debug prints, print the dual-issue counters every cycle, print the cycle count at exit
sed -i 's/let debug = True;/let debug = False;/; s/if (count == 1000) begin/if (True) begin/' pipelined.bsv
sed -i "0,/if (req.addr == 'hf000_fff8) begin/s//if (req.addr == 'hf000_fff8) begin \$fdisplay(stderr, \"CYCLES %0d\", cycle_count);/" top_pipelined.bsv
[ "$MEM" = dual ] && sed -i 's/MainMem2 dram <- mkMainMemFPGA;/MainMem2 dram <- mkMainMem2;/' top_pipelined.bsv
rm -rf build top_pipelined top_pipelined.so; make >/dev/null 2>&1 || { echo "build failed (see $W/d)"; exit 1; }
printf '%-10s %-6s %10s %10s %6s %10s\n' test result cycles instrs IPC dual_wb
for t in ${TESTS:-add and or sub xor hello mul reverse thuemorse thelie matmul}; do
  cp test/build/${t}32.hex mem.vmh
  set +e; timeout ${TIMEOUT:-600} ./top_pipelined 2> err.txt | grep -a "Times in Writeback" | tail -1 > wb.txt; set -e
  r=$(grep -ao 'PASS\|FAIL' err.txt | head -1); c=$(grep -a CYCLES err.txt | awk '{print $2}')
  read -r _ _ _ w _ _ dw < <(tr -s ' ' < wb.txt) || true
  if [ -n "$c" ] && [ -n "$w" ]; then
    awk -v t=$t -v r=$r -v c=$c -v w=$w -v dw=$dw 'BEGIN{printf "%-10s %-6s %10d %10d %6.2f %9.0f%%\n",t,r,c,w+dw,(w+dw)/c,100*dw/w}'
  elif [ -n "$c" ]; then printf '%-10s %-6s %10d\n' $t "$r" $c
  else printf '%-10s %-6s\n' $t "${r:-TIMEOUT}"; fi
done
rm -rf "$W"
