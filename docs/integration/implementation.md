# Mapped firewall wrapper implementation study

`scripts/mapped_soc.py` maps `firewall_mmio` plus its `firewall_update` instance separately with `SHADOW=0` and `SHADOW=1`, using four policy entries in each active bank. This is a wrapper-and-firewall comparison, not a whole-SoC or SRAM measurement. It flattens the design, uses `dfflibmap` followed by ABC with one identical 5000 ps mapping target, the SKY130 HD buffer `sky130_fd_sc_hd__buf_2`, and 10 fF output load. The library is pruned of the probe and low-power flow cells; both variants use the same resulting file. A mapping target is not measured delay or proof of timing closure.

Run in PowerShell after putting Yosys/ABC on PATH:

```powershell
$env:PATH = "$PWD\tools\oss-cad-suite\bin;$PWD\tools\oss-cad-suite\lib;" + $env:PATH
python scripts/mapped_soc.py
```

A standard Python 3 installation may replace `python` above. If Python is unavailable on PATH, this workstation has a bundled interpreter at `C:\Users\User\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe`. Outputs, including logs, mapped netlists, JSON netlists, cell statistics, and source/library hashes, are in `build/soc/mapped/`. The script refuses an incorrect library hash, a failed Yosys structural check, any unmapped or unknown top-level cell, or a result without mapped sequential cells. Areas are sums of the Liberty cell area attributes, in square micrometres; they omit floorplan, routing, clock tree, filler and physical effects.

The source library is `sky130hd_tt.lib.gz` from [OpenSTA's pinned upstream repository](https://github.com/parallaxsw/OpenSTA/blob/b99a8e528de098e4e06dbb6a0bb5423d6ada2f51/examples/sky130hd_tt.lib.gz), commit `b99a8e528de098e4e06dbb6a0bb5423d6ada2f51`, SHA-256 `210e56be3a3a0907b5241a34d277f664cf4b4d91dcb49a27ff813df4406a5889`. The report records the source and pruned hashes and RTL hashes. See the upstream repository for provenance and applicable licenses.

**Timing is unavailable in this run.** The local OSS CAD Suite bin directory did not contain OpenSTA/`sta` or OpenROAD, and PowerShell command lookup found no `sta` or `openroad` on PATH. WSL reports version 2 but `wsl --list --quiet` showed no installed distributions; Docker's client could not reach a daemon. Consequently there is no SDC, endpoint coverage audit, setup/hold analysis, critical path, frequency, or timing-closure claim. ABC's 5 ns target and the synthesis netlist are not a substitute for STA. A future timing run needs a verified STA executable, a common clock and I/O delays, reset treatment, explicit loading/driving assumptions, and checks that every relevant endpoint is constrained. Results would still be prelayout, single-corner estimates rather than signoff.

## Observed run

On Yosys `0.70+277` (commit `77dddbd66`), the checked mapping produced:

| Configuration | Mapped cells | Sequential cells | Cell area (µm²) |
|---|---:|---:|---:|
| SHADOW=0 | 3,334 | 590 | 29,577.1168 |
| SHADOW=1 | 4,172 | 861 | 42,024.0544 |

The shadow configuration used approximately 42.1% more mapped cell area in this run. This is not total chip area or a timing or power comparison. The exact input hashes, synthesized netlists, and tool details are in `build/soc/mapped/report.json` and associated logs.
