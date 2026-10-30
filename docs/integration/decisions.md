# Integration decisions

- **Reuse PicoRV32 RV32I.** Its native interface fits a small one-clock design and the existing Icarus environment. The pinned revision boots compiled C firmware; no CPU change is needed. Upstream is archived, so provenance is pinned and maintenance is not assumed. CPU RTL is attributed, not claimed as project-original.
- **Keep the firewall protocol.** It remains the existing aligned, one-outstanding ready/valid protocol. A CPU-local bridge handles the native CPU bus. No AXI or IOPMP compatibility claim follows.
- **Use private firmware memory.** Instruction fetch, stack, and control accesses do not pass through the DMA firewall. Explicit CPU accesses to the shared SRAM can still wait behind DMA; firmware should poll the independent control interface when managing a stalled transfer.
- **Use a bounded command mailbox.** The CPU can poll while an entry or commit waits. Entry submission snapshots all fields; concurrent staging edits cannot alter the queued command. Invalid commands fail visibly rather than occupying the mailbox forever.
- **Persist completion.** The wrapper turns a one-cycle acknowledgment into a modulo-2^32 sequence counter. Command admission, command handshake, and policy activation have separate meanings.
- **Check the complete memory address.** Permission rules authorize requests, while the SRAM endpoint enforces which physical target exists on the DMA route. A broad rule cannot expose CPU MMIO through low-bit aliases.
- **Treat denied responses as normal test outcomes.** The DMA continues its configured count and records per-job successes, errors and read checksum. Invalid control accesses remain diagnosable. Results clear on each accepted start.
- **Separate verification levels.** Existing firewall proofs, abstract-backend wrapper proofs, reduced-memory arbiter proofs, directed tests, and firmware execution cover different obligations. None alone proves the whole system.
- **Measure phase rather than hide it.** The dedicated demo requires a busy update. The wider workload matrix permits busy or idle update arrival and records that fact. Programming-loop iterations and simulation cycles are different quantities.
- **Report mapped area without timing.** A pinned public SKY130 HD library supports a fair cell-area comparison. Native static-timing tooling was unavailable in the inspected setup, so there is no claimed critical path, frequency, timing closure, or physical implementation.

The necessary next platform step, if desired, is obtaining an independently validated timing-analysis flow or access to an FPGA board. Neither is a hidden requirement for the current simulation deliverable.
