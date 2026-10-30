"""Component simulation, formal contracts, and semantically rejected mutants."""
import hashlib,json,pathlib,subprocess,sys
from soc import ROOT,SUITE,ENV,run
OUT=ROOT/'build/soc/verification'
def main():
    OUT.mkdir(parents=True,exist_ok=True);checks=[]
    cases={'mmio':['rtl/firewall_update.sv','rtl/peripherals/firewall_mmio.sv','tb/soc/tb_mmio.sv'],
           'dma':['rtl/peripherals/dma_engine.sv','tb/soc/tb_dma.sv'],
           'shared':['rtl/soc/shared_sram.sv','tb/soc/tb_shared.sv']}
    tops={'mmio':'tb_mmio','dma':'tb_dma','shared':'tb_shared'}
    for tag,sources in cases.items():
        exe=OUT/(tag+'.vvp')
        run([SUITE/'bin/iverilog.exe','-g2012','-s',tops[tag],'-o',exe,*[ROOT/x for x in sources]],ROOT,OUT/(tag+'-compile.log'))
        result=run([SUITE/'bin/vvp.exe',exe],OUT,OUT/(tag+'.log'))
        if 'PASS'not in result:raise RuntimeError('no PASS '+tag)
        checks.append({'name':tag,'passed':True})
    for task,sby in [('prove','shared'),('cover','shared'),('prove0','mmio'),('prove1','mmio'),('bmc0','mmio'),('bmc1','mmio')]:
        dest=OUT/(sby+'-'+task)
        run([SUITE/'bin/sby.exe','-f','-d',dest,sby+'.sby',task],ROOT/'formal/integration',OUT/(sby+'-'+task+'.log'))
        if not(dest/'status').read_text().startswith('PASS'):raise RuntimeError('bad formal status')
        checks.append({'name':sby+'-'+task,'passed':True})
    mutants=[('mmio','early_completion','mailbox==COMMIT_CMD && commit_ack','mailbox==COMMIT_CMD && commit_sent'),
             ('shared','address_alias',"({1'b0,address} >= BASE) && ({1'b0,address} < LIMIT)","1'b1"),
             ('shared','response_owner','owner <= grant_d;','owner <= !grant_d;')]
    for tag,name,old,new in mutants:
        source=ROOT/cases[tag][-2];text=source.read_text()
        if old not in text:raise RuntimeError('mutation anchor missing '+name)
        private=OUT/(name+'.sv');private.write_text(text.replace(old,new))
        sources=[private if ROOT/x==source else ROOT/x for x in cases[tag]]
        exe=OUT/(name+'.vvp')
        run([SUITE/'bin/iverilog.exe','-g2012','-s',tops[tag],'-o',exe,*sources],ROOT,OUT/(name+'-compile.log'))
        p=subprocess.run([str(SUITE/'bin/vvp.exe'),str(exe)],cwd=OUT,env=ENV,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
        (OUT/(name+'.log')).write_text(p.stdout)
        if p.returncode==0 or 'FATAL:'not in p.stdout or 'watchdog'in p.stdout.lower() or 'timeout'in p.stdout.lower():raise RuntimeError('mutant not semantically caught '+name+' '+p.stdout)
        checks.append({'name':name,'passed':True,'expected_failure':True})
    hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()for folder in['rtl','tb/soc','formal/integration']for p in(ROOT/folder).rglob('*')if p.is_file() and p.suffix in('.sv','.v','.svh','.vh','.sby')}
    (OUT/'report.json').write_text(json.dumps({'checks':checks,'source_sha256':hashes},indent=2))
    print('PASS integration verification: '+str(len(checks))+' checks')
if __name__=='__main__':main()
