"""Fetch pinned CPU, compiler, and mapped-area library; verify before use."""
import hashlib,json,pathlib,urllib.request,zipfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
REV='ef203c2b0a3fb793280f5114941416c425c5b461'
GCC='https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v15.2.0-1/xpack-riscv-none-elf-gcc-15.2.0-1-win32-x64.zip'
GCC_SHA='85ef714dacd273b1dadf4af4892774520ac01915bfa6da816a56e7e41591e09e'
def fetch(url,path,sha):
    path.parent.mkdir(parents=True,exist_ok=True)
    if not path.exists():
        print('Downloading '+url,flush=True)
        with urllib.request.urlopen(url)as src,path.open('wb')as dst:
            while block:=src.read(1024*1024):dst.write(block)
    if hashlib.sha256(path.read_bytes()).hexdigest().lower()!=sha.lower():raise RuntimeError('SHA-256 mismatch: '+str(path))
def main():
    provenance=json.loads((ROOT/'third_party/picorv32/provenance.json').read_text(encoding='utf-8-sig'))
    for entry in provenance['files']:
        name=entry['Path'].replace('\\','/').split('/')[-1]
        fetch(f'https://raw.githubusercontent.com/YosysHQ/picorv32/{REV}/{name}',ROOT/'third_party/picorv32'/name,entry['Hash'])
    archive=ROOT/'tools/riscv-gcc.zip';fetch(GCC,archive,GCC_SHA)
    expected=ROOT/'tools/xpack-riscv-none-elf-gcc-15.2.0-1/libexec/gcc/riscv-none-elf/15.2.0/cc1.exe'
    if not expected.exists():
        with zipfile.ZipFile(archive)as z:z.extractall(ROOT/'tools')
    fetch('https://raw.githubusercontent.com/parallaxsw/OpenSTA/b99a8e528de098e4e06dbb6a0bb5423d6ada2f51/examples/sky130hd_tt.lib.gz',ROOT/'tools/library/sky130hd_tt.lib.gz','210e56be3a3a0907b5241a34d277f664cf4b4d91dcb49a27ff813df4406a5889')
    print('Pinned integration dependencies verified. Install OSS CAD Suite as documented in README.')
if __name__=='__main__':main()
