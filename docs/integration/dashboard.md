# Local simulation dashboard

The dashboard is a small, dependency-free web interface for running the existing integrated SoC simulation. It does not replace the testbench, create a different hardware model, or control a physical FPGA.

## Start it

From the project root in PowerShell:

```powershell
.\scripts\run_dashboard.ps1
```

This starts a server bound to `127.0.0.1` and opens `http://127.0.0.1:8765`. Keep the PowerShell window open while using it; press Ctrl+C there to stop the dashboard. The pinned OSS CAD Suite and xPack RISC-V compiler must be installed as for the command-line workflow.

## Choose a run

- **Stop & program / Shadow bank** select the existing `SHADOW=0` or `SHADOW=1` RTL mode.
- **Programming gap** is the firmware's loop-iteration setting, not a cycle count.
- **Memory stall** injects the testbench's deterministic downstream stall in cycles.
- **CPU shared-memory reads** enables the existing firmware contention workload.
- **Capture waveform** writes `soc.vcd` into that run folder. Clear it for a smaller, faster result folder.

Press **Run simulation**. The server invokes `scripts/soc.py` with an argument array and no shell, and saves every run in its own timestamped directory under `build/soc/frontend-runs/`. Only one simulation can run at a time. The compiled firmware executes on the pinned PicoRV32 RTL in Icarus Verilog.

## Read the display

The monitor reports simulation clock cycles, DMA accepted/completed requests, error responses, begin-to-acknowledgment latency, observed request gap, and whether an operation was outstanding when the update began. Error responses include intentional policy-denial tests; they are not all failures. Event markers come from the testbench's `events.csv`. The VCD link downloads the simulation waveform when capture was enabled. The simulation output preserves firmware messages and the final `PASS soc` line.

**Cycle playback** replays recorded request, response, and commit-ack events around the policy update. Play/pause, speed, and the scrubber change only the browser visualization; they do not rerun or alter the simulation. The cursor reports simulated cycles, and only events inside the selected update window are shown.

The request-gap card displays the run's raw `max_acceptance_gap` field. For controlled performance interpretation, use the derived active-job metric and caveats in [measured results](results.md); the raw gap may include periods outside the designated DMA job.

## Local service boundary

The server binds only to the loopback interface and accepts validated settings from that local page. It allows one run at a time, invokes only the repository's fixed simulation script, and stores output under `build/`. The page uses no remote scripts, fonts, analytics, or services. Do not expose the server through a tunnel or bind it to a public interface.
