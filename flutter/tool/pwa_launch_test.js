const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '..');
const script = fs.readFileSync(path.join(root, 'web/pwa-launch.js'), 'utf8');
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'web/site.webmanifest'), 'utf8'));
assert.equal(manifest.start_url, '/app/');
assert.equal(manifest.id, '/'); // Preserve the identity of existing installations.
assert.equal(manifest.scope, '/');

function launch({ ios = false, standalone = false, pathname = '/', search = '', hash = '', media = true } = {}) {
  const redirects = [];
  vm.runInNewContext(script, {
    navigator: { standalone: ios },
    window: {
      ...(media ? { matchMedia: () => ({ matches: standalone }) } : {}),
      location: { pathname, search, hash, replace: (url) => redirects.push(url) },
    },
  });
  return redirects;
}
assert.deepEqual(launch({ ios: true }), ['/app/']);
assert.deepEqual(launch({ standalone: true }), ['/app/']);
assert.deepEqual(launch({ ios: true, media: false }), ['/app/']);
assert.deepEqual(launch({ ios: true, search: '?action=found', hash: '#saved' }), ['/app/?action=found#saved']);
assert.deepEqual(launch(), []);
assert.deepEqual(launch({ media: false }), []);
assert.deepEqual(launch({ ios: true, pathname: '/app/' }), []);
assert.deepEqual(launch({ ios: true, pathname: '/items/example/' }), []);
console.log('PWA launch checks passed.');
