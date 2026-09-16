const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {test} = require('node:test');
const script = fs.readFileSync(path.join(__dirname, '../web/yandex-map.js'), 'utf8');

function harness({legacyHtml = false} = {}) {
  const handlers = {}, sent = [], scripts = [], timers = new Map();
  let nextTimer = 0, maps = 0;
  const element = () => ({hidden: true, textContent: '', addEventListener(name, fn) {this[name] = fn;}, remove() {}});
  const nodes = {status: element(), locate: element(), retry: element()};
  if (legacyHtml) delete nodes.retry;
  nodes.tools = {appendChild(node) {nodes[node.id] = node;}};
  const parent = {postMessage(data, origin) {assert.equal(origin, 'https://edinburo.ru'); sent.push(JSON.parse(data));}};
  const window = {addEventListener(name, fn) {handlers[name] = fn;}};
  const context = {document: {getElementById: id => nodes[id], createElement: element,
    head: {appendChild: element => scripts.push(element)}}, window, parent,
    location: {origin: 'https://edinburo.ru'}, navigator: {},
    setTimeout(fn, ms) {const id = ++nextTimer; timers.set(id, {fn, ms}); return id;},
    setInterval(fn, ms) {const id = ++nextTimer; timers.set(id, {fn, ms}); return id;},
    clearTimeout: id => timers.delete(id), clearInterval: id => timers.delete(id)};
  vm.runInNewContext(script, context);
  return {nodes, scripts, sent, timers,
    tick(ms) {for (const timer of [...timers.values()]) if (timer.ms === ms) timer.fn();},
    message(data, source = parent, origin = 'https://edinburo.ru') {
      handlers.message({source, origin, data: JSON.stringify(data)});
    },
    sdk() {
      const ymaps = {ready: fn => fn(), Map: function() {maps++; return {
        events: {add() {}}, geoObjects: {removeAll() {}, add() {}}, setCenter() {}, getZoom: () => 12,
      };}};
      window.ymaps = context.ymaps = ymaps;
    },
    get maps() {return maps;},
  };
}
const config = {source: 'bureau-flutter', key: 'test-key', editable: false, markers: []};

test('a cached pre-upgrade document still connects and can retry a failed map load', () => {
  const h = harness({legacyHtml: true});
  assert.equal(h.sent[0].type, 'ready');
  assert.equal(h.nodes.retry.textContent, 'Повторить загрузку карты');
  h.message(config);
  h.scripts[0].onerror();
  assert.equal(h.nodes.retry.hidden, false);
  h.nodes.retry.click();
  h.sdk(); h.scripts[1].onload();
  assert.equal(h.maps, 1);
  assert.match(h.nodes.status.textContent, /Показаны приблизительные/);
});

test('lost initial ready is retried; missing configuration ends with an actionable error', () => {
  const h = harness();
  assert.equal(h.sent.length, 1);
  h.tick(500); assert.equal(h.sent.length, 2);
  h.tick(12000);
  assert.match(h.nodes.status.textContent, /Не удалось подключить/);
  assert.equal(h.nodes.retry.hidden, false);
  h.nodes.retry.click();
  h.message(config);
  assert.equal(h.scripts.length, 1);
  assert.equal([...h.timers.values()].filter(t => [500, 12000].includes(t.ms)).length, 0);
  h.sdk(); h.scripts[0].onload();
  assert.equal(h.maps, 1);
  assert.match(h.nodes.status.textContent, /Показаны приблизительные/);
});

test('only the same-origin parent may configure the map; failed SDK loads can retry', () => {
  const h = harness();
  h.message(config, {});
  h.message(config, undefined, 'https://untrusted.example');
  assert.equal(h.scripts.length, 0);
  h.message(config);
  h.scripts[0].onerror();
  assert.equal(h.nodes.retry.hidden, false);
  h.nodes.retry.click();
  assert.equal(h.scripts.length, 2);
  h.sdk();
  h.scripts[0].onload(); // Late response from failed attempt cannot create a map.
  assert.equal(h.maps, 0);
  h.scripts[1].onload();
  assert.equal(h.maps, 1);
});

test('a stalled provider times out and its late callback cannot overwrite retry', () => {
  const h = harness(); h.message(config); h.tick(15000);
  assert.equal(h.nodes.retry.hidden, false);
  assert.match(h.nodes.status.textContent, /Карта не загрузилась/);
  h.sdk(); h.scripts[0].onload(); assert.equal(h.maps, 0);
  h.nodes.retry.click(); assert.equal(h.maps, 1);
});
