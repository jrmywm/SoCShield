# Reproduce the SoC integration

Run the commands from a PowerShell window at `C:\Users\User\Documents\SoCShield`. Generated binaries, logs, CSVs, manifests, and optional waveforms are written below `build/soc/`.

## Tools and source provenance

- The local OSS CAD Suite is in `tools/oss-cad-suite`; `tools/oss-cad-suite/VERSION` records `20261029`. It supplies Icarus Verilog, Yosys, SymbiYosys, solver dependencies, and a bundled Python interpreter at `lib/python3.exe`.
- Firmware uses xPack GNU RISC-V Embedded GCC `15.2.0-1`, RV32I/ILP32. The bundled archive is `tools/riscv-gcc.zip`; `tools/compiler-provenance.json` records its official release URL and SHA-256, while `tools/compiler-release.json` preserves release metadata. The compiler is extracted under `tools/xpack-riscv-none-elf-gcc-15.2.0-1/`. If reacquiring it, use the recorded official release and verify the archive digest before extracting.
- CPU RTL is PicoRV32 revision `ef203c2b0a3fb793280f5114941416c425c5b461`. Source hashes and repository are in `third_party/picorv32/provenance.json`; retain the included `third_party/picorv32/COPYING` license.
- `scripts/setup_soc.py` explicitly fetches/verifies pinned CPU, compiler archive, and area library when invoked. Normal simulation commands do not download dependencies. The large installed tool bundles are excluded from the source archive; install the pinned OSS CAD Suite described in the main README, then run the setup script with its Python interpreter.

## Boot and integrated runs

The firmware compiler, generated map, Icarus compile, and simulation are handled by `scripts/soc.py`:

The shorter entry point is `.\scripts\run_soc.ps1 boot`, `demo`, `verify`, `evaluate`, `map`, or `all`. Each command stops on a failing step. The lower-level commands are shown below for inspection and individual runs.

```powershell
& .\tools\oss-cad-suite\lib\python3.exe scripts\soc.py --boot --trace --out build/soc/boot
& .\tools\oss-cad-suite\lib\python3.exe scripts\soc.py --mode 0 --trace --out build/soc/demo-stop
& .\tools\oss-cad-suite\lib\python3.exe scripts\soc.py --mode 1 --trace --out build/soc/demo-shadow
```

`--boot` checks CPU startup before the longer policy/DMA demonstration. Mode 0 is stop-and-program; mode 1 is shadow-bank update. A successful full demonstration prints `PASS soc` and writes `manifest.json`, `metrics.csv`, and `events.csv`; `--trace` also writes `soc.vcd`. The manifest records source and ELF hashes and compiler version. Do not compare two modes as a controlled pair unless their source hashes and workload arguments match.

Optional schedule controls are `--gap N` (firmware idle-loop iterations while programming), `--contention 1` (firmware reads shared memory during configuration), `--stall N` (testbench-injected deterministic memory stall after the long transfer is armed), `--seed N`, and `--random-stalls`. These are simulation conditions, not hardware registers or physical timing measurements. `--out` selects a run directory relative to the project root. A stalled system is expected to finish only if the selected endpoint schedule eventually progresses.

## Component tests, formal jobs, and mutants

```powershell
& .\tools\oss-cad-suite\lib\python3.exe scripts\verify_integration.py
```

This compiles/runs MMIO, DMA, and shared-SRAM directed benches; runs MMIO wrapper PDR and BMC for both update modes plus shared-SRAM PDR/cover; and compiles/runs three semantic mutants. The aggregate report is `build/soc/verification/report.json`; per-check logs and solver work directories are alongside it. A passing wrapper proof is not an end-to-end SoC proof. Read [evidence-matrix.md](evidence-matrix.md) for the current evidence freshness caveat.

## Evaluation matrix

```powershell
& .\tools\oss-cad-suite\lib\python3.exe scripts\evaluate_soc.py
```

The script runs 34 integrated simulations: 24 paired settings across both modes, programming gaps 0/4/16, contention off/on, and injected stall 0/64; plus five seeded random-stall cases per mode. It creates per-run folders under `build/soc/evaluation/` and, only after the full batch finishes and validates, writes `build/soc/evaluation/summary.csv`. Review that CSV and run manifests before describing the matrix as complete. A partial set of per-run folders or `evaluation-run.log` is not a completed matrix.

## Wrapper technology mapping

`scripts/mapped_soc.py` calls Yosys and ABC through `PATH`. Add the local `bin` and `lib` folders before running it:

```powershell
$env:PATH = "$PWD\tools\oss-cad-suite\bin;$PWD\tools\oss-cad-suite\lib;$env:PATH"
& .\tools\oss-cad-suite\lib\python3.exe scripts\mapped_soc.py
```

The script checks the pinned SKY130 HD Liberty digest and writes logs, mapped netlists, JSON, cell counts, and `build/soc/mapped/report.json`. It maps `firewall_mmio` with `firewall_update` for both `SHADOW` settings, not the complete CPU/SoC. ABC's mapping target and output-load assumption are not static timing analysis. `report.json` currently marks timing unavailable; no timing closure, power, placement, routing, or silicon claim follows from this step.

## Address-map regeneration

`scripts/soc.py` invokes `scripts/generate_map.py` before each build. To regenerate explicitly:

```powershell
& .\tools\oss-cad-suite\lib\python3.exe scripts\generate_map.py
```

Edit `config/soc_map.json` as the source of truth. The generated files are `rtl/soc/soc_map.vh` and `firmware/soc_map.h`; the generator guards the fixed memory geometry. Do not edit those generated files by hand.

## Report and archive

```powershell
& .\tools\oss-cad-suite\lib\python3.exe scripts\report_soc.py
& .\tools\oss-cad-suite\lib\python3.exe scripts\package_soc.py
```

Report generation refuses stale source hashes, missing required matrix cases, a dedicated demo without actual outstanding-update overlap, failed verification, or stale mapped inputs. It derives `analysis.csv` from real transaction events, separating gaps within the designated DMA job from inter-job firmware idle time. The archive includes source and compact evidence with an internal SHA-256 manifest and an external archive checksum.

For a clean reproduction without deleting preserved evidence, run `soc.py --out build/soc/clean-reproduction` for a fresh run folder. The Icarus cache is content-addressed; it can be bypassed by moving its directory aside before rebuilding. `evaluate_soc.py --resume` reuses only passing runs whose recorded source hashes still match; it does not reuse stale evidence.

## Interpreting results

The CPU executes real RTL instructions and compiled firmware in Icarus. Console output, memory delay, and SRAM behavior are simulated. An event CSV is a cycle-level simulation trace; it is not a hardware capture. Formal proofs cover only their named RTL modules and assumptions. [evidence-matrix.md](evidence-matrix.md) identifies which results are current, which require a rerun, and where the reports live.
