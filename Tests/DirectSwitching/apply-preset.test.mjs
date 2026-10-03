import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { test } from 'node:test';
const source = await readFile(new URL('../../Sources/CodexUsageAutomation/Resources/apply-preset.js', import.meta.url), 'utf8');
const defaultPresets = JSON.parse(await readFile(new URL('../../presets.example.json', import.meta.url), 'utf8')).presets;

function triggerElement(visible = true) {
  return {
    isConnected: true,
    closest: () => null,
    getClientRects: () => visible ? [{}] : [],
    checkVisibility: () => visible,
    getBoundingClientRect: () => ({ width: 40, height: 30, left: 20, right: 60, top: 20, bottom: 50 })
  };
}

function fixture(options = {}) {
  const calls = [];
  const models = [
    { model: 'gpt-6-astra', displayName: 'GPT-6 Astra', supportedReasoningEfforts: [{ reasoningEffort: 'ultra' }, { reasoningEffort: 'xhigh' }, { reasoningEffort: 'high' }] },
    { model: 'gpt-6.1-sol', displayName: 'GPT-6.1 Sol', supportedReasoningEfforts: [{ reasoningEffort: 'xhigh' }, { reasoningEffort: 'high' }] }
  ];
  const props = {
    onSelectModel() { throw Error('Do not use the void menu wrapper.'); },
    modelPickerTriggerConfig: {}, models, modelOptions: models.map(model => ({ model })),
    model: 'gpt-6-astra', reasoningEffort: 'xhigh', selectionMode: 'default',
    onSelectModelOption() { props.selectionMode = 'model'; if (options.selectionChangeChat) owner.memoizedProps.conversationId = 'other-chat'; },
    onBeforeSelectModel() { return options.confirmation !== false; }
  };
  const settings = { model: props.model, reasoningEffort: props.reasoningEffort, isLoading: false };
  const controller = {
    modelSettings: settings,
    async selectComposerModelAndReasoningEffort(model, effort) {
      calls.push({ model, effort });
      if (options.reject) throw Error('server rejected update');
      if (options.returnFalse) return false;
      if (options.changeChat) owner.memoizedProps.conversationId = 'other-chat';
      if (options.changeRoute) context.location.href = 'app://-/index.html#/settings';
      if (options.swapDraft) {
        const alternateOwner = { ...owner, alternate: owner };
        owner.alternate = alternateOwner;
        const alternatePicker = { ...picker, return: alternateOwner, alternate: picker };
        picker.alternate = alternatePicker;
        alternateOwner.child = alternatePicker;
        current.child = alternateOwner;
      }
      if (!options.noUpdate) Object.assign(props, { model, reasoningEffort: options.simpleReset && props.selectionMode !== 'model' ? 'high' : effort });
      Object.assign(settings, { model, reasoningEffort: effort });
      return true;
    }
  };
  const override = options.agentOverride ? { selectModelAndReasoningEffort: controller.selectComposerModelAndReasoningEffort } : null;
  if (override) controller.selectComposerModelAndReasoningEffort = () => { throw Error('Wrong default-model controller'); };
  const dispatcher = (model, effort) => (override?.selectModelAndReasoningEffort ?? controller.selectComposerModelAndReasoningEffort)(model, effort);
  const owner = { memoizedProps: { conversationId: options.swapDraft ? null : 'chat-1' }, updateQueue: { memoCache: { data: [[null, controller, dispatcher, dispatcher]] } } };
  const picker = { memoizedProps: props, return: owner };
  const trigger = triggerElement();
  const triggers = [trigger];
  const host = { stateNode: trigger, return: picker };
  picker.child = host;
  owner.child = picker;
  const current = { child: owner };
  const root = { '__reactContainer$test': { stateNode: { current } } };
  const context = vm.createContext({
    document: { getElementById: () => root, hasFocus: () => options.focus !== false, querySelectorAll: () => triggers },
    innerWidth: 1200, innerHeight: 800,
    TextEncoder,
    location: { href: 'app://-/index.html#/threads/chat-1' },
    setTimeout: (fn) => setTimeout(fn, 1)
  });
  vm.runInContext(source, context);
  return { calls, props, settings, controller, owner, picker, host, trigger, triggers, current, context,
    action: input => context.performCodexDeckAction(input),
    apply: preset => context.applyCodexPreset(preset), applyRemote: (preset, id) => context.applyCodexPreset(preset, id), deckState: () => context.readCodexDeck() };
}
const preset = defaultPresets.find(p => p.slot === 4);

test('all five default presets call the bound async callback and retain exact model/effort', async () => {
  const f = fixture();
  for (const p of defaultPresets) {
    const result = await f.apply(p);
    assert.equal(result.effort, p.effort);
    assert.equal(f.props.model, result.model);
  }
  assert.deepEqual(f.calls, [
    { model: 'gpt-6-astra', effort: 'ultra' }, { model: 'gpt-6-astra', effort: 'xhigh' },
    { model: 'gpt-6-astra', effort: 'high' }, { model: 'gpt-6.1-sol', effort: 'xhigh' }, { model: 'gpt-6.1-sol', effort: 'high' }
  ]);
});
test('an already selected preset sends no update', async () => {
  const f = fixture();
  assert.equal((await f.apply({ model: 'GPT-6 Astra', effort: 'xhigh' })).changed, false);
  assert.equal(f.calls.length, 0);
});
for (const [name, options, message] of [
  ['focus lost', { focus: false }, /focus/],
  ['confirmation required', { confirmation: false }, /confirmation/],
  ['server failure', { reject: true }, /server rejected/],
  ['server refused', { returnFalse: true }, /did not confirm/],
  ['chat changes during update', { changeChat: true }, /composer changed/],
  ['composer does not retain update', { noUpdate: true }, /did not retain/]
]) test(name, async () => { await assert.rejects(fixture(options).apply(preset), message); });
for (const [name, mutate, input, message] of [
  ['disabled model', f => { f.props.modelOptions[1].disabledReason = 'unavailable'; }, preset, /disables this model/],
  ['disabled composer', f => { f.props.disabled = true; }, preset, /disables model/],
  ['disabled daybreak', f => { f.props.daybreak = { disabled: true }; }, preset, /disables model/],
  ['unsupported effort', () => {}, { ...preset, effort: 'ultra' }, /does not support/],
  ['unknown model', () => {}, { ...preset, model: 'Missing' }, /not found/],
  ['two visible composers', f => {
    const trigger = triggerElement(); f.triggers.push(trigger);
    f.picker.sibling = { memoizedProps: f.props, child: { stateNode: trigger } };
  }, preset, /Several visible/],
  ['catalog loading', f => { f.props.models = undefined; f.props.modelOptions = undefined; }, preset, /loading its model catalog/],
  ['no visible model control', f => { f.triggers.length = 0; }, preset, /No visible/],
  ['unmapped visible model control', f => { f.host.stateNode = null; }, preset, /could not be linked/],
  ['missing controller', f => { f.owner.updateQueue = {}; }, preset, /callback shape/],
  ['duplicate callbacks', f => { f.owner.updateQueue.memoCache.data[0].push(() => (f?.selectModelAndReasoningEffort ?? (() => {}))()); }, preset, /Several composer/]
]) test(name, async () => {
  const f = fixture(); mutate(f);
  await assert.rejects(f.apply(input), message);
  assert.equal(f.calls.length, 0);
});

test('an explicit preset survives simple-mode fallback rules', async () => {
  const f = fixture({ simpleReset: true });
  await f.apply(preset);
  assert.equal(f.props.reasoningEffort, 'xhigh');
  assert.equal(f.props.selectionMode, 'model');
});
test('draft re-render uses reciprocal React alternate without changing identity', async () => {
  const f = fixture({ swapDraft: true });
  await f.apply(preset);
  assert.equal(f.props.model, 'gpt-6.1-sol');
});
test('agent composers use the outer dispatcher instead of default settings', async () => {
  const f = fixture({ agentOverride: true });
  await f.apply(preset);
  assert.equal(f.calls.length, 1);
});

test('hidden mounted pickers do not make the active composer ambiguous', async () => {
  const f = fixture();
  const hidden = triggerElement(false);
  f.triggers.push(hidden);
  f.owner.sibling = { memoizedProps: { ...f.props }, child: { stateNode: hidden } };
  await f.apply(preset);
  assert.equal(f.calls.length, 1);
});

test('inert, aria-hidden and offscreen model controls are excluded', async () => {
  const f = fixture();
  const hidden = triggerElement(); hidden.closest = () => ({});
  const offscreen = triggerElement();
  offscreen.getBoundingClientRect = () => ({ width: 40, height: 30, left: 1500, right: 1540, top: 20, bottom: 50 });
  f.triggers.push(hidden, offscreen);
  await f.apply(preset);
  assert.equal(f.calls.length, 1);
});

test('uses committed picker props despite a stale DOM fiber pointer and return chain', async () => {
  const f = fixture();
  const stale = { memoizedProps: { ...f.props, modelOptions: [] } };
  f.trigger.__reactFiber$test = { return: stale };
  f.host.return = stale;
  f.picker.return = { memoizedProps: { conversationId: 'old-chat' } };
  await f.apply(preset);
  assert.equal(f.props.model, 'gpt-6.1-sol');
});

test('a large mounted tree does not hide the visible composer behind the old 20k limit', async () => {
  const f = fixture();
  let branch = f.owner;
  for (let i = 0; i < 21000; i++) branch = { sibling: branch };
  f.current.child = branch;
  await f.apply(preset);
  assert.equal(f.calls.length, 1);
});

test('custom catalog display names return the verified canonical model ID', async () => {
  const f = fixture();
  Object.assign(f.props.modelOptions[1].model, { model: 'provider:special-v2', displayName: 'My Custom Model' });
  const result = await f.apply({ ...preset, model: 'My Custom Model' });
  assert.equal(result.model, 'provider:special-v2');
  assert.equal(result.displayName, 'My Custom Model');
  assert.equal(f.props.model, result.model);
});


test('Web Deck reports saved chat controls without transcript or private drafts', () => {
  const f = fixture({ focus: false });
  f.owner.memoizedProps.title = 'Fixture chat';
  f.owner.memoizedProps.messages = ['private transcript must not be returned'];
  const state = JSON.parse(JSON.stringify(f.deckState()));
  assert.deepEqual(state, { targetID: 'chat-1', title: 'Fixture chat', model: 'gpt-6-astra', effort: 'xhigh',
    models: [{ id: 'gpt-6-astra', name: 'GPT-6 Astra', efforts: ['ultra', 'xhigh', 'high'] },
      { id: 'gpt-6.1-sol', name: 'GPT-6.1 Sol', efforts: ['xhigh', 'high'] }],
    activity: 'unknown', dictation: { available: false, recording: false, owned: false }, pending: [] });
  assert.equal(f.calls.length, 0);
});

test('Web Deck applies all five presets to its exact saved target in the background', async () => {
  const f = fixture({ focus: false });
  const targetID = f.deckState().targetID;
  for (const preset of defaultPresets) {
    const result = await f.applyRemote(preset, targetID);
    assert.equal(result.effort, preset.effort);
    assert.equal(f.props.model, result.model);
  }
  assert.equal(f.calls.length, 5);
});

test('Web Deck rejects a stale target before calling the model callback', async () => {
  const f = fixture({ focus: false });
  await assert.rejects(f.applyRemote(preset, 'previous-chat'), /no longer active/);
  assert.equal(f.calls.length, 0);
});

test('Web Deck rejects drafts for both discovery and mutation', async () => {
  const f = fixture({ swapDraft: true, focus: false });
  assert.throws(() => f.deckState(), /saved Codex chat/);
  await assert.rejects(f.applyRemote(preset, 'chat-1'), /no longer active/);
  assert.equal(f.calls.length, 0);
});

test('Web Deck cannot bypass the original model confirmation', async () => {
  const f = fixture({ focus: false, confirmation: false });
  await assert.rejects(f.applyRemote(preset, 'chat-1'), /confirmation/);
  assert.equal(f.calls.length, 0);
});

test('Web Deck checks the chat again after selecting explicit model mode', async () => {
  const f = fixture({ focus: false, selectionChangeChat: true });
  await assert.rejects(f.applyRemote(preset, 'chat-1'), /composer changed/);
  assert.equal(f.calls.length, 0);
});

for (const [name, options, message] of [
  ['chat changes while applying', { changeChat: true }, /composer changed/],
  ['route changes while applying', { changeRoute: true }, /focus or chat/],
  ['selection does not retain effort', { noUpdate: true }, /did not retain/]
]) test(`Web Deck rejects unconfirmed success when ${name}`, async () => {
  const f = fixture({ ...options, focus: false });
  await assert.rejects(f.applyRemote(preset, 'chat-1'), message);
});

function pendingFixture(f, type = 'userInput', options = {}) {
  const calls = [];
  const question = { id: 'next', question: 'Which task next?', isOther: true, isSecret: false,
    options: [{ label: 'Build', description: 'Implement the next change' }, { label: 'Review', description: 'Review first' }] };
  const item = type === 'userInput' ? { requestId: 'request-1', questions: [question] } :
    type === 'permissionRequest' ? { requestId: 'request-1', reason: 'Read the project?', permissions: { fileSystem: { read: ['/project'] } } } :
      { approvalRequestId: 'request-1', type: 'exec', cmd: ['git', 'status'], cwd: '/project', approvalReason: 'Inspect repository state?' };
  const request = { type, item };
  const panel = { memoizedProps: { conversationId: options.foreign ? 'other-chat' : 'chat-1', pendingRequest: request } };
  const complete = () => { if (!options.retain) f.picker.sibling = null; };
  const client = { replyWithUserInputResponse(target, id, response) { calls.push({ target, id, response }); complete(); } };
  const submit = response => client.replyWithUserInputResponse('chat-1', item.requestId, response);
  const actions = {
    onApprove: () => { calls.push('approve'); complete(); },
    onDeny: () => { calls.push('deny'); complete(); },
    scopedApproveAction: { onClick: () => { throw new Error('Must never grant session-wide access.'); } }
  };
  const controls = { memoizedProps: type === 'userInput' ? { questionAndOptions: [question], onSubmit: submit } : { actions },
    child: { stateNode: triggerElement(!options.hidden) } };
  panel.child = controls;
  f.picker.sibling = panel;
  return { panel, controls, request, item, question, calls };
}

function currentAction(f, extra) {
  const request = f.deckState().pending[0];
  return { targetID: 'chat-1', type: request.kind, id: request.id, fingerprint: request.fingerprint, ...extra };
}

function voiceFixture(f, options = {}) {
  const calls = [];
  const voice = {
    isDictating: false, isDictationStarting: false, isTranscribing: false,
    isMicrophoneBusy: false, isDictationSupported: true, isDictationButtonVisible: true,
    realtimeSession: { thread: { phase: 'inactive' } },
    async startDictation(mode) {
      calls.push(['start', mode]);
      if (options.delayedStart) setTimeout(() => { voice.isDictating = true; }, 5);
      else if (!options.noStart) voice.isDictating = true;
    },
    async stopDictation(mode) { calls.push(['stop', mode]); if (!options.noStop) voice.isDictating = false; }
  };
  f.owner.memoizedProps.voiceControls = voice;
  const control = { startDictation: mode => voice.startDictation(mode), stopDictation: voice.stopDictation,
    isVisible: true, disabled: false };
  const fiber = { memoizedProps: control, child: { stateNode: triggerElement() }, sibling: f.picker };
  f.owner.child = fiber;
  return { voice, calls, control, fiber };
}

test('model dial action reuses exact selection verification', async () => {
  const f = fixture({ focus: false });
  const result = await f.action({ type: 'model', targetID: 'chat-1', model: 'gpt-6.1-sol', effort: 'high' });
  assert.equal(result.ok, true);
  assert.equal(f.props.reasoningEffort, 'high');
});

test('catalog excludes disabled and locked choices, and disabled composers expose no choices', () => {
  const f = fixture();
  f.props.modelOptions[0].disabledReason = 'unavailable';
  f.props.lockedModelSlug = 'gpt-6.1-sol';
  assert.equal(f.deckState().models.length, 0);
  delete f.props.modelOptions[0].disabledReason;
  f.props.disabled = true;
  assert.equal(f.deckState().models.length, 0);
});

test('questions expose only current prompts, choices and custom-answer rules', () => {
  const f = fixture();
  const p = pendingFixture(f);
  p.controls.memoizedProps.initialDraft = { secret: 'private unsent answer' };
  const request = f.deckState().pending[0];
  assert.equal(request.kind, 'question');
  assert.equal(request.questions[0].allowOther, true);
  assert.equal(request.questions[0].options[0].id, 'Build');
  assert.ok(!JSON.stringify(request).includes('private unsent answer'));
  assert.equal(request.fingerprint, JSON.stringify({ request: Object.fromEntries(Object.entries(request).filter(([key]) => key !== 'fingerprint')), hostID: null }));
});

test('exact option answers call the native question callback and wait for removal', async () => {
  const f = fixture({ focus: false });
  const p = pendingFixture(f);
  const result = await f.action(currentAction(f, { answers: [{ id: 'next', optionID: 'Review' }] }));
  assert.equal(result.ok, true);
  assert.deepEqual(JSON.parse(JSON.stringify(p.calls)), [{ target: 'chat-1', id: 'request-1', response: [{ selectedOptionId: 'Review', freeformText: '' }] }]);
  assert.equal(f.deckState().pending.length, 0);
});

test('freeform answers are only accepted for the current freeform-capable questions', async () => {
  const f = fixture();
  const p = pendingFixture(f);
  p.question.isSecret = true;
  assert.equal(f.deckState().pending[0].questions[0].isSecret, true);
  const result = await f.action(currentAction(f, { answers: [{ id: 'next', text: '  Another task  ' }] }));
  assert.equal(result.ok, true);
  assert.equal(p.calls[0].response[0].freeformText, 'Another task');
});

for (const [name, publicOptions] of [['empty', []], ['missing', undefined], ['null', null]]) {
  test(`freeform-only public questions with ${name} options work after Codex's native normalization`, async () => {
    const f = fixture(); const p = pendingFixture(f);
    // Static app-shared C6r/T6r normalize this public protocol shape before Gr
    // receives it. The bridge consumes this committed, already-normalized item.
    p.question.options = (publicOptions ?? []).map(option => ({ label: option.label, description: option.description }));
    p.question.isOther = false;
    assert.equal(f.deckState().pending[0].questions[0].allowOther, true);
    await f.action(currentAction(f, { answers: [{ id: 'next', text: 'Use the existing implementation.' }] }));
    assert.equal(p.calls[0].response[0].freeformText, 'Use the existing implementation.');
  });
}

for (const [name, mutate] of [
  ['missing normalized options', p => { delete p.question.options; }],
  ['null normalized options', p => { p.question.options = null; }],
  ['non-array options', p => { p.question.options = 'invalid'; }],
  ['null option', p => { p.question.options = [null]; }],
  ['malformed option description', p => { p.question.options[0].description = {}; }],
  ['duplicate option labels', p => { p.question.options.push(p.question.options[0]); }],
  ['blank question ID', p => { p.question.id = ''; }],
  ['null question', p => { p.item.questions = [null]; }],
  ['missing question set', p => { delete p.item.questions; }],
  ['empty question set', p => { p.item.questions = []; }],
  ['duplicate question IDs', p => { p.item.questions.push({ ...p.question }); }],
  ['missing request ID', p => { delete p.item.requestId; }],
  ['non-finite request ID', p => { p.item.requestId = Infinity; }]
]) test(`malformed mounted question: ${name} shows a Codex fallback instead of no requests`, () => {
  const f = fixture(); const p = pendingFixture(f); mutate(p);
  assert.equal(f.deckState().pending.length, 0);
  assert.match(f.deckState().pendingUnavailable, /Codex/);
  assert.equal(p.calls.length, 0);
});

for (const [name, answers] of [
  ['unknown option', [{ id: 'next', optionID: 'Delete everything' }]],
  ['foreign question', [{ id: 'foreign', optionID: 'Build' }]],
  ['blank answer', [{ id: 'next', text: ' ' }]],
  ['extra fields', [{ id: 'next', text: 'Build', sendPrompt: true }]],
  ['option with unrelated text', [{ id: 'next', optionID: 'Build', text: 'also do this' }]],
  ['extra question', [{ id: 'next', optionID: 'Build' }, { id: 'other', text: 'text' }]],
  ['missing answer', []]
]) test(`question action rejects ${name} before native dispatch`, async () => {
  const f = fixture(); const p = pendingFixture(f);
  await assert.rejects(f.action(currentAction(f, { answers })));
  assert.equal(p.calls.length, 0);
});

test('questions without an Other option reject custom text', async () => {
  const f = fixture(); const p = pendingFixture(f); p.question.isOther = false;
  await assert.rejects(f.action(currentAction(f, { answers: [{ id: 'next', text: 'custom' }] })), /valid answer/);
  assert.equal(p.calls.length, 0);
});

for (const type of ['approval', 'permissionRequest']) for (const decision of ['approve', 'deny']) {
  test(`${type} ${decision} uses only its one-request callback`, async () => {
    const f = fixture(); const p = pendingFixture(f, type);
    const result = await f.action(currentAction(f, { decision }));
    assert.equal(result.ok, true);
    assert.deepEqual(p.calls, [decision]);
  });
}

test('nested normalized permission panel is not exposed as another unsupported request', () => {
  const f = fixture(); const p = pendingFixture(f, 'permissionRequest');
  p.item.type = 'permission-request';
  p.panel.child = { memoizedProps: { conversationId: 'chat-1', pendingRequest: p.item }, child: p.controls };
  assert.equal(f.deckState().pending.length, 1);
  assert.equal(f.deckState().pendingUnavailable, undefined);
});

test('malformed mounted permissions show a Codex fallback', () => {
  const f = fixture(); const p = pendingFixture(f, 'permissionRequest');
  p.item.permissions = null;
  assert.equal(f.deckState().pending.length, 0);
  assert.match(f.deckState().pendingUnavailable, /Codex/);
});

test('patch approval exposes full changes rather than hiding the diff', () => {
  const f = fixture(); const p = pendingFixture(f, 'approval');
  Object.assign(p.item, { type: 'patch', changes: { 'test.js': { type: 'update', unifiedDiff: '-old\n+new' } } });
  assert.deepEqual(JSON.parse(f.deckState().pending[0].detail).changes, p.item.changes);
});

test('patch approval includes grant scope and visualization changes in review and fingerprint', async () => {
  const f = fixture(); const p = pendingFixture(f, 'approval');
  Object.assign(p.item, { type: 'patch', changes: {}, grantRoot: '/project', visualizationActivities: [{ action: 'update', id: 'chart-1', patch: 'new chart' }] });
  const request = f.deckState().pending[0];
  const detail = JSON.parse(request.detail);
  assert.equal(detail.grantRoot, '/project');
  assert.deepEqual(detail.visualizationActivities, p.item.visualizationActivities);
  const action = currentAction(f, { decision: 'approve' });
  p.item.grantRoot = '/';
  await assert.rejects(f.action(action), /request changed/);
  assert.equal(p.calls.length, 0);
});

test('changed host or command scope invalidates the approval fingerprint', async () => {
  const f = fixture(); const p = pendingFixture(f, 'approval');
  const action = currentAction(f, { decision: 'approve' });
  p.item.proposedExecpolicyAmendment = ['git'];
  await assert.rejects(f.action(action), /request changed/);
  delete p.item.proposedExecpolicyAmendment;
  p.panel.memoizedProps.hostId = 'different-host';
  await assert.rejects(f.action(action), /request changed/);
  assert.equal(p.calls.length, 0);
});

test('approval cannot grant blanket/session access', async () => {
  const f = fixture(); const p = pendingFixture(f, 'approval');
  await assert.rejects(f.action(currentAction(f, { decision: 'acceptForSession' })), /allowing once/);
  assert.equal(p.calls.length, 0);
});

test('changed command content invalidates approval fingerprint', async () => {
  const f = fixture(); const p = pendingFixture(f, 'approval');
  const action = currentAction(f, { decision: 'approve' });
  p.item.cmd.push('--different');
  await assert.rejects(f.action(action), /request changed/);
  assert.equal(p.calls.length, 0);
});

test('changed question invalidates its fingerprint', async () => {
  const f = fixture(); const p = pendingFixture(f);
  const action = currentAction(f, { answers: [{ id: 'next', optionID: 'Build' }] });
  p.question.question = 'Different request';
  await assert.rejects(f.action(action), /request changed/);
  assert.equal(p.calls.length, 0);
});

test('pending actions reject a stale chat and replayed response', async () => {
  const f = fixture(); const p = pendingFixture(f, 'approval');
  const action = currentAction(f, { decision: 'deny' });
  await assert.rejects(f.action({ ...action, targetID: 'other-chat' }), /no longer active/);
  await f.action(action);
  await assert.rejects(f.action(action), /already answered/);
  assert.deepEqual(p.calls, ['deny']);
});

test('unmounted and foreign pending controls are not exposed', () => {
  const f = fixture(); pendingFixture(f, 'userInput', { hidden: true });
  assert.equal(f.deckState().pending.length, 0);
  pendingFixture(f, 'userInput', { foreign: true });
  assert.equal(f.deckState().pending.length, 0);
});

test('unsupported callback shapes fail closed and give a Mac fallback', () => {
  const f = fixture(); const p = pendingFixture(f);
  p.controls.memoizedProps.onSubmit = () => { throw Error('Do not call this.'); };
  assert.equal(f.deckState().pending.length, 0);
  assert.match(f.deckState().pendingUnavailable, /cannot be answered remotely/);
});

test('oversized approval is withheld instead of truncating command details', () => {
  const f = fixture(); const p = pendingFixture(f, 'approval');
  p.item.cmd = ['x'.repeat(11000)];
  assert.equal(f.deckState().pending.length, 0);
  assert.match(f.deckState().pendingUnavailable, /too large/);
});

test('native callbacks that leave their request pending are not reported as success', async () => {
  const f = fixture(); const p = pendingFixture(f, 'approval', { retain: true });
  await assert.rejects(f.action(currentAction(f, { decision: 'approve' })), /has not confirmed/);
  assert.deepEqual(p.calls, ['approve']);
});

test('Mac dictation starts in tap mode and stops with insert-only semantics', async () => {
  const f = fixture(); const v = voiceFixture(f);
  assert.equal(f.deckState().dictation.available, true);
  assert.equal((await f.action({ type: 'dictation', targetID: 'chat-1', recording: true })).ok, true);
  assert.equal(f.deckState().dictation.owned, true);
  assert.equal((await f.action({ type: 'dictation', targetID: 'chat-1', recording: false })).ok, true);
  assert.deepEqual(v.calls, [['start', 'tap'], ['stop', 'insert']]);
  assert.equal(f.deckState().dictation.recording, false);
  assert.equal(f.deckState().dictation.owned, false);
});

test('Web Deck cannot stop a recording started on the Mac', async () => {
  const f = fixture(); const v = voiceFixture(f); v.voice.isDictating = true;
  await assert.rejects(f.action({ type: 'dictation', targetID: 'chat-1', recording: false }), /started in Codex/);
  assert.equal(v.calls.length, 0);
});

test('observing idle or a changed callback revokes dictation ownership', async () => {
  const f = fixture(); const v = voiceFixture(f);
  await f.action({ type: 'dictation', targetID: 'chat-1', recording: true });
  v.voice.isDictating = false;
  assert.equal(f.deckState().dictation.owned, false);
  v.voice.isDictating = true;
  await assert.rejects(f.action({ type: 'dictation', targetID: 'chat-1', recording: false }), /started in Codex/);
  v.voice.isDictating = false;
  await f.action({ type: 'dictation', targetID: 'chat-1', recording: true });
  v.voice.stopDictation = async () => { throw Error('Unrelated callback'); };
  v.control.stopDictation = v.voice.stopDictation;
  await assert.rejects(f.action({ type: 'dictation', targetID: 'chat-1', recording: false }), /started in Codex/);
});

for (const [field, value] of [['isDictationSupported', false], ['isDictationButtonVisible', false],
  ['isMicrophoneBusy', true], ['isDictationStarting', true], ['isTranscribing', true]]) {
  test(`dictation is unavailable when ${field}=${value}`, async () => {
    const f = fixture(); const v = voiceFixture(f); v.voice[field] = value;
    await assert.rejects(f.action({ type: 'dictation', targetID: 'chat-1', recording: true }), /not available/);
    assert.equal(v.calls.length, 0);
  });
}

test('dictation startup must be verified rather than assumed', async () => {
  const f = fixture(); voiceFixture(f, { noStart: true });
  await assert.rejects(f.action({ type: 'dictation', targetID: 'chat-1', recording: true }), /did not confirm/);
  assert.equal(f.deckState().dictation.owned, false);
});

test('dictation retains ownership until a delayed React commit confirms recording', async () => {
  const f = fixture(); const v = voiceFixture(f, { delayedStart: true });
  await f.action({ type: 'dictation', targetID: 'chat-1', recording: true });
  assert.equal(f.deckState().dictation.owned, true);
  await f.action({ type: 'dictation', targetID: 'chat-1', recording: false });
  assert.deepEqual(v.calls, [['start', 'tap'], ['stop', 'insert']]);
});

test('native microphone disabled or hidden state cannot be bypassed', async () => {
  const f = fixture(); const v = voiceFixture(f);
  v.control.disabled = true;
  await assert.rejects(f.action({ type: 'dictation', targetID: 'chat-1', recording: true }), /not available/);
  v.control.disabled = false;
  v.control.isVisible = false;
  await assert.rejects(f.action({ type: 'dictation', targetID: 'chat-1', recording: true }), /not available/);
  assert.equal(v.calls.length, 0);
});

test('explicit Stop remains available when an owned recording replaces the idle microphone control', async () => {
  const f = fixture(); const v = voiceFixture(f);
  await f.action({ type: 'dictation', targetID: 'chat-1', recording: true });
  v.control.isVisible = false;
  v.voice.isDictationButtonVisible = false;
  assert.equal(f.deckState().dictation.available, true);
  await f.action({ type: 'dictation', targetID: 'chat-1', recording: false });
  assert.deepEqual(v.calls, [['start', 'tap'], ['stop', 'insert']]);
});

test('inspecting a different chat cannot stop the original recording or lose its observed ownership', async () => {
  const f = fixture(); const v = voiceFixture(f);
  await f.action({ type: 'dictation', targetID: 'chat-1', recording: true });
  f.owner.memoizedProps.conversationId = 'other-chat';
  assert.equal(f.deckState().dictation.owned, false);
  await assert.rejects(f.action({ type: 'dictation', targetID: 'other-chat', recording: false }), /started in Codex/);
  f.owner.memoizedProps.conversationId = 'chat-1';
  assert.equal(f.deckState().dictation.owned, true);
  await f.action({ type: 'dictation', targetID: 'chat-1', recording: false });
  assert.deepEqual(v.calls, [['start', 'tap'], ['stop', 'insert']]);
});


// Status fixtures reproduce Codex's conversation row -> statusState props.
function activityRow(f, status, conversationId = 'chat-1') {
  const row = { memoizedProps: { conversationId }, child: { memoizedProps: { statusState: status } } };
  row.sibling = f.owner.sibling;
  f.owner.sibling = row;
  return row;
}
for (const [status, expected] of [
  [{ type: 'idle', unread: false }, 'idle'],
  [{ type: 'idle', unread: true }, 'complete'],
  [{ type: 'loading', unread: false }, 'thinking'],
  [{ type: 'loading', unread: true }, 'thinking'],
  [{ type: 'error', unread: true }, 'error']
]) test(`chat frame reads native ${expected} state without invoking a callback`, () => {
  const f = fixture(); activityRow(f, status);
  assert.equal(f.deckState().activity, expected);
  assert.equal(f.calls.length, 0);
});
test('missing, unsupported and conflicting status props stay unknown', () => {
  const f = fixture();
  assert.equal(f.deckState().activity, 'unknown');
  const row = activityRow(f, { type: 'future-status', unread: false });
  assert.equal(f.deckState().activity, 'unknown');
  row.child.memoizedProps.statusState = { type: 'idle', unread: false };
  activityRow(f, { type: 'loading', unread: false });
  assert.equal(f.deckState().activity, 'unknown');
});
test('another chat and a nested draft cannot supply this chat status', () => {
  const f = fixture();
  activityRow(f, { type: 'error', unread: true }, 'other-chat');
  const row = activityRow(f, { type: 'idle', unread: false });
  row.child.memoizedProps.conversationId = null;
  assert.equal(f.deckState().activity, 'unknown');
  delete row.child.memoizedProps.conversationId;
  assert.equal(f.deckState().activity, 'idle');
});
test('mounted requests take priority, including unsupported Mac-only requests', () => {
  const f = fixture(); activityRow(f, { type: 'loading', unread: false });
  const request = pendingFixture(f, 'userInput');
  assert.equal(f.deckState().activity, 'requires-input');
  request.panel.memoizedProps.pendingRequest.type = 'unsupported';
  assert.equal(f.deckState().activity, 'requires-input');
  request.controls.child.stateNode = triggerElement(false);
  assert.equal(f.deckState().activity, 'thinking');
});

test('active composer can report thinking when its sidebar status is not mounted', () => {
  const f = fixture();
  f.owner.memoizedProps.isResponseInProgress = true;
  assert.equal(f.deckState().activity, 'thinking');
  f.owner.memoizedProps.isResponseInProgress = false;
  assert.equal(f.deckState().activity, 'unknown');
});
