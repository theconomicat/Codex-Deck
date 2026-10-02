const test = require('node:test');
const assert = require('node:assert/strict');
const { DeckController, consumePairingToken, isPresetSelected, POLL_INTERVAL } = require('../../Sources/CodexUsageWeb/Resources/deck.js');

const preset = { slot: 1, model: 'gpt-6-astra', effort: 'ultra', title: 'GPT-6 Astra · Ultra' };
function snapshot(overrides = {}) {
  return { csrf: 'test-csrf', connected: true, target: { id: 'chat-a', title: 'Fixture chat' }, presets: [preset], selection: { model: 'gpt-6.1-sol', effort: 'high' }, ...overrides };
}
function response(payload, status = 200) { return { ok: status >= 200 && status < 300, status, json: async () => payload }; }
function deferred() { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; }
function harness(responses) {
  const requests = [], timers = new Map();
  let nextID = 0, visible = true;
  const controller = new DeckController({
    fetch: async (path, options) => {
      requests.push({ path, options });
      const next = responses.shift();
      if (next instanceof Error) throw next;
      if (next === undefined) throw new Error('Unexpected fixture request: ' + path);
      return next;
    },
    onChange() {}, isVisible: () => visible,
    schedule: (fn, delay) => { const id = ++nextID; timers.set(id, { fn, delay }); return id; },
    cancel: id => timers.delete(id)
  });
  return { controller, requests, timers, setVisible: value => { visible = value; } };
}

test('default timer adapters do not pass the controller as a browser timer receiver', () => {
  const originalSetTimeout = globalThis.setTimeout;
  const originalClearTimeout = globalThis.clearTimeout;
  const calls = [];
  try {
    globalThis.setTimeout = function (callback, delay) {
      'use strict';
      assert.equal(this, undefined);
      calls.push(['schedule', delay]);
      return 42;
    };
    globalThis.clearTimeout = function (timer) {
      'use strict';
      assert.equal(this, undefined);
      calls.push(['cancel', timer]);
    };
    const controller = new DeckController({ fetch() {}, onChange() {} });
    controller.scheduleRefresh();
    controller.clearTimer();
    assert.deepEqual(calls, [['schedule', POLL_INTERVAL], ['cancel', 42]]);
  } finally {
    globalThis.setTimeout = originalSetTimeout;
    globalThis.clearTimeout = originalClearTimeout;
  }
});

test('selected key matches display labels and slugs without confusing model versions or effort', () => {
  assert.equal(isPresetSelected({ model: 'gpt-6-astra', effort: 'ultra' }, { model: 'GPT-6 Astra', effort: 'ultra' }), true);
  assert.equal(isPresetSelected({ model: '6.1 Sol', effort: 'high' }, { model: 'GPT-6.1 Sol', effort: 'high' }), true);
  assert.equal(isPresetSelected({ model: 'gPt_6.1-SOL', effort: 'high' }, { model: 'GPT-6.1 Sol', effort: 'high' }), true);
  assert.equal(isPresetSelected({ model: 'gpt-6-sol', effort: 'high' }, { model: 'GPT-6.1 Sol', effort: 'high' }), false);
  assert.equal(isPresetSelected({ model: 'gpt-6.1-sol', effort: 'xhigh' }, { model: 'GPT-6.1 Sol', effort: 'high' }), false);
  assert.equal(isPresetSelected({ model: 'gpt-6-astra-preview', effort: 'ultra' }, { model: 'GPT-6 Astra', effort: 'ultra' }), false);
  assert.equal(isPresetSelected(undefined, { model: 'GPT-6 Astra', effort: 'ultra' }), false);
});

test('pairing token leaves the address bar before it is used and is not in the route', () => {
  const calls = [];
  assert.equal(consumePairingToken({ hash: '#pair=secret-token', pathname: '/', search: '' }, { replaceState: (...args) => calls.push(args) }), 'secret-token');
  assert.deepEqual(calls, [[null, '', '/']]);
});

test('pairing is followed by authenticated state and uses only same-origin credentials', async () => {
  const h = harness([response({ csrf: 'paired' }), response(snapshot())]);
  await h.controller.start('pair-token');
  assert.deepEqual(h.requests.map(r => r.path), ['/api/pair', '/api/state']);
  assert.equal(h.requests[0].options.body, '{"token":"pair-token"}');
  assert.equal(h.requests[0].options.credentials, 'same-origin');
  assert.equal(h.controller.state.phase, 'ready');
  assert.equal(h.controller.csrf, 'test-csrf');
  assert.equal([...h.timers.values()][0].delay, POLL_INTERVAL);
  assert.ok(POLL_INTERVAL >= 5000);
});

test('401 removes sensitive state and stops polling', async () => {
  const h = harness([response(snapshot()), response({ error: 'Expired session' }, 401)]);
  await h.controller.start();
  await h.controller.refresh();
  assert.equal(h.controller.state.phase, 'pairing');
  assert.equal(h.controller.state.snapshot, null);
  assert.equal(h.controller.csrf, null);
  assert.equal(h.timers.size, 0);
});

test('polls do not overlap and hidden pages stop scheduling and requesting', async () => {
  const gate = deferred();
  const h = harness([gate.promise]);
  const first = h.controller.refresh();
  const second = h.controller.refresh();
  assert.equal(first, second);
  assert.equal(h.requests.length, 1);
  h.setVisible(false);
  h.controller.visibilityChanged();
  gate.resolve(response(snapshot()));
  await first;
  assert.equal(h.timers.size, 0);
  await h.controller.refresh();
  assert.equal(h.requests.length, 1);
});

test('preset sends exact displayed model, effort, target and CSRF; success waits for confirmation', async () => {
  const gate = deferred();
  const h = harness([response(snapshot()), gate.promise, response(snapshot({ selection: { model: preset.model, effort: preset.effort } }))]);
  await h.controller.start();
  const applying = h.controller.applyPreset(preset);
  assert.equal(h.controller.state.applyingSlot, 1);
  assert.equal(h.controller.state.feedback, null);
  assert.equal(h.controller.state.snapshot.selection.model, 'gpt-6.1-sol');
  assert.equal(await h.controller.applyPreset(preset), false);
  assert.equal(h.requests.length, 2);
  assert.deepEqual(JSON.parse(h.requests[1].options.body), { slot: 1, model: 'gpt-6-astra', effort: 'ultra', targetID: 'chat-a' });
  assert.equal(h.requests[1].options.headers['X-Deck-CSRF'], 'test-csrf');
  gate.resolve(response({ ok: true, message: 'Preset applied.' }));
  assert.equal(await applying, true);
  assert.equal(h.controller.state.feedback.tone, 'success');
  assert.equal(h.controller.state.snapshot.selection.effort, 'ultra');
});

test('target change during a poll blocks the previously displayed key', async () => {
  const gate = deferred();
  const h = harness([response(snapshot()), gate.promise, response(snapshot({ target: { id: 'chat-b', title: 'Second chat' } }))]);
  await h.controller.start();
  const poll = h.controller.refresh();
  const applying = h.controller.applyPreset(preset);
  gate.resolve(response(snapshot({ target: { id: 'chat-b', title: 'Second chat' } })));
  await poll;
  assert.equal(await applying, false);
  assert.equal(h.requests.filter(r => r.path === '/api/preset').length, 0);
  assert.equal(h.controller.state.feedback.tone, 'error');
});

test('409 never auto-retries a write and refreshes the target', async () => {
  const h = harness([response(snapshot()), response({ error: 'The active chat changed.' }, 409), response(snapshot())]);
  await h.controller.start();
  assert.equal(await h.controller.applyPreset(preset), false);
  assert.deepEqual(h.requests.map(r => r.path), ['/api/state', '/api/preset', '/api/state']);
  assert.equal(h.controller.state.feedback.tone, 'error');
});

test('another device busy state disables preset actions', async () => {
  const h = harness([response(snapshot({ busy: true }))]);
  await h.controller.start();
  assert.equal(h.controller.canApply(), false);
  assert.equal(await h.controller.applyPreset(preset), false);
  assert.equal(h.requests.length, 1);
});

test('offline cannot apply presets and a successful poll clears connection error', async () => {
  const h = harness([response(snapshot()), new Error('Network disconnected'), response(snapshot())]);
  await h.controller.start();
  await h.controller.refresh();
  assert.equal(h.controller.state.phase, 'offline');
  assert.equal(h.controller.canApply(), false);
  await h.controller.refresh();
  assert.equal(h.controller.state.phase, 'ready');
  assert.equal(h.controller.state.feedback, null);
});

test('logout waits for the current poll, clears state and stops polling', async () => {
  const gate = deferred();
  const h = harness([response(snapshot()), gate.promise, response({ ok: true })]);
  await h.controller.start();
  const poll = h.controller.refresh();
  const logout = h.controller.logout();
  assert.equal(h.requests.length, 2);
  gate.resolve(response(snapshot()));
  await poll;
  await logout;
  assert.equal(h.requests[2].path, '/api/logout');
  assert.equal(h.controller.state.phase, 'pairing');
  assert.equal(h.controller.state.snapshot, null);
  assert.equal(h.timers.size, 0);
});
