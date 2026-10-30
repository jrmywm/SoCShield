"""Reproducible firmware build and actual RTL CPU simulation (Windows)."""
import argparse, hashlib, json, os, pathlib, subprocess, struct, shutil
from generate_map import generate
ROOT=pathlib.Path(__file__).resolve().parents[1]
SUITE=ROOT/'tools/oss-cad-suite'
ENV=os.environ.copy(); ENV['PATH']=str(SUITE/'bin')+os.pathsep+str(SUITE/'lib')+os.pathsep+ENV.get('PATH','')
def run(args,cwd,log):
    p=subprocess.run([str(a) for a in args],cwd=cwd,env=ENV,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
    pathlib.Path(log).write_text(p.stdout,encoding='utf-8')
    if p.returncode: raise RuntimeError(f'{args[0]} exit {p.returncode}: {p.stdout[-2500:]}')
    return p.stdout
def main():
    generate()
    p=argparse.ArgumentParser();p.add_argument('--boot',action='store_true');p.add_argument('--mode',type=int,default=0,choices=[0,1]);p.add_argument('--gap',type=int,default=0);p.add_argument('--contention',type=int,default=0);p.add_argument('--stall',type=int,default=0);p.add_argument('--seed',type=int,default=1);p.add_argument('--random-stalls',action='store_true');p.add_argument('--allow-idle-update',action='store_true');p.add_argument('--trace',action='store_true');p.add_argument('--out',default='build/soc')
    a=p.parse_args();out=(ROOT/a.out).resolve();out.mkdir(parents=True,exist_ok=True)
    compilers=sorted((ROOT/'tools').glob('xpack-riscv-none-elf-gcc-*/bin/riscv-none-elf-gcc.exe'))
    if not compilers:raise RuntimeError('Compiler missing; see tools/compiler-release.json and docs/integration/reproduce.md')
    gcc=compilers[-1];prefix=str(gcc)[:-7]
    flags=['-march=rv32i','-mabi=ilp32','-Os','-ffreestanding','-fno-builtin','-fno-pic','-msmall-data-limit=0','-mno-relax','-nostdlib','-nostartfiles','-Wl,--build-id=none',f'-Wl,-T,{ROOT/"firmware/link.ld"}',f'-Wl,-Map,{out/"firmware.map"}',f'-DGAP={a.gap}',f'-DCONTENTION={a.contention}',f'-DBOOT_ONLY={int(a.boot)}']
    run([gcc,*flags,ROOT/'firmware/start.S',ROOT/'firmware/main.c','-o',out/'firmware.elf'],ROOT,out/'compiler.log')
    run([prefix+'objcopy.exe','-O','binary',out/'firmware.elf',out/'firmware.bin'],ROOT,out/'objcopy.log')
    dis=run([prefix+'objdump.exe','-d',out/'firmware.elf'],ROOT,out/'firmware.dis')
    image=(out/'firmware.bin').read_bytes();image=image.ljust(65536,b'\0')
    if len(image)!=65536:raise RuntimeError('firmware too large')
    (out/'firmware.hex').write_text('\n'.join(f'{w[0]:08x}' for w in struct.iter_unpack('<I',image))+'\n')
    sources=['third_party/picorv32/picorv32.v','rtl/firewall_update.sv','rtl/peripherals/firewall_mmio.sv','rtl/peripherals/dma_engine.sv','rtl/soc/shared_sram.sv','rtl/soc/soc_top.sv','tb/soc/tb_soc.sv']
    # The top's default image path is intentionally relative to each run directory.
    top=(ROOT/'rtl/soc/soc_top.sv').read_text().replace('"build/soc/firmware.hex"','"firmware.hex"')
    (out/'soc_top.sv').write_text(top)
    compile_sources=[out/'soc_top.sv' if x=='rtl/soc/soc_top.sv' else ROOT/x for x in sources]
    key=hashlib.sha256((str(a.mode)+(ROOT/'rtl/soc/soc_map.vh').read_text()+''.join(x.read_text() for x in compile_sources)).encode()).hexdigest()
    cache=ROOT/'build/soc/cache';cache.mkdir(parents=True,exist_ok=True)
    binary=cache/(key+'.vvp')
    if not binary.exists():
        run([SUITE/'bin/iverilog.exe','-g2012','-I',ROOT/'rtl/soc','-s','tb_soc',f'-Ptb_soc.MODE={a.mode}','-o',binary,*compile_sources],ROOT,out/'compile.log')
    else:(out/'compile.log').write_text('Reused content-addressed Icarus binary '+key+'\n')
    shutil.copyfile(binary,out/'sim.vvp')
    log=run([SUITE/'bin/vvp.exe',out/'sim.vvp',f'+STALL={a.stall}',f'+SEED={a.seed}',f'+RANDOM={int(a.random_stalls)}',f'+REQUIRE_OVERLAP={int(not a.allow_idle_update)}',*(['+TRACE']if a.trace else[])],out,out/'simulation.log')
    if 'PASS soc' not in log:raise RuntimeError('missing PASS')
    hashes={str(x.relative_to(ROOT)):hashlib.sha256(x.read_bytes()).hexdigest() for x in [*[ROOT/x for x in sources],ROOT/'rtl/soc/soc_map.vh',ROOT/'config/soc_map.json',ROOT/'scripts/soc.py',*sorted((ROOT/'firmware').glob('*'))]if x.is_file()}
    (out/'manifest.json').write_text(json.dumps({'arguments':vars(a),'sources':hashes,'elf_sha256':hashlib.sha256((out/'firmware.elf').read_bytes()).hexdigest(),'compiler':run([gcc,'--version'],ROOT,out/'compiler-version.log').splitlines()[0]},indent=2))
    print(log)
if __name__=='__main__':main()
