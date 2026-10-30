# Verification scope and evidence

The safety properties describe a single clock and the specified sole memory path. They do not establish security of a surrounding SoC, authenticity of the trusted controller, absence of other access paths, or physical attack resistance.

## Static enforcement

`tb/tb_firewall.sv` is a small directed test. `tb/tb_system.sv` adds 64 KiB of persistent memory plus the final word of the 32-bit address space, an independent policy scoreboard, deterministic pseudorandom backpressure, and 512 generated requests with seed `51c0ffee`. A special allowed address returns a downstream error. Interface reset flushes pending traffic but preserves already-written storage.

The system run exercises default deny; aligned endpoints; all three misalignment offsets; overlapping and disabled rules; inverted ranges; a region ending partway through a word; the highest aligned address; allowed write/readback; denied writes; memory errors; changing unaccepted inputs; delayed memory acceptance and response; response backpressure; simultaneous request/configuration; exact-once forwarding and response accounting; and reset in SEND, WAIT_RSP, and RESP phases. Continuous checks compare every presented downstream payload with its accepted upstream payload and every response with the expected data/error.

The recorded system run accepted 539 operations: 536 completed, three were deliberately reset-abandoned, 209 reached memory, and 329 were denied. Two of the abandoned operations had already reached memory. Counts are trace-specific and are not a coverage percentage.

## Formal safety

`formal/firewall_properties.svh` and `formal/update_properties.svh` are included only under `FORMAL`; they are absent from synthesized hardware. They maintain transaction and policy reference state. Policy matching traverses entries in the opposite direction from the RTL while preserving lowest-index priority. Internal storage/state equalities strengthen induction and are themselves asserted, not assumed.

The update proof decomposes bank steering and storage: it asserts that selected/programming banks agree with an acknowledgment-based abstract active bank, then uses the proven steering signals to share duplicate configuration-update logic. This reduces solver cost without assuming bank correctness. State/refinement invariants are checked in the base case and induction step along with externally visible properties.

The only formal environment assumption is that reset is asserted in the initial modeled cycle. Request addresses, write data, directions, unaccepted input changes, trusted configuration values, later resets, memory readiness, memory response valid/data/error, and upstream response readiness are otherwise unconstrained. There are no fairness assumptions. This deliberately admits malformed memory response signals as well; the proven data property is capture/sanitization of the response at the expected handshake. Correct memory response provenance remains an integration obligation.

Assertions cover:

- One upstream slot, no unsolicited or repeated downstream forwarding, and matching accepted payloads.
- Default deny, priority, alignment, full-word containment, zero denial data, and downstream-error sanitization.
- Held request and response fields during stalls, and reset suppression of handshakes.
- Four-entry completion before commit, session rules, commit/config/request priority, inactive-bank programming, and bank changes only with acknowledgment.
- No acknowledgment while an old-policy operation is outstanding and no request acceptance across the drain barrier.

The `prove` jobs use temporal induction. A successful base case plus induction is an **unbounded proof of these safety assertions**, under the stated model. The depth setting is an induction search parameter, not a claim that only that many future cycles are safe. Separate `bmc` jobs are finite checks: 12 cycles for the static core and 24 for each update architecture. They are not substituted for proof.

Cover jobs seek bounded examples, not proofs of liveness: 24 cycles for the static core and 32 for update variants. They exercise denied completion, both allowed directions, backpressure followed by completion, reset, stalled drain followed by commit, a write followed by later denial, and concurrent shadow configuration/request acceptance. No unconditional completion theorem is claimed.

## Deliberate faults

`verify.ps1` generates four private faulty static variants: unconditional allow, live instead of captured downstream address, highest-index priority, and missing word-end containment. Both system simulation and bounded formal assertions must detect each fault. `compare.ps1` removes the drain-empty condition for each update architecture; its simulation and bounded checks must reject that early-drain implementation.

Negative checks require assertion failures; a parse error, missing executable, or tool `ERROR` is not counted as a detected security fault. Source copies, logs, status files, and counterexample traces remain under `build/`. Original RTL is never overwritten by a mutant.

## Evidence and limits

`build/results.json` records static check outcomes and SHA-256 source hashes. `build/comparison/manifest.json`, `metrics.csv`, `area.json`, and `mutations.json` record the comparison. Formal work directories contain copied sources, solver logs, status, and cover/counterexample traces. `scripts/render_evidence.py` separately parses real VCD files, reconstructs policy and handshake state, checks transaction accounting, forwarding payloads, responses, stalls and commit drain, and emits `build/waveform_audit.json` plus SVG excerpts with source hashes.

Simulations use one generated seed and a small deterministic update workload, not an exhaustive workload sweep. Formal abstraction does not model a CPU, interconnect, ECC, caches, or physical memory device. Generic synthesis has no cell library, clock constraint, placement, routing, power activity model, or mapped timing. These remain limitations of the study.
