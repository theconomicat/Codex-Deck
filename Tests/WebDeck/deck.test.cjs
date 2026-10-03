const test = require('node:test');
const assert = require('node:assert/strict');
const { DeckController, consumePairingToken, isPresetSelected, usagePercent, POLL_INTERVAL } = require('../../Sources/CodexUsageWeb/Resources/deck.js');

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


test('usage ring preserves zero and rejects unknown, invalid or expired readings', () => {
  assert.equal(usagePercent({ remainingPercent: 0 }), 0);
  assert.equal(usagePercent({ remainingPercent: 94.6 }), 94.6);
  assert.equal(usagePercent({ remainingPercent: 100 }), 100);
  for (const remainingPercent of [null, undefined, NaN, Infinity, -1, 101, "94"]) {
    assert.equal(usagePercent({ remainingPercent }), null);
  }
  assert.equal(usagePercent(undefined), null);
  assert.equal(usagePercent({ remainingPercent: 94, resetsAt: 10 }, 10000), null);
  assert.equal(usagePercent({ remainingPercent: 94, resetsAt: 11 }, 10000), 94);
});

const { validControl, pressFeedback } = require('../../Sources/CodexUsageWeb/Resources/deck.js');
const models = [{ id: 'gpt-6-astra', name: 'GPT-6 Astra', efforts: ['medium', 'high', 'xhigh', 'ultra'] }];
const approval = { id: 'approval:request-a', fingerprint: 'exact-request', kind: 'approval', title: 'Run command?', choices: [{ id: 'approve', label: 'Allow' }, { id: 'deny', label: 'Deny' }] };
const question = { id: 'question:request-b', fingerprint: 'exact-questions', kind: 'question', title: 'Choose a route', questions: [
  { id: 'route', prompt: 'Which route?', options: [{ id: 'Fast', label: 'Fast' }, { id: 'Careful', label: 'Careful' }], allowOther: true },
  { id: 'detail', prompt: 'Any details?', options: [], allowOther: true }
] };

test('model control accepts only a model and effort currently exposed by the host', () => {
  assert.equal(validControl({ type: 'model', model: 'gpt-6-astra', effort: 'ultra' }, { models }), true);
  assert.equal(validControl({ type: 'model', model: 'gpt-6-astra', effort: 'max' }, { models }), false);
  assert.equal(validControl({ type: 'model', model: 'gpt-unknown', effort: 'high' }, { models }), false);
});

test('model control sends only the selected setting and exact chat, without general commands', async () => {
  const h = harness([response(snapshot({ models })), response({ ok: true }), response(snapshot({ models }))]);
  await h.controller.start();
  assert.equal(await h.controller.control({ type: 'model', model: 'gpt-6-astra', effort: 'xhigh' }), true);
  assert.equal(h.requests[1].path, '/api/control');
  assert.deepEqual(JSON.parse(h.requests[1].options.body), { type: 'model', model: 'gpt-6-astra', effort: 'xhigh', targetID: 'chat-a' });
  assert.equal(h.requests[1].options.headers['X-Deck-CSRF'], 'test-csrf');
});

test('approval requires the current fingerprint and one exposed decision', () => {
  const base = { type: 'approval', id: approval.id, fingerprint: approval.fingerprint, decision: 'approve' };
  assert.equal(validControl(base, { pending: [approval] }), true);
  assert.equal(validControl({ ...base, decision: 'deny' }, { pending: [approval] }), true);
  assert.equal(validControl({ ...base, fingerprint: 'stale' }, { pending: [approval] }), false);
  assert.equal(validControl({ ...base, decision: 'always-allow' }, { pending: [approval] }), false);
  assert.equal(validControl(base, { pending: [] }), false);
});

test('an approval changed by an in-flight poll is never submitted', async () => {
  const gate = deferred();
  const h = harness([response(snapshot({ pending: [approval] })), gate.promise, response(snapshot({ pending: [] }))]);
  await h.controller.start();
  const poll = h.controller.refresh();
  const action = h.controller.control({ type: 'approval', id: approval.id, fingerprint: approval.fingerprint, decision: 'approve' });
  gate.resolve(response(snapshot({ pending: [{ ...approval, fingerprint: 'changed-command' }] })));
  await poll;
  assert.equal(await action, false);
  assert.equal(h.requests.some(request => request.path === '/api/control'), false);
  assert.equal(h.controller.state.feedback.tone, 'error');
});

test('pending control cannot cross a changed active target', async () => {
  const gate = deferred();
  const h = harness([response(snapshot({ pending: [approval] })), gate.promise, response(snapshot({ pending: [approval] }))]);
  await h.controller.start();
  const poll = h.controller.refresh();
  const action = h.controller.control({ type: 'approval', id: approval.id, fingerprint: approval.fingerprint, decision: 'deny' });
  gate.resolve(response(snapshot({ pending: [approval], target: { id: 'chat-b', title: 'Another chat' } })));
  await poll;
  assert.equal(await action, false);
  assert.equal(h.requests.some(request => request.path === '/api/control'), false);
});

test('a rejected control is refreshed but never replayed automatically', async () => {
  const h = harness([response(snapshot({ pending: [approval] })), response({ error: 'The request changed.' }, 409), response(snapshot({ pending: [] }))]);
  await h.controller.start();
  assert.equal(await h.controller.control({ type: 'approval', id: approval.id, fingerprint: approval.fingerprint, decision: 'approve' }), false);
  assert.deepEqual(h.requests.map(request => request.path), ['/api/state', '/api/control', '/api/state']);
});

test('question answers must match every waiting question and cannot act as a general chat send', () => {
  const base = { type: 'question', id: question.id, fingerprint: question.fingerprint, answers: [{ id: 'route', optionID: 'Fast' }, { id: 'detail', text: 'Keep the existing files.' }] };
  assert.equal(validControl(base, { pending: [question] }), true);
  assert.equal(validControl(base, { pending: [] }), false);
  assert.equal(validControl({ ...base, answers: base.answers.slice(0, 1) }, { pending: [question] }), false);
  assert.equal(validControl({ ...base, answers: [base.answers[0], base.answers[0]] }, { pending: [question] }), false);
  assert.equal(validControl({ ...base, answers: [{ id: 'route', optionID: 'Unseen' }, base.answers[1]] }, { pending: [question] }), false);
  assert.equal(validControl({ ...base, answers: [{ id: 'route', optionID: 'Fast', text: 'Injected extra' }, base.answers[1]] }, { pending: [question] }), false);
  assert.equal(validControl({ ...base, answers: [{ id: 'route', text: 'My alternative' }, base.answers[1]] }, { pending: [question] }), true);
  assert.equal(validControl({ ...base, answers: [{ id: 'route', text: 'My alternative' }, base.answers[1]] }, { pending: [{ ...question, questions: [{ ...question.questions[0], allowOther: false }, question.questions[1]] }] }), false);
  assert.equal(validControl({ ...base, answers: [base.answers[0], { id: 'detail', text: '   ' }] }, { pending: [question] }), false);
  assert.equal(validControl({ ...base, answers: [base.answers[0], { id: 'detail', text: '가'.repeat(2667) }] }, { pending: [question] }), false);
});

test('explicit question submission waits for confirmation and suppresses duplicate taps', async () => {
  const gate = deferred();
  const h = harness([response(snapshot({ pending: [question] })), gate.promise, response(snapshot({ pending: [] }))]);
  await h.controller.start();
  const action = { type: 'question', id: question.id, fingerprint: question.fingerprint, answers: [{ id: 'route', optionID: 'Careful' }, { id: 'detail', text: 'Use the fixtures.' }] };
  const applying = h.controller.control(action);
  assert.equal(await h.controller.control(action), false);
  assert.equal(h.controller.state.feedback, null);
  assert.equal(h.requests.length, 2);
  gate.resolve(response({ ok: true }));
  assert.equal(await applying, true);
  assert.deepEqual(JSON.parse(h.requests[1].options.body), { ...action, targetID: 'chat-a' });
});

test('dictation accepts explicit start/stop only when available and owned for stop', () => {
  assert.equal(validControl({ type: 'dictation', recording: true }, { dictation: { available: true, recording: false } }), true);
  assert.equal(validControl({ type: 'dictation', recording: false }, { dictation: { available: true, recording: true, owned: true } }), true);
  assert.equal(validControl({ type: 'dictation', recording: false }, { dictation: { available: true, recording: true, owned: false } }), false);
  assert.equal(validControl({ type: 'dictation', recording: true }, { dictation: { available: true, recording: true } }), false);
  assert.equal(validControl({ type: 'dictation', recording: true }, { dictation: { available: false, recording: false } }), false);
  assert.equal(validControl({ type: 'dictation', recording: 'toggle' }, { dictation: { available: true, recording: false } }), false);
});

test('intentional logout is blocked while this deck owns active Mac dictation', async () => {
  const h = harness([response(snapshot({ dictation: { available: true, recording: true, owned: true } }))]);
  await h.controller.start();
  await h.controller.logout();
  assert.equal(h.requests.length, 1);
  assert.equal(h.controller.state.feedback.message, 'Stop Mac dictation before disconnecting.');
  assert.equal(h.controller.state.phase, 'ready');
});

test('sound starts media synchronously on every press regardless of an old sound preference', () => {
  const calls = [];
  const media = { currentTime: 99, play() { calls.push(['play', this.currentTime]); return Promise.resolve(); }, pause() { calls.push(['pause']); } };
  const window = {
    Audio: function (source) { calls.push(['source', source]); return media; },
    navigator: { vibrate: milliseconds => calls.push(['vibrate', milliseconds]) },
    get localStorage() { throw new Error('Old mute preferences must not be read'); }
  };
  const feedback = pressFeedback(window);
  feedback.play();
  assert.deepEqual(calls, [['source', '/click.wav'], ['vibrate', 12], ['play', 0]]);
  feedback.play();
  assert.equal(calls.filter(call => call[0] === 'play').length, 2);
  feedback.suspend();
  assert.deepEqual(calls.at(-1), ['pause']);
  assert.equal(feedback.toggle, undefined);
});

const { modelEffort } = require('../../Sources/CodexUsageWeb/Resources/deck.js');
test('model-name keys preserve a supported effort and choose a supported fallback', () => {
  assert.equal(modelEffort({ efforts: ['low', 'high', 'xhigh', 'ultra'] }, 'ultra'), 'ultra');
  assert.equal(modelEffort({ efforts: ['medium', 'high', 'xhigh'] }, 'ultra'), 'high');
  assert.equal(modelEffort({ efforts: ['low', 'medium'] }, 'ultra'), 'low');
});
