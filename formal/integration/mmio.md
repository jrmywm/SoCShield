# MMIO wrapper safety checks

Run from `formal/integration`, with the OSS CAD Suite `bin` and `lib` on PATH:

```
sby -f -d ../../build/soc/formal-mmio/prove0 mmio.sby prove0
sby -f -d ../../build/soc/formal-mmio/prove1 mmio.sby prove1
sby -f -d ../../build/soc/formal-mmio/bmc0 mmio.sby bmc0
sby -f -d ../../build/soc/formal-mmio/bmc1 mmio.sby bmc1
```

`prove0` and `prove1` use ABC PDR for unbounded safety; `bmc0` and `bmc1` use Z3 for 20-cycle bounded safety. Both values of SHADOW are checked. The only assumption is reset asserted on the initial sampled edge. Bus inputs can change arbitrarily each cycle, including back-to-back transfers, invalid formats, and subsequent resets. There are no fairness or progress assumptions.

The firewall is replaced by an intentionally over-approximated interface whose ready, acknowledgment and busy signals are unconstrained, even allowing acknowledgments unrelated to commits. Assertions cover exact sequence-counter updates, payload stability under backpressure and snapshotting, session and command ordering, commit completeness, rejection while occupied, and sticky-error/W1C updates. They prove wrapper-local safety only, not backend acknowledgment correctness, DMA policy enforcement, or liveness. Tests in `tb/soc/tb_mmio.sv` instantiate the real firewall.
