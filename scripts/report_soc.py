"""Generate comparison figures/report exclusively from checked run artifacts."""
import csv,hashlib,html,json,pathlib
ROOT=pathlib.Path(__file__).resolve().parents[1]
DOC=ROOT/'docs/integration';FIG=DOC/'figures'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def current_manifest(path):
    m=json.loads(path.read_text())
    for name,digest in m['sources'].items():
        if sha(ROOT/name)!=digest:raise RuntimeError('Stale evidence: '+str(path)+' '+name)
    return m
def main():
    FIG.mkdir(parents=True,exist_ok=True)
    rows=list(csv.DictReader((ROOT/'build/soc/evaluation/summary.csv').open()))
    if len(rows)!=34:raise RuntimeError('expected 24 paired deterministic and 10 seeded runs')
    for row in rows:
        current_manifest(ROOT/'build/soc/evaluation'/row['run']/'manifest.json')
        events=list(csv.DictReader((ROOT/'build/soc/evaluation'/row['run']/'events.csv').open()))
        # Isolate this explicitly programmed job using its captured address/data
        # signature. Inter-job firmware idle time is not service interruption.
        job=[e for e in events if e['event']=='request' and 0xabc00000<=int(e['data'],16)<0xabc00400]
        if len(job)!=1024:raise RuntimeError('missing measured DMA job')
        for i,e in enumerate(job):
            if int(e['data'],16)!=0xabc00000+i or int(e['address'],16)!=0x10000000+4*i:raise RuntimeError('wrong job identity')
        begin,ack=int(row['begin_cycle']),int(row['ack_cycle'])
        pairs=[int(b['cycle'])-int(a['cycle'])for a,b in zip(job,job[1:])if int(b['cycle'])>=begin and int(a['cycle'])<=ack]
        row['active_job_gap']=max(pairs,default=0)
        row['job_issued_before_ack']=int(int(job[-1]['cycle'])<ack)
    with (ROOT/'build/soc/evaluation/analysis.csv').open('w',newline='')as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
    demo=[]
    for tag in('demo-stop','demo-shadow'):
        current_manifest(ROOT/'build/soc'/tag/'manifest.json')
        d=next(csv.DictReader((ROOT/'build/soc'/tag/'metrics.csv').open()))
        if int(d['overlap'])<1:raise RuntimeError('demo lacks required overlap')
        demo.append(d)
    current_manifest(ROOT/'build/soc/boot/manifest.json')
    verification=json.loads((ROOT/'build/soc/verification/report.json').read_text())
    for name,digest in verification['source_sha256'].items():
        if sha(ROOT/name)!=digest:raise RuntimeError('stale verification '+name)
    if not all(c['passed']for c in verification['checks']):raise RuntimeError('failed verification')
    mapped=json.loads((ROOT/'build/soc/mapped/report.json').read_text())
    for name,digest in mapped['source_sha256'].items():
        if sha(ROOT/name)!=digest:raise RuntimeError('stale mapping '+name)
    def select(mode,gap):return next(r for r in rows if int(r['mode'])==mode and int(r['gap'])==gap and r['contention']=='0'and r['stall']=='0'and r['random']=='0')
    # Static, exportable SVG chart with no package dependencies.
    svg=['<svg xmlns="http://www.w3.org/2000/svg" width="960" height="450" viewBox="0 0 960 450">','<rect width="960" height="450" fill="#fff"/>','<g font-family="Arial" fill="#172338">','<text x="35" y="35" font-size="21">Observed request gaps within the active DMA job</text>','<text x="35" y="60" font-size="12">Cycles; no forced stall/contention. At the slowest setting the shadow job finishes before commit.</text>']
    maximum=max(int(select(m,g)['active_job_gap'])for m in(0,1)for g in(0,4,16));scale=260/maximum
    for i,g in enumerate((0,4,16)):
        x=115+270*i
        for m,color in((0,'#245a81'),(1,'#c57531')):
            val=int(select(m,g)['active_job_gap']);height=val*scale;xx=x+m*78
            svg.append(f'<rect x="{xx}" y="{350-height:.2f}" width="64" height="{height:.2f}" fill="{color}"/><text x="{xx+32}" y="{338-height:.2f}" text-anchor="middle" font-size="14">{val}</text>')
        svg.append(f'<text x="{x+70}" y="375" text-anchor="middle" font-size="14">{g} programming-loop iterations</text>')
    svg+=['<text x="110" y="420" fill="#245a81">Blue: stop and program</text><text x="410" y="420" fill="#c57531">Orange: shadow bank</text></g></svg>']
    (FIG/'interruption.svg').write_text('\n'.join(svg),encoding='utf-8')
    # Measured event timeline around the dedicated revocation demonstration.
    svg=['<svg xmlns="http://www.w3.org/2000/svg" width="1100" height="300"><rect width="1100" height="300" fill="white"/><g font-family="Arial" fill="#172338"><text x="25" y="30" font-size="20">Simulation events around revocation</text>']
    for mode,tag in enumerate(('demo-stop','demo-shadow')):
        d=demo[mode];begin=int(d['begin_cycle']);ack=int(d['ack_cycle']);lo=begin-40;hi=ack+40
        y=95+mode*110
        svg.append(f'<text x="25" y="{y-25}" font-size="14">{tag}: begin {begin}, ack {ack}, outstanding at begin {d["overlap"]}</text><line x1="25" y1="{y}" x2="1060" y2="{y}" stroke="#aaa"/>')
        events=list(csv.DictReader((ROOT/'build/soc'/tag/'events.csv').open()))
        for event in events:
            c=int(event['cycle']);kind=event['event']
            if lo<=c<=hi and kind in('request','response','ack'):
                x=25+1035*(c-lo)/(hi-lo);color={'request':'#245a81','response':'#45864c','ack':'#c12c41'}[kind]
                svg.append(f'<line x1="{x:.2f}" y1="{y-12}" x2="{x:.2f}" y2="{y+12}" stroke="{color}"/>')
        svg.append(f'<text x="25" y="{y+30}" font-size="12">Window: cycles {lo}–{hi}; rows have independent horizontal scales</text>')
    svg.append('<text x="25" y="285" font-size="12">Blue: accepted DMA request; green: consumed response; red: actual firewall commit acknowledgment.</text></g></svg>')
    (FIG/'revocation-events.svg').write_text('\n'.join(svg),encoding='utf-8')
    area=mapped['results'];overhead=(area[1]['area_um2']/area[0]['area_um2']-1)*100
    out=['# SoCShield integrated RISC-V system: measured results','',
         'The pinned PicoRV32 RTL executes compiled RV32I/ILP32 C firmware. Both SoCShield update variants pass the dedicated security demonstration. The integrated workload matrix contains 24 deterministic cases and 10 seeded endpoint-stall cases; all pass the independent transaction/memory scoreboard. These are simulation results, accompanied by component safety proofs and library-mapped area. No physical FPGA deployment, whole-system formal proof, or static timing result is claimed.','',
         '## Demonstration','',
         '| Mode | Total simulated cycles | DMA accepted/completed | Error responses | Requests reaching SRAM endpoint | Outstanding operation at update begin |','|---|---:|---:|---:|---:|---:|']
    for d in demo:out.append(f'| {"Shadow"if d["mode"]=="1"else"Stop"} | {d["cycles"]} | {d["accepted"]}/{d["completed"]} | {d["errors"]} | {d["forwarded"]} | {d["overlap"]} |')
    out+=['','Firmware checks default denial, allowed writes/readback and checksum, denied reads/writes, private/control/high-address alias probes under a deliberately broad policy, revoke during a transfer, and repeated regrant. The bench independently reconstructs policy and memory effects, checks DMA payload/response correctness and CPU SRAM exact-once routing, and compares final SRAM contents. Three broad-policy probes reach the SRAM endpoint and are rejected by its full-address decode; they never reach private RAM or configuration registers. The DMA engine continues through errors, so counts include intentional denied operations.','',
          '## Controlled update comparison','',
          '| Programming-loop iterations per entry | Stop: begin→ack cycles | Shadow: begin→ack cycles | Stop: active-job acceptance gap | Shadow: active-job acceptance gap |','|---:|---:|---:|---:|---:|']
    for gap in(0,4,16):
        a,b=select(0,gap),select(1,gap)
        out.append(f'| {gap} | {int(a["ack_cycle"])-int(a["begin_cycle"])} | {int(b["ack_cycle"])-int(b["begin_cycle"])} | {a["active_job_gap"]} | {b["active_job_gap"]} |')
    out+=['','![DMA interruption](figures/interruption.svg)','',
          'Programming gaps are C loop iterations, not hardware cycles. Begin→ack uses actual firewall handshakes. The active-job gap is independently reconstructed from successive requests in the designated 1,024-word DMA job whose intervals intersect begin→ack; it excludes gaps between separate jobs. At the slowest programming setting, the shadow job can finish before commit, so that row does not measure a switching interruption under sustained demand. Raw `max_acceptance_gap` may include subsequent firmware idle time and is not interchangeable with this metric. `analysis.csv` records both and flags jobs whose requests all precede acknowledgment. `inhibited_cycles` separately counts the controller inhibit condition during the firmware phase. The firmware phase includes MMIO and polling overhead. CPU instruction timing, arbitration, and update phase affect results. The broad sweep records overlap rather than requiring every update to land on a busy cycle; the dedicated demonstrations require overlap.','',
          'Acceptance metrics count both allowed and denied operations. Faster error completion is not useful-data throughput, and total demonstration runtime includes firmware overhead and different numbers of old-policy successful operations. These measurements must not be presented as a general application speedup.','',
          'The deterministic matrix varies mode (2), programming gap (3), one-shot endpoint stall (0 or 64 cycles), and a firmware shared-memory-access workload (off/on). The latter performs checked reads while DMA is active and between entry updates; it is not a constant-rate background master. `contested_cycles` records actual simultaneous CPU/DMA demand; a configured contention workload does not imply every cycle contends. Five seeds per mode drive additional pseudo-random endpoint stalls. Complete measurements and per-run manifests are in `build/soc/evaluation/summary.csv` and its run directories.','',
          '![Revocation events](figures/revocation-events.svg)','',
          '## Verification','',
          f'The integration verification entry point passed {len(verification["checks"])} checks: three component simulations, six formal tasks, and three negative controls. The original standalone static/update suites and independent VCD audit were also rerun successfully.','',
          '- The original firewall safety proofs retain their documented assumptions and scope.',
          '- Wrapper proofs use an unconstrained backend abstraction. They establish wrapper-local command, payload, counter, and error behavior, not the backend security guarantee.',
          '- The SRAM/arbiter proof uses four words and LATENCY=2 with initial reset; directed simulation tests the production addressing logic and reset retention.',
          '- The CPU executing firmware is tested in end-to-end simulation; it is reused IP and is not re-proved here.',
          '- Early completion reporting, address aliasing, and wrong response ownership are each rejected by semantic test failures. Parse errors or timeouts are not counted as fault detection.','',
          '## Library-mapped implementation cost','',
          '| Configuration | Mapped cells | Sequential cells | Cell-area sum (µm²) |','|---|---:|---:|---:|']
    for r in area:out.append(f'| {"Shadow"if r["shadow"]else"Stop"} | {r["cells"]} | {r["sequential_cells"]} | {r["area_um2"]:.4f} |')
    out+=['',f'The shadow wrapper/firewall has {overhead:.1f}% higher library-cell area in this mapping. This measures `firewall_mmio` plus `firewall_update`, not the CPU, RAM, DMA engine, or whole chip. It is distinct from the earlier bare-firewall generic-cell comparison.','',
          'Mapping uses the pinned SKY130 HD typical 25 °C / 1.8 V Liberty and identical Yosys/ABC settings. Cell area excludes routing, clock tree, floorplan, and other physical overhead. The ABC 5 ns target guides mapping; it is not measured delay or proof of timing closure. See [implementation evidence](implementation.md) for provenance and tool limitations.','',
          '## Calculations and interpretation','',
          '- Transaction latency = response-consumption cycle − request-acceptance cycle.',
          '- Update latency = actual acknowledgment cycle − accepted begin/commit cycle; the start event must be named.',
          '- Cell-area overhead = (shadow area − stop area) / stop area × 100%.',
          '- DMA throughput in bytes/cycle = successful transferred words × 4 / measured workload cycles. Converting to bytes/second requires an explicitly assumed or validated clock frequency.',
          '- Lower interruption is useful only while preserving the same denial and old-operation completion contract. A permanent stall may prevent commit indefinitely.','',
          '## Reproduction and limitations','',
          'See [reproduction instructions](reproduce.md), [architecture](architecture.md), [requirements/evidence matrix](evidence-matrix.md), and [student walkthrough](student-guide.md). The required output is a simulated RTL system. No board, power result, physical timing, secure boot, independent reset, cache coherence, standard-bus compliance, or claim of a new security mechanism is included.','']
    (DOC/'results.md').write_text('\n'.join(out),encoding='utf-8')
    print('Report generated after current-source evidence validation')
if __name__=='__main__':main()
