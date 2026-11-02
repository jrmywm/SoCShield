// Graphviz's own layout engine, compiled to WebAssembly by Viz.js.
const fs = require('node:fs');
const path = require('node:path');
const [modulePath, input, output] = process.argv.slice(2);
const api = require(modulePath);
const pkg = JSON.parse(fs.readFileSync(path.join(path.dirname(modulePath), '..', 'package.json'), 'utf8'));
api.instance().then(viz => {
  fs.writeFileSync(output, viz.renderString(fs.readFileSync(input, 'utf8'), {format: 'svg', engine: 'dot'}), 'utf8');
  process.stdout.write(JSON.stringify({package: '@viz-js/viz', version: pkg.version, graphviz: api.graphvizVersion}) + '\n');
}).catch(error => { process.stderr.write(String(error)); process.exit(1); });
