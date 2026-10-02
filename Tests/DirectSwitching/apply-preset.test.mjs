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
    onSelectModelOption() { props.selectionMode = 'model'; },
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
    location: { href: 'app://-/index.html#/threads/chat-1' },
    setTimeout: (fn) => setTimeout(fn, 1)
  });
  vm.runInContext(source, context);
  return { calls, props, settings, controller, owner, picker, host, trigger, triggers, current, apply: preset => context.applyCodexPreset(preset) };
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
