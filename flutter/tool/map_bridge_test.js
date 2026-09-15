const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {execFileSync} = require('node:child_process');
const {test} = require('node:test');

test('compiled Dart accepts the same JS iframe window and rejects unrelated messages', () => {
  const folder = fs.mkdtempSync(path.join(os.tmpdir(), 'bureau-map-'));
  try {
    const compiled = path.join(folder, 'bridge.js');
    execFileSync('dart', ['compile', 'js', 'tool/map_bridge_probe.dart', '-o', compiled],
      {cwd: path.join(__dirname, '..'), stdio: 'pipe'});
    const script = path.join(folder, 'run.cjs');
    fs.writeFileSync(script, `
      const source = {};
      globalThis.self = globalThis;
      globalThis.mapTestFrame = {contentWindow: source};
      const good = {origin: 'https://edinburo.ru', source, data: JSON.stringify({source:'bureau-yandex', type:'ready'})};
      globalThis.mapTestEvents = [good, {...good, source:{}}, {...good, source:null},
        {...good, origin:'https://untrusted.example'}, {...good, data:'{'},
        {...good, data:{}}, {...good, data:JSON.stringify({source:'other'})}];
      require(${JSON.stringify(compiled)});
    `);
    const result = execFileSync(process.execPath, [script], {encoding: 'utf8'});
    assert.match(result, /real JS source identity and message validation passed/);
  } finally {
    fs.rmSync(folder, {recursive: true, force: true});
  }
});
