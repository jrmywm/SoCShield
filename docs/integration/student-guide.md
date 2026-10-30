# Student walkthrough and defense guide

This guide is a compact route through the implementation. Run the commands in [reproduce.md](reproduce.md) from the project root. The final boot, paired demonstrations, component verification, and 34-run evaluation were rebuilt and checked against current source hashes. Use [results.md](results.md) for measured findings and their limits. After later source changes, regenerate affected evidence before citing it.

## Walkthrough

1. **Boot the real CPU.** Run the `--boot` command. Follow `firmware/start.S` into `main()` and explain how the stack, BSS, initialized data, and private RAM are established. The firmware checks BSS/data, word stores, byte and halfword updates, and an independently observed boot signature. The result register and console are simulation-only.
2. **Follow one DMA store.** Firmware stages address, count, operation, and pattern at the DMA MMIO base. An accepted start snapshots the staging values, clears the previous job's results, and begins one outstanding word transaction. The request goes through the firewall before the SRAM arbiter. A successful write uses `pattern + word_index`; the next address is four bytes higher. The DMA consumes a response before issuing the next request.
3. **Compare denial with grant.** Before policy programming, a shared-memory DMA operation is denied and the sentinel is checked. Firmware then writes all four policy entries, including disabled entries, and commits. Allowed transfers are checked by firmware and an independent testbench memory/policy scoreboard. The register contract is in [registers.md](registers.md).
4. **Follow a revocation.** Firmware launches a long DMA job, then requests an update while a request is outstanding. The testbench tracks DMA handshakes and checks that the commit acknowledgment does not occur while that operation is outstanding. After revocation, denied operations do not alter the protected sentinel. Firmware later regrants and performs another transfer.
5. **Compare update modes.** Mode 0 stops acceptance while it drains/programs the sole bank. Mode 1 programs an inactive bank during traffic, then drains and switches. Both preserve the same authorization rule. Compare per-run source hashes and inputs before comparing cycle metrics. `--gap`, `--stall`, and `--contention` change the simulated workload conditions.

## Calculations to be able to explain

- **SRAM capacity and word index:** shared range is `[0x10000000, 0x10010000)`, or `0x10000` bytes = 65,536 bytes = 16,384 32-bit words. For a valid shared address, the index is `(address - 0x10000000) >> 2`. Full-address and alignment checks happen before indexing.
- **Firewall word containment:** the firewall checks the last byte with 33-bit arithmetic: `address + 3 <= inclusive_limit`. A word beginning at `0x100000fc` fits in a region ending at `0x100000ff`; one at `0x100000fd` does not.
- **DMA range check:** for a job of `count` words, the exclusive end is `base + 4*count`. The engine uses a 35-bit sum and accepts a range only if the base is aligned and the end is at most `2^32`. Thus base `0xfffffffc`, count `1` ends exactly at `2^32` and is representable; count `2` must be rejected. Count zero completes without issuing a request.
- **Write data:** word `i` writes `initial_pattern + i` modulo 2^32. The corresponding address is `base + 4*i`.
- **Result meaning:** `SUCCESS` and `DENIED` are per-job response counts and clear on accepted start. `CHECKSUM` is the XOR of successful read data for that job. `ERR` is sticky for rejected MMIO/start activity or denied memory responses, clears by writing bit 0, and also clears on accepted start.
- **Update evidence:** configuration submission, commit command acceptance, and commit acknowledgment are different events. Only the acknowledgment means the update's drain/switch contract completed. A permanent endpoint stall can prevent progress indefinitely.

## Questions to rehearse

1. **Who is trusted, and what does the firewall protect?** The CPU, firmware, and configuration path are trusted. The DMA-like peripheral is mediated before shared SRAM. The design does not defend against a compromised CPU or alternate physical access path.
2. **Why is the DMA not allowed to write firewall registers?** Its only memory request route is firewall to shared SRAM; the CPU-local address decoder is a separate path. Broad memory permissions cannot change this physical wiring or bypass SRAM's full-address check.
3. **What changes between stop and shadow mode?** Stop mode blocks new acceptance while it drains and rewrites one bank. Shadow mode writes the inactive bank while old-policy traffic continues, then blocks new acceptance, drains, and switches. Neither mode cancels already-issued writes.
4. **What does the formal evidence establish?** The standalone firewall proof establishes its asserted module safety properties under its explicit model. MMIO formal replaces the backend with an over-approximation and proves wrapper-local safety. Shared-SRAM proof covers its small endpoint model. None proves the CPU, firmware, complete SoC, physical memory, or liveness under an unbounded stall.
5. **What does the evaluation measure?** It measures simulation cycles and handshake gaps for specified firmware and endpoint schedules. It is not wall-clock performance, silicon timing, or an unconditional throughput guarantee.
6. **What is the technology-mapping result?** `mapped_soc.py` maps the firewall MMIO wrapper and its update logic to a pinned SKY130 HD library. Its area is a library cell-area estimate for that block. It is not whole-chip area, STA, post-layout timing, power, or measured silicon.
7. **What evidence must be checked before citing the integrated results?** Compare each run's source hashes and arguments, inspect `events.csv`/`metrics.csv`, ensure the current `tb_soc.sv` hash matches, and wait for `build/soc/evaluation/summary.csv`. A partial run directory is not the complete experiment.

## A defensible summary

Describe this as an integration and verification study of an existing runtime-configurable memory firewall, using a pinned reused CPU and compiled firmware. Separate the firewall's formal properties from system-level simulation, say which paths are trusted, and state that endpoint delay is modeled. Do not claim IOPMP or AXI compliance, a whole-CPU proof, silicon security, timing closure, or publication-level novelty.
