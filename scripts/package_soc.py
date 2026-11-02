"""Package source and compact evidence, excluding installed executables/caches."""
import hashlib,json,pathlib,zipfile
from report_soc import main as validate_and_report
ROOT=pathlib.Path(__file__).resolve().parents[1]
def main():
    validate_and_report()
    files=set()
    for folder in('rtl','firmware','tb','formal','scripts','docs','config','third_party'):
        files.update(p for p in(ROOT/folder).rglob('*')if p.is_file() and '__pycache__'not in p.parts and p.suffix not in('.pyc','.vvp','.sqlite'))
    files.update([ROOT/'README.md',ROOT/'.gitignore',ROOT/'.gitattributes',ROOT/'tools/compiler-provenance.json',ROOT/'tools/compiler-release.json',ROOT/'tools/library/PROVENANCE.txt'])
    if (ROOT/'tools/viz-provenance.json').exists():files.add(ROOT/'tools/viz-provenance.json')
    files.update(p for p in(ROOT/'evidence').rglob('*')if p.is_file())
    # Full installed tools are fetched by documented pinned URLs, not redistributed.
    allowed={'.json','.csv','.log','.md','.txt','.elf','.bin','.hex','.dis','.map','.v','.sv','.svh','.sby','.ys','.vcd'}
    for p in(ROOT/'build').rglob('*'):
        if not p.is_file():continue
        rel=p.relative_to(ROOT/'build');parts=rel.parts
        if parts[0]in('baseline-preserved','mutations'):continue
        if parts[0]=='soc' and len(parts)>1 and (parts[1].startswith('cache') or parts[1]in('root-formal','formal-shared','formal-mmio')):continue
        if p.name=='status' or p.name=='logfile.txt':files.add(p);continue
        if p.suffix not in allowed:continue
        if p.suffix=='.vcd' and not ('demo-stop'in parts or 'demo-shadow'in parts):continue
        # Avoid generated formal model copies; their original src snapshots and logs suffice.
        if 'model'in parts or 'engine_0'in parts:continue
        files.add(p)
    manifest={str(p.relative_to(ROOT)).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest()for p in sorted(files)}
    dest=ROOT/'deliverables/SoCShield-RISC-V-source-and-evidence.zip';dest.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(dest,'w',zipfile.ZIP_DEFLATED)as z:
        for p in sorted(files):z.write(p,p.relative_to(ROOT))
        z.writestr('PACKAGE-MANIFEST.json',json.dumps(manifest,indent=2))
    with zipfile.ZipFile(dest)as z:
        if z.testzip()is not None:raise RuntimeError('ZIP integrity failure')
        for name,digest in manifest.items():
            if hashlib.sha256(z.read(name)).hexdigest()!=digest:raise RuntimeError('ZIP hash failure '+name)
    digest=hashlib.sha256(dest.read_bytes()).hexdigest()
    dest.with_suffix('.zip.sha256').write_text(digest+'  '+dest.name+'\n')
    print(f'Validated {len(files)} files, {dest.stat().st_size} bytes, SHA-256 {digest}')
if __name__=='__main__':main()
