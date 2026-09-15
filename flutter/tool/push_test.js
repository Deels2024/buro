const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {test} = require('node:test');

const clientScript = fs.readFileSync(path.join(__dirname, '../web/push-client.js'), 'utf8');
const workerScript = fs.readFileSync(path.join(__dirname, '../web/bureau-push-sw.js'), 'utf8');

test('permission is requested from the gesture, subscription has a separate scope, opt-out removes it', async () => {
  const calls = [], values = new Map();
  const sub = {toJSON: () => ({endpoint: 'https://web.push.apple.com/example'}),
    unsubscribe: async () => {calls.push('unsubscribe'); return true;}};
  const reg = {active: {}, pushManager: {getSubscription: async () => null,
    subscribe: async options => {assert.equal(options.userVisibleOnly, true); return sub;}}};
  const context = {window: {isSecureContext: true, PushManager: {}, Notification: {}},
    navigator: {serviceWorker: {
      register: async (url, options) => {calls.push('register'); assert.equal(url, '/app/bureau-push-sw.js');
        assert.equal(options.scope, '/app/push/'); return reg;},
      getRegistration: async () => ({pushManager: {getSubscription: async () => sub}})
    }},
    Notification: {requestPermission: () => {calls.push('permission'); return Promise.resolve('granted');}},
    localStorage: {getItem: key => values.get(key), setItem: (key, value) => values.set(key, value), removeItem: key => values.delete(key)},
    atob, Uint8Array, setTimeout, clearTimeout};
  vm.runInNewContext(clientScript, context);
  const bridge = context.window.bureauPush;
  assert.equal(bridge.supported, true);
  assert.deepEqual(calls, []); // No permission prompt on load.
  const pending = bridge.subscribe('AQID');
  assert.deepEqual(calls, ['permission']);
  assert.equal(JSON.parse(await pending).endpoint, 'https://web.push.apple.com/example');
  bridge.saveDevice('device-id');
  assert.equal(await bridge.unsubscribe(), 'device-id');
  assert.equal(values.size, 0);
  assert.deepEqual(calls, ['permission', 'register', 'unsubscribe']);
});

test('push click stays on our app and malformed pushes still produce a visible notification', async () => {
  const handlers = {}, notices = [], opened = [];
  vm.runInNewContext(workerScript, {URL, self: {
    addEventListener: (name, handler) => {handlers[name] = handler;},
    registration: {showNotification: async (title, options) => notices.push({title, options})},
    location: {origin: 'https://edinburo.ru'},
    clients: {matchAll: async () => [], openWindow: async url => opened.push(url)},
  }});
  let pending;
  handlers.push({data: {json: () => ({body: 'Есть ответ', tag: 'same-id', url: 'https://evil.example/'})},
    waitUntil: task => {pending = task;}});
  await pending;
  assert.equal(notices[0].options.data.url, '/app/?action=notifications');
  assert.equal(notices[0].options.tag, 'same-id');
  handlers.push({data: {json: () => {throw new Error('invalid');}}, waitUntil: task => {pending = task;}});
  await pending;
  assert.equal(notices.length, 2);
  handlers.notificationclick({notification: {close() {}}, waitUntil: task => {pending = task;}});
  await pending;
  assert.deepEqual(opened, ['/app/?action=notifications']);
});
