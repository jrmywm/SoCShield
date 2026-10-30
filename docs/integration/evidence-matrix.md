# Requirements and evidence matrix

All paths are relative to the project root. Final report generation checks source hashes before accepting the evidence. PASS has the bounded meaning stated in each row.

| ID | Requirement | Implementation | Validation and evidence |
|---|---|---|---|
| I-01 | Compiled firmware boots and checks data, BSS, stack, byte/halfword/word memory operations | `firmware/`, `soc_top.sv`, attributed PicoRV32 | PASS boot at 916 cycles; independent signature in `tb_soc.sv`; `build/soc/boot/manifest.json`, ELF, disassembly and log |
| I-02 | Whole entries are snapshotted, commands cannot silently overwrite pending commands, invalid ordering is visible | `firewall_mmio.sv` | PASS `tb_mmio` for both modes; wrapper PDR/BMC; `build/soc/verification/report.json` |
| I-03 | Commit sequence advances only in response to actual backend acknowledgment | `firewall_mmio.sv`, `firewall_update.sv` | PASS wrapper abstraction proof plus actual-backend simulation; premature-completion mutant is rejected |
| I-04 | DMA holds one request, snapshots jobs, rejects wrapping ranges, accounts for responses | `dma_engine.sv` | PASS directed `tb_dma`, including 35-bit overflow regression, repeated starts, stalls, errors, checksum and reset; simulation evidence only |
| I-05 | SRAM validates full addresses, applies byte enables, preserves memory over protocol reset | `shared_sram.sv` | PASS directed `tb_shared`; alias mutant is rejected; `build/soc/verification/` |
| I-06 | SRAM responses preserve requester ownership and remain stable under backpressure | `shared_sram.sv` | PASS PDR and cover with WORDS=4 / LATENCY=2 / initial reset; directed reset/production-addressing tests; wrong-owner mutant is rejected |
| I-07 | DMA cannot reach CPU private memory or MMIO through broad rules/address aliases | `soc_top.sv`, `shared_sram.sv` | PASS three broad-policy address probes in both full-system demos; independent error/payload and final SRAM checks |
| I-08 | Default deny, grants, read/write protection, revoke and regrant work end-to-end | `firmware/main.c` and integrated RTL | PASS both dedicated demos, 1,067 accepted/completed operations each; `build/soc/demo-stop/` and `demo-shadow/` |
| I-09 | Dedicated revocation actually overlaps an operation and never acknowledges with old work outstanding | `firewall_update.sv`, `tb_soc.sv` | PASS actual event/scoreboard checks in both dedicated demos; original update module safety proof retained; separate scopes |
| I-10 | CPU shared requests receive matching exactly-once responses; measurements record real contention | `soc_top.sv`, `shared_sram.sv`, `tb_soc.sv` | PASS independent CPU request/response/data scoreboard; `cpu_accepted`, `cpu_completed`, `contested_cycles` in metrics |
| I-11 | Workload comparison is reproducible with phase information | `evaluate_soc.py`, `soc.py`, `tb_soc.sv` | PASS 24 deterministic settings plus five seeded endpoint-stall runs per mode; `build/soc/evaluation/summary.csv`; all manifests match final source |
| I-12 | Gaps within a DMA job are distinguished from software idle time | `report_soc.py` | Validated 1,024-word job identities from address/data signatures; `analysis.csv`; raw gaps retained; slow shadow jobs flagged when finishing before commit |
| I-13 | Firmware and CPU decoder use one address-map source | `config/soc_map.json`, `generate_map.py` | Generated HDL/C constants used on every build; geometry guards; full-address endpoint tests. This is consistency checking, not a security proof |
| I-14 | Wrapper hardware cost is compared under one technology library/settings | `mapped_soc.py` | PASS independently rerun SKY130 HD mapping; source/library hashes, cell whitelist and structural checks; `build/soc/mapped/report.json` |
| I-15 | Standalone baseline remains reproducible | Original firewall RTL, tests and scripts | PASS static/update simulations, nine positive formal jobs, deliberate faults and independent audit of 13 VCD traces rerun; baseline preserved in `build/baseline-preserved/` |

The wrapper formal backend is unconstrained and abstract: that proof does not establish the real firewall's permission or acknowledgment behavior. The SRAM formal harness uses reduced memory and initial reset. Full-system CPU/firmware behavior is tested by simulation. No DMA formal proof, whole-system formal proof, unconditional liveness, static timing closure, power, or physical FPGA claim is made.

After source changes, re-run affected validation and regenerate the report. A previous PASS with a different source hash is historical evidence, not validation of the changed implementation. [status.md](status.md) records the final milestone state and remaining physical implementation limitations.
