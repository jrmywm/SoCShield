"""Bounded paired workload matrix plus five adversarial seeds per mode."""
import argparse,csv,hashlib,json,pathlib,subprocess,sys
ROOT=pathlib.Path(__file__).resolve().parents[1]
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--resume',action='store_true');opts=parser.parse_args()
    rows=[]
    cases=[(m,g,c,s,1,False)for m in(0,1)for g in(0,4,16)for c in(0,1)for s in(0,64)]
    cases += [(m,0,1,0,seed,True)for m in(0,1)for seed in(1,7,23,101,65537)]
    for mode,gap,contention,stall,seed,random in cases:
        name=f'm{mode}_g{gap}_c{contention}_s{stall}_seed{seed}_r{int(random)}'
        out='build/soc/evaluation/'+name
        args=[sys.executable,str(ROOT/'scripts/soc.py'),'--mode',str(mode),'--gap',str(gap),'--contention',str(contention),'--stall',str(stall),'--seed',str(seed),'--allow-idle-update','--out',out]
        if random:args+=['--random-stalls']
        valid=False
        if opts.resume and (ROOT/out/'manifest.json').exists():
            m=json.loads((ROOT/out/'manifest.json').read_text())
            valid=all((ROOT/k).exists() and hashlib.sha256((ROOT/k).read_bytes()).hexdigest()==v for k,v in m['sources'].items())
            valid=valid and (ROOT/out/'metrics.csv').exists() and 'PASS soc' in (ROOT/out/'simulation.log').read_text()
        if not valid:
            p=subprocess.run(args,cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
            if p.returncode:raise RuntimeError(name+'\n'+p.stdout)
        r=next(csv.DictReader((ROOT/out/'metrics.csv').open()))
        r.update(gap=gap,contention=contention,stall=stall,random=int(random),run=name)
        rows.append(r);print(('REUSED current-source PASS 'if valid else 'PASS ')+name,flush=True)
    for mode in(0,1):
        if not any(int(r['overlap'])>0 for r in rows if int(r['mode'])==mode):raise RuntimeError('no outstanding-update scenario for mode '+str(mode))
    dest=ROOT/'build/soc/evaluation/summary.csv'
    with dest.open('w',newline='')as f:w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
    print(f'{len(rows)} runs passed; {dest}')
if __name__=='__main__':main()
