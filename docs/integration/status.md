# Integration status

30 October 2026. The planned simulation implementation is complete. Repository: https://github.com/jrmywm/SoCShield (private). Work is organized into staged commits; inspect Git history for the current published head.

| Work package | Observed result |
|---|---|
| WP0 baseline | Original RTL preserved. Static and update simulations, all nine positive formal jobs, negative controls, and independent audit of 13 VCD traces rerun PASS. Previous archive, live evidence and hashes preserved in `build/baseline-preserved/`. Regenerated baseline figures changed; original firewall RTL did not. |
| WP1 CPU boot | PASS at 916 simulated cycles. Pinned PicoRV32 ef203c2b0a3fb793280f5114941416c425c5b461 runs compiled RV32I/ILP32 C; xPack GCC 15.2.0-1 archive matches publisher SHA-256. Data/BSS/stack and byte/halfword/word checks pass. |
| WP2 control | Real-backend simulation PASS in both modes. Wrapper-local unbounded PDR and 20-cycle BMC PASS for both modes using the documented unconstrained backend abstraction. |
| WP3 memory path | DMA and SRAM directed tests PASS. SRAM/arbiter unbounded PDR and cover PASS with WORDS=4 and LATENCY=2. Per-job DMA counters reset on accepted start; range arithmetic retains the 35th carry bit. |
| WP4 demo | Both dedicated modes PASS with 1,067 accepted/completed DMA operations and an outstanding operation at actual update begin. Default deny, grant/readback, protected sentinel, broad-policy private/control/alias probes, revoke and repeated regrant checked. |
| WP5 integration checks | PASS 12-check entry point: three component simulations, six formal tasks, and semantic rejection of three mutants (early completion, address aliasing, wrong response owner). Root independently reran delegated component/formal work. CPU SRAM and DMA transactions are checked by an independent scoreboard. |
| WP6 evaluation | PASS 34 current-source runs: 24 deterministic mode/gap/CPU-access/stall cases and 10 seeded endpoint-stall cases. Final report verifies source hashes and derives active-job gaps separately from raw gaps including software idle time. |
| WP7 implementation | SKY130 HD mapped-area comparison independently rerun PASS for firewall/control wrapper: stop 29,577.1168 µm², shadow 42,024.0544 µm² (+42.1%). Native STA was unavailable; no timing, power, placement/routing, or physical FPGA claim. |
| WP8 report/package | Editable report, figures, architecture, requirements matrix, register documentation, student guide, pinned setup and reproduction/package commands provided. Package generation validates source/evidence freshness, archive integrity, and internal/external SHA-256 checksums. |

## Current evidence

2 November 2026 visual update: ten schematic views were exported from unchanged firewall/MMIO RTL with Yosys and Graphviz 14.1.3 via pinned Viz.js 3.25.0. Unedited DOT, rendered SVG, export recipes, logs, RTLIL JSON and source/output hashes are available. The architecture overview is explicitly labeled AI-assisted, while these circuit views are tool-generated. See `docs/integration/schematics.md` and `docs/integration/figures/schematics/manifest.json`. This adds structural visualization, not new functional/security proof claims.

2 November 2026 frontend update: a local-only browser dashboard now launches the existing `scripts/soc.py` flow and displays run metrics, testbench transaction events, simulation output, and an optional VCD waveform. An actual shadow-bank run launched through the dashboard passed at 17,279 simulated cycles, with 2,141 event records and a retrievable waveform. Python/JavaScript syntax checks passed. The run is retained at `build/soc/frontend-runs/20261102-172308-60b8ee/`. The refreshed source/evidence archive validated 965 files, internal hashes, and ZIP integrity. See `docs/integration/dashboard.md`. This remains RTL simulation, not physical FPGA control.

- `build/soc/boot/`, `demo-stop/`, `demo-shadow/`: firmware ELF/disassembly/image, logs, metrics, events, source manifests; demo VCDs.
- `build/soc/clean-stop/`, `clean-shadow/`: clean output-folder reproduction after moving the previous simulator cache aside; both PASS.
- `build/soc/verification/report.json`: current-source component tests, proof jobs, and mutants.
- `build/soc/evaluation/summary.csv`, `analysis.csv`: raw measurements and event-derived active-job analysis for all 34 runs.
- `build/soc/mapped/report.json`: mapped block cost, source and library hashes; timing explicitly unavailable.
- `build/soc/frontend-runs/`: timestamped runs launched from the browser interface.
- `evidence/integration/`: compact tracked results for review without a full rebuild.
- `docs/integration/results.md`: generated measured report; `reproduce.md`, `evidence-matrix.md`, `decisions.md`, `student-guide.md`: interpretation and reproduction.
- `deliverables/SoCShield-RISC-V-source-and-evidence.zip` and `.zip.sha256`: generated source/evidence package, produced by `scripts/package_soc.py`.

## Remaining limitations and continuation

No blocker remains for the agreed simulation deliverable. The CPU and DMA firmware demonstration is tested, not formally proved as a complete system. Wrapper proof abstracts the backend, SRAM proof reduces memory size, and DMA verification is simulation-based. Progress depends on eventual endpoint/response consumption. CPU and firmware are trusted. Single clock, coordinated reset, one outstanding DMA operation, four regions and a custom interface remain the stated scope.

Optional next work is a verified static-timing flow or an actual FPGA demonstration with borrowed hardware. These are not measured results and do not require purchasing hardware for the current project. After any code changes, rerun affected validation and regenerate manifests/report/archive. Do not present historical evidence as validating changed source.
