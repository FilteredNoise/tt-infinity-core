#!/bin/bash
set -e
export PATH="$HOME/opt/oss-cad-suite/bin:$PATH"

rm -f *.json *.fs
echo "--- Synthesizing ---"
# Note: include BOTH top.v and the project.v
yosys -p "read_verilog top.v ../src/project.v; synth_gowin -top top -json project.json"

echo "--- Placing & Routing ---"
nextpnr-himbaechel --json project.json \
                   --write pnr_project.json \
                   --device GW1NR-LV9QN88C6/I5 \
                   --vopt family=GW1N-9C \
                   --vopt cst=tangnano9k.cst

echo "--- Packing ---"
gowin_pack -d GW1N-9C -o pack.fs pnr_project.json
echo "--- Done ---"
