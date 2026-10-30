"""Create a small source-and-evidence archive, excluding local tool binaries."""
from pathlib import Path
import hashlib
import json
import zipfile

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/"deliverables"
OUT.mkdir(exist_ok=True)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check_sources():
    # Require the distributed RTL and properties to match actual proof inputs.
    for work,rtl,properties in [
        ("build/prove","firewall.sv","firewall_properties.svh"),
        ("build/comparison/stop_prove","firewall_update.sv","update_properties.svh"),
        ("build/comparison/shadow_prove","firewall_update.sv","update_properties.svh"),
    ]:
        status=(ROOT/work/"status").read_text().split()[0]
        assert status=="PASS", (work,status)
        for source,kind in [(rtl,"rtl"),(properties,"formal")]:
            assert sha(ROOT/kind/source)==sha(ROOT/work/"src"/source), f"Proof/source mismatch: {source}"


def wanted_build(path):
    relative=path.relative_to(ROOT/"build")
    if "model" in relative.parts:
        return False  # Large regenerated solver models are reproducible.
    if relative.parts[0] in {"logs","mutations","prove","bmc","cover","comparison"}:
        return path.suffix.lower() in {".log",".txt",".json",".csv",".vcd",".sv",".svh",".sby",".v",".smtc",".yw",".xml"} or path.name in {"status","PASS","FAIL"}
    return relative.as_posix() in {"results.json","waveform_audit.json","system.vcd","firewall.vcd"}


if __name__=="__main__":
    check_sources()
    files=[ROOT/"README.md",ROOT/".gitignore"]
    for folder in ("rtl","tb","formal","scripts","docs"):
        files.extend(p for p in (ROOT/folder).rglob("*") if p.is_file() and "__pycache__" not in p.parts)
    files.extend(p for p in (ROOT/"build").rglob("*") if p.is_file() and wanted_build(p))
    files=sorted(set(files))
    archive=OUT/"SoCShield-source-and-evidence.zip"
    manifest="\n".join(f"{sha(p)}  SoCShield/{p.relative_to(ROOT).as_posix()}" for p in files)+"\n"
    with zipfile.ZipFile(archive,"w",zipfile.ZIP_DEFLATED) as z:
        for p in files:
            z.write(p,"SoCShield/"+p.relative_to(ROOT).as_posix())
        z.writestr("MANIFEST.sha256",manifest)
    # Re-read every entry to ensure the delivered archive matches the manifest.
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
        for line in manifest.splitlines():
            digest,name=line.split("  ",1)
            assert hashlib.sha256(z.read(name)).hexdigest()==digest
    (OUT/"SoCShield-source-and-evidence.zip.sha256").write_text(f"{sha(archive)}  {archive.name}\n")
    print(json.dumps({"archive":str(archive),"bytes":archive.stat().st_size,"files":len(files),"sha256":sha(archive),"proof_source_match":True,"archive_integrity":"PASS"},indent=2))
