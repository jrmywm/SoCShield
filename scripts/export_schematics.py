"""Export unedited Yosys DOT circuits; let Graphviz compute SVG/PNG layout."""
import argparse,hashlib,json,pathlib,shutil,subprocess,sys,tarfile
from soc import ROOT,SUITE,ENV,run

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def quote(path):return '"'+str(path).replace('\\','/')+'"'
def prefix_arg(path):return path.relative_to(ROOT).as_posix()
def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--setup',action='store_true',help='download/verify the pinned Graphviz WASM package')
    args=parser.parse_args()
    node=shutil.which('node')
    if not node:raise RuntimeError('Node.js is required for the Graphviz WASM renderer')
    provenance=json.loads((ROOT/'tools/viz-provenance.json').read_text())
    graph_root=ROOT/'tools/viz'
    if args.setup:
        archive=ROOT/'tools/viz-3.25.0.tgz'
        if not archive.exists():
            js="const fs=require('node:fs');fetch(process.argv[1]).then(r=>{if(!r.ok)throw Error(r.status);return r.arrayBuffer()}).then(b=>fs.writeFileSync(process.argv[2],Buffer.from(b))).catch(e=>{console.error(e);process.exit(1)})"
            subprocess.run([node,'-e',js,provenance['url'],str(archive)],check=True)
        if sha(archive)!=provenance['sha256']:raise RuntimeError('Graphviz package checksum mismatch')
        if not(graph_root/'package/dist/viz.cjs').exists():
            with tarfile.open(archive)as t:t.extractall(graph_root,filter='data')
    bundled=pathlib.Path.home()/'.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@viz-js/viz'
    candidates=[graph_root/'package/dist/viz.cjs',bundled/'dist/viz.cjs']
    module=next((p for p in candidates if p.exists()),None)
    if module is None:raise RuntimeError('Graphviz WASM package missing; rerun with --setup')
    pkg=json.loads((module.parent.parent/'package.json').read_text())
    if pkg['version']!='3.25.0':raise RuntimeError('Unexpected Viz.js package version')
    if sha(module)!=provenance['renderer_sha256']:raise RuntimeError('Graphviz renderer hash mismatch')
    out=ROOT/'build/soc/schematics';out.mkdir(parents=True,exist_ok=True)
    figures=ROOT/'docs/integration/figures/schematics';figures.mkdir(parents=True,exist_ok=True)
    def yosys_flow(tag,commands):
        script=out/(tag+'.ys');script.write_text(commands+'\n',encoding='utf-8')
        run([SUITE/'bin/yosys.exe','-Q','-T','-s',script],ROOT,out/(tag+'.log'))
    views=[]
    for mode in(0,1):
        tag='shadow'if mode else'stop'
        full=out/(tag+'_full');access=out/(tag+'_access');handshake=out/(tag+'_handshakes');wrapper=out/(tag+'_wrapper');valids=out/(tag+'_valids')
        flow=(f'read_verilog -sv rtl/firewall_update.sv; chparam -set SHADOW {mode} firewall_update; '
              'hierarchy -check -top firewall_update; proc; opt -full; check -assert; '
              f'show -format dot -viewer none -enum -width -prefix {prefix_arg(full)} firewall_update; '
              'select -set access_cone firewall_update/w:allowed %cie*; '
              f'show -format dot -viewer none -enum -width -prefix {prefix_arg(access)} @access_cone; '
              'select -clear; '
              'select -set handshake_cone firewall_update/w:req_ready firewall_update/w:mem_req_valid firewall_update/w:rsp_valid %u %u %cie*; '
              f'show -format dot -viewer none -enum -width -prefix {prefix_arg(handshake)} @handshake_cone; '
              'select -clear; select -set valid_cone firewall_update/w:mem_req_valid firewall_update/w:rsp_valid %u %cie*; '
              f'show -format dot -viewer none -enum -width -prefix {prefix_arg(valids)} @valid_cone; '
              f'select -clear; write_json {quote(out/(tag+"_rtlil.json"))}')
        yosys_flow(tag,flow)
        yosys_flow(tag+'_wrapper',
            f'read_verilog -sv rtl/firewall_update.sv rtl/peripherals/firewall_mmio.sv; '
            f'chparam -set SHADOW {mode} firewall_mmio; hierarchy -check -top firewall_mmio; proc; opt -full; check -assert; '
            f'show -format dot -viewer none -enum -width -prefix {prefix_arg(wrapper)} firewall_mmio/c:firewall')
        for prefix,scope in[(full,'whole firewall_update module'),(access,'combinational input cone of allowed'),
                             (handshake,'union of combinational input cones for req_ready, mem_req_valid, rsp_valid'),
                             (wrapper,'firewall instance and its connected boundary wires within firewall_mmio'),
                             (valids,'combinational input cones for mem_req_valid and rsp_valid; state register is a cut point')]:
            source=prefix.with_suffix('.dot')
            if not source.exists()or 'digraph'not in source.read_text():raise RuntimeError('Missing Yosys graph '+str(source))
            dest=figures/(prefix.name+'.svg')
            run([node,ROOT/'scripts/render_schematic.cjs',module,source,dest],ROOT,out/(prefix.name+'-graphviz.log'))
            if '<svg'not in dest.read_text(encoding='utf-8'):raise RuntimeError('Invalid SVG')
            # Preserve Yosys's exact graph: no hand-added components or connections.
            shutil.copyfile(source,figures/source.name)
            views.append({'name':prefix.name,'scope':scope,'mode':mode,'dot_sha256':sha(source),'svg_sha256':sha(dest)})
        print('PASS exported '+tag+' full / access / handshakes / instance boundary')
    sources=[ROOT/'rtl/firewall_update.sv',ROOT/'rtl/peripherals/firewall_mmio.sv',pathlib.Path(__file__).resolve(),ROOT/'scripts/render_schematic.cjs']
    yosys_version=run([SUITE/'bin/yosys.exe','-V'],ROOT,out/'yosys-version.log').strip()
    graphviz_version=json.loads((out/'stop_full-graphviz.log').read_text())
    report={'kind':'tool-generated optimized RTL schematics, not technology-mapped physical layouts',
            'yosys':yosys_version,'graphviz':graphviz_version,'sources':{str(p.relative_to(ROOT)):sha(p)for p in sources},
            'views':views,'graphviz_archive':provenance,
            'interpretation':'Diamond nodes at cone boundaries are cut-point signals, not newly added hardware. Auto-numbered cells map to source locations in Yosys logs. Schematics do not constitute a correctness proof.'}
    (figures/'manifest.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    shutil.copyfile(figures/'manifest.json',out/'manifest.json')
    print('Saved unedited DOT, SVG, exact .ys recipes, logs, RTLIL JSON, and source/output hashes.')
if __name__=='__main__':main()
