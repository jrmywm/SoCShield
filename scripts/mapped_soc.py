"""Map firewall_mmio configurations onto pinned SKY130 HD cells; no timing claim."""
from pathlib import Path
import fnmatch, gzip, hashlib, json, os, re, shutil, subprocess, sys
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build'/'soc'/'mapped'
SOURCE=ROOT/'tools'/'library'/'sky130hd_tt.lib.gz'
SHA='210e56be3a3a0907b5241a34d277f664cf4b4d91dcb49a27ff813df4406a5889'
DONT=('sky130_fd_sc_hd__probe_p_8','sky130_fd_sc_hd__probec_p_8','sky130_fd_sc_hd__lpflow_*')

def q(p): return '"'+str(p.resolve()).replace('\\','/')+'"'
def main():
    if not SOURCE.exists() or hashlib.sha256(SOURCE.read_bytes()).hexdigest()!=SHA:
        raise RuntimeError('pinned Liberty missing or SHA-256 mismatch')
    yosys=shutil.which('yosys')
    if not yosys: raise RuntimeError('yosys not on PATH')
    OUT.mkdir(parents=True,exist_ok=True)
    text=gzip.decompress(SOURCE.read_bytes()).decode('utf-8')
    cell_re=re.compile(r'^[ \t]*cell \("([^"]+)"\) \{',re.M)
    cells={}; out=[]; pos=0
    while True:
        m=cell_re.search(text,pos)
        if not m: out.append(text[pos:]); break
        out.append(text[pos:m.start()]); depth=0; j=m.end()-1
        while j<len(text):
            depth+=(text[j]=='{')-(text[j]=='}')
            if not depth: break
            j+=1
        if j==len(text): raise RuntimeError('bad Liberty cell block')
        block=text[m.start():j+1]; name=m.group(1)
        if not any(fnmatch.fnmatch(name,p) for p in DONT):
            area=re.search(r'\barea\s*:\s*([0-9.]+)\s*;',block)
            if not area: raise RuntimeError('missing area '+name)
            cells[name]={'area':float(area.group(1)), 'sequential':bool(re.search(r'\b(?:ff|latch)\s*\(',block))}
            out.append(block)
        pos=j+1
    lib=OUT/'sky130hd_tt_pruned.lib'; lib.write_text(''.join(out),encoding='utf-8')
    abc=OUT/'abc.constr'; abc.write_text('set_driving_cell sky130_fd_sc_hd__buf_2\nset_load 10.0\n')
    rtl=[ROOT/'rtl'/'firewall_update.sv',ROOT/'rtl'/'peripherals'/'firewall_mmio.sv']
    version=subprocess.check_output([yosys,'-V'],text=True).strip()
    results=[]
    for shadow in (0,1):
        tag=f'shadow{shadow}'; net=OUT/(tag+'.v'); js=OUT/(tag+'.json'); stat=OUT/(tag+'.stat.txt'); log=OUT/(tag+'.yosys.log')
        script=(f'read_liberty -lib -overwrite {q(lib)}; read_verilog -sv '+ ' '.join(map(q,rtl))+'; '
                f'chparam -set SHADOW {shadow} firewall_mmio; synth -top firewall_mmio -flatten; '
                f'dfflibmap -liberty {q(lib)}; abc -liberty {q(lib)} -D 5000 -constr {q(abc)}; '
                f'opt_clean -purge; check -assert; tee -o {q(stat)} stat -liberty {q(lib)}; '
                f'write_json {q(js)}; write_verilog -noattr -noexpr {q(net)}')
        proc=subprocess.run([yosys,'-Q','-q','-l',str(log),'-p',script],cwd=ROOT,text=True,capture_output=True)
        if proc.returncode: raise RuntimeError(f'{tag} failed; see {log}: {proc.stderr[-1000:]}')
        design=json.loads(js.read_text()); inst=design['modules']['firewall_mmio']['cells']
        unknown=sorted({c['type'] for c in inst.values()}-cells.keys())
        if unknown: raise RuntimeError(f'{tag}: unmapped/unknown cells: {unknown}')
        area=sum(cells[c['type']]['area'] for c in inst.values())
        seq=sum(cells[c['type']]['sequential'] for c in inst.values())
        if not seq: raise RuntimeError('no mapped flops')
        results.append({'shadow':shadow,'cells':len(inst),'sequential_cells':seq,'area_um2':round(area,4),'timing':'unavailable'})
    report={'tool':version,'source_liberty_sha256':SHA,'pruned_liberty_sha256':hashlib.sha256(lib.read_bytes()).hexdigest(),
            'source_sha256':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in rtl},
            'top':'firewall_mmio','abc_target_ps':5000,'abc_load_fF':10.0,'results':results,
            'timing_note':'No independent static timing analysis performed; mapping target is not a timing result.'}
    (OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
if __name__=='__main__':
    try: main()
    except Exception as e: print('FAIL: '+str(e),file=sys.stderr); sys.exit(1)
