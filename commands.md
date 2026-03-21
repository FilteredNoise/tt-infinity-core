# Useful commands

### Run once per terminal session
```bash
source test/venv/bin/activate
```

### View waveforms
```bash
cd test
make
gtkwave tb.fst
cd ..
```

### Create diagram
```bash
cd test
make diagram
cd ..
```

## FPGA Test (Tang Nano 9K)

### Run once per terminal session
```bash
export PATH="$HOME/opt/oss-cad-suite/bin:$PATH"
```

### Build bitstream
```bash
cd fpga
./build.sh
cd ..
```
### Flash bitstream to temporary memory (fast, erased when unplugged)
```bash
cd fpga
openFPGALoader -b tangnano9k -m pack.fs
cd ..
```

### Flash bitstream to persistent flash (slower, but survives power-offs)
```bash
cd fpga
openFPGALoader -b tangnano9k -f pack.fs
cd ..
```

### Clear flash if needed
```bash
cd fpga
openFPGALoader -b tangnano9k -f pack.fs
cd ..
```