# Presenting and defending SoCShield

This is a five-minute demonstration script followed by a rehearsal guide. It follows the existing firmware and evidence; it does not add a different workload. Console messages indicate that preceding firmware checks completed. The independent testbench checks the transactions and memory effects as well.

## Before presenting

Run the paired demonstration from the repository root:

```powershell
.\scripts\run_soc.ps1 demo
```

Keep both `build/soc/demo-stop/simulation.log` and `build/soc/demo-shadow/simulation.log`, their metrics and manifests, and `docs/integration/results.md` available. Check both logs for `PASS soc`. These commands execute the compiler and simulator; merely opening a report does not rerun them.

The dashboard can show individual runs and replay saved events after a run. Use mode 0 and mode 1 with identical settings: programming gap 0, memory stall 0, CPU shared-memory reads off, seed 1. Preserve each run directory before switching views. Use the logs and results table as the presentation's dependable core; the animation is optional. Browser interaction behavior still needs its own end-to-end review.

## Five-minute demonstration

### 0:00–0:40 — State the problem and trace the path

Say: “A peripheral that transfers data directly to memory needs limits on where it can read or write. My system places a hardware firewall on the DMA request path. Trusted firmware programs the policy and can change it while transfers are in progress.”

Show the architecture and trace DMA → firewall → shared SRAM. Point to the trusted CPU's separate control path. Explain that PicoRV32 is reused CPU IP executing compiled firmware, and that this demonstration runs in an RTL simulator.

### 0:40–1:20 — Access starts denied

Show `DEFAULT DENY` in the log. Firmware first stores `0xaaaa0000` at shared address `0x10000000`, then asks DMA to overwrite it with `0x1234`. It expects zero successes and one error response, and checks that the original memory value remains.

Say: “This checks both the error response and the absence of a memory change. A denial message alone would not establish that the write was blocked.”

### 1:20–2:10 — Grant a bounded region

Show `GRANT AND CONTAINMENT`. Firmware grants reads and writes for `0x10000000` through `0x100000ff`. It writes 16 words using DMA, checks each value through the CPU, then performs a DMA readback and checks its checksum. DMA write data is `0x12340000 + word_index`.

Next point to the protected sentinel at `0x10000200`: a DMA read and write there must fail, and its value must remain `0xfeedcafe`. That address lies outside the granted 256-byte region.

Say: “The grant enables a specific region. It does not make the entire memory accessible.”

### 2:10–3:20 — Revoke while a transfer is in progress

Show `REVOKED`, then the update event window. Firmware starts a 1,024-word DMA write job, begins programming a deny policy, and waits for the commit sequence to advance. The dedicated testbench checks that an operation actually overlaps update begin and that acknowledgment never occurs with old work still outstanding.

Say: “An operation already issued under the old policy may finish. Acknowledgment is the point at which the update has completed and old work has drained. The design does not undo an accepted write.”

Be precise about the workload: 1,024 words span 4 KiB, but the old permission covers only 256 bytes, or 64 words. Therefore, the total error count includes out-of-region accesses as well as accesses denied after revocation. Do not describe every error as a revocation event. The independent policy/transaction scoreboard and update acknowledgment checks establish the relevant behavior.

### 3:20–4:15 — Compare the update methods

Explain stop-and-program: pause acceptance, finish outstanding work, program the single policy bank, and resume. Explain shadow-bank mode: program the inactive bank while old-policy traffic continues, then pause acceptance, drain, and switch banks.

Show the controlled comparison in `results.md`. For the previously recorded gap-0, no-forced-stall, no-CPU-contention case, the derived active-job acceptance gaps were 976 cycles for stop and 5 for shadow. Describe these as recorded results for that workload; use regenerated values if source or settings change.

Say: “The comparison asks how much request service is interrupted while preserving the same update-completion rule. The shadow method costs extra policy storage and control logic.”

Do not substitute the dashboard's raw maximum-gap card for the derived active-job metric. Do not call shorter error-response intervals useful-data throughput or a general application speedup.

### 4:15–5:00 — Regrant and state the evidence boundary

Show `REGRANT` and the final `PASS soc`. Firmware restores access, writes four words, checks the final word, exercises another revoke/regrant sequence, and checks a read.

Say: “The system can deny, grant, revoke during activity, and grant again. I tested the integrated CPU and firmware in simulation and used formal checks for specified component properties. This is not a formal proof of the complete SoC.”

If asked about `NO BYPASS`, explain the additional broad-policy probes: DMA still cannot reach CPU private memory or the configuration registers because its path ends at shared SRAM, whose full-address decoder rejects those targets.

## Explain the design in your own words

| Likely question | Answer to understand and defend | Where to look |
|---|---|---|
| What did you contribute? | The firewall/control integration, firmware workload, DMA-like engine, shared-memory path, verification and controlled update comparison. PicoRV32 and the tools are attributed reused components. | `architecture.md`, `evidence-matrix.md` |
| Why put the firewall on the DMA path? | Every DMA request to shared SRAM must pass its permission check. The guarantee depends on that being the only path. | `rtl/soc/soc_top.sv` |
| Why trust the CPU? | Firmware is the policy authority and can directly configure permissions and access memory. A compromised authority is outside this threat model. | `architecture.md` |
| Why not let DMA configure its own rules? | Then the restricted requester could grant itself access. Configuration belongs to the trusted CPU path. | `soc_top.sv`, `registers.md` |
| What exactly is checked? | The winning region, direction permission, alignment and containment of the full four-byte word. Unmatched access is denied. | `rtl/firewall_update.sv`, `docs/spec.md` |
| Why check the final byte? | A valid starting address alone does not guarantee the whole word lies inside the region. Widened arithmetic also avoids address-wrap mistakes. | `student-guide.md` |
| Why wait before acknowledging commit? | Otherwise software could see “update complete” while an old-policy operation could still take effect or its response remained outstanding. | `firewall_update.sv`, `tb/soc/tb_soc.sv` |
| What if memory never responds? | Commit may never finish. Safety does not imply progress without an eventual response. | `docs/verification.md` |
| What does the shadow bank buy? | Programming can overlap old-policy traffic. Final drain/switch still requires a safe boundary and may wait for memory. | `results.md` |
| What is formally verified? | Named firewall properties and local wrapper/SRAM properties under their harness assumptions. Wrapper proofs abstract the backend; SRAM proofs use reduced memory. CPU/firmware integration is simulated. | `evidence-matrix.md` |
| How do you know the checks catch errors? | Deliberately faulty variants exercise failures such as premature completion, address aliasing and wrong response ownership. Rejecting them supports those checks, but does not establish exhaustive bug detection. | `evidence-matrix.md` |
| Is it faster or smaller in silicon? | We measured simulation behavior and mapped cell area for the firewall/control block. There is no measured chip frequency, power or whole-SoC area result. | `implementation.md` |

## Rehearse without the script

1. Draw CPU, DMA, firewall and SRAM from memory. Add the CPU control path and identify the trust boundary.
2. Explain one allowed write and one denied write, including the response and whether memory changes.
3. Explain why writing a commit command and observing completion are different events.
4. Explain both update modes using one outstanding request that stalls.
5. Explain why the revocation workload's total error count cannot isolate revocation effects.
6. Name one property established by a component proof, one checked by integrated simulation, and one outside the project scope.

If you can do these with the architecture and one real trace open, you have the core explanation needed for a project interview. Use the code and evidence to resolve uncertainties rather than memorizing stronger claims.
