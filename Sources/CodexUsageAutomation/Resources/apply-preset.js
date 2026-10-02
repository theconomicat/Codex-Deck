// Calls the active composer's existing selection callback. No menu clicks or
// transcript reads. Discovery is structural so version-hashed names can change.
function codexComposerRuntime() {
  const fail = message => { throw new Error(message); };
  const root = document.getElementById('root');
  const key = root && Object.getOwnPropertyNames(root).find(k => k.startsWith('__reactContainer$'));
  if (!key) fail('Codex did not expose its composer runtime.');
  const currentRoot = () => {
    const container = root[key];
    return container?.stateNode?.current ?? container?.current ?? container;
  };
  const locate = () => {
    // Codex mounts several picker surfaces. Start from visible controls, then
    // resolve their host nodes in the committed tree (DOM fiber pointers can
    // still refer to the previous React alternate).
    const triggers = new Set([...document.querySelectorAll('[data-codex-intelligence-trigger]')].filter(element => {
      if (!element.isConnected || element.closest('[hidden], [inert], [aria-hidden="true"]') ||
          !element.getClientRects().length ||
          element.checkVisibility?.({ checkOpacity: true, checkVisibilityCSS: true }) === false) return false;
      const bounds = element.getBoundingClientRect();
      return bounds.width > 0 && bounds.height > 0 && bounds.bottom > 0 && bounds.right > 0 &&
        bounds.top < innerHeight && bounds.left < innerWidth;
    }));
    if (!triggers.size) fail('No visible Codex model control was found. Open a chat with its composer visible.');
    const remaining = new Set(triggers);
    const queue = [{ fiber: currentRoot(), parent: null }];
    const seen = new Set();
    const parents = new Map();
    const matches = new Map();
    while (queue.length && remaining.size && seen.size < 100000) {
      const { fiber, parent } = queue.pop();
      if (!fiber || seen.has(fiber)) continue;
      seen.add(fiber);
      parents.set(fiber, parent);
      if (remaining.delete(fiber.stateNode)) {
        for (let owner = fiber; owner; owner = parents.get(owner)) {
          const props = owner.memoizedProps;
          if (props && typeof props.onSelectModel === 'function' &&
              Object.hasOwn(props, 'modelOptions') && Object.hasOwn(props, 'modelPickerTriggerConfig')) {
            const owners = [];
            for (let ancestor = owner; ancestor && owners.length < 40; ancestor = parents.get(ancestor)) owners.push(ancestor);
            matches.set(owner, { fiber: owner, props, owners });
            break;
          }
        }
      }
      queue.push({ fiber: fiber.sibling, parent }, { fiber: fiber.child, parent: fiber });
    }
    const diagnostics = `${triggers.size} visible controls, ${matches.size} composers, ${seen.size} React nodes`;
    if (remaining.size && queue.length) fail(`The composer search reached its limit (${diagnostics}).`);
    if (remaining.size || matches.size === 0) fail(`The visible model control could not be linked to its composer (${diagnostics}).`);
    if (matches.size !== 1) fail(`Several visible model composers were found (${diagnostics}). Close the extra composer, then retry.`);
    return matches.values().next().value;
  };
  const dispatcherFor = ({ owners }) => {
    for (const owner of owners) {
      // The outer composer dispatcher preserves agent-specific overrides and
      // returns the native async result. The menu prop itself discards it.
      for (const cache of owner.updateQueue?.memoCache?.data ?? []) {
        if (!Array.isArray(cache)) continue;
        const dispatchers = [...new Set(cache.filter(value => typeof value === 'function' &&
          /\.selectModelAndReasoningEffort\s*\?\?/.test(Function.prototype.toString.call(value))))];
        if (dispatchers.length === 1) return dispatchers[0];
        if (dispatchers.length > 1) fail('Several composer model callbacks were found.');
      }
    }
    fail('This Codex version does not expose the supported composer callback shape.');
  };
  const identityFor = ({ owners }) => {
    for (const owner of owners) {
      const props = owner.memoizedProps;
      if (typeof props?.conversationId === 'string') return props.conversationId;
    }
    // Draft composers have no persisted conversation ID; their owner must stay
    // mounted throughout the change.
    return owners[1];
  };
  return { locate, dispatcherFor, identityFor };
}

async function applyCodexPreset(preset, expectedTargetID = null) {
  const fail = message => { throw new Error(message); };
  const normalize = value => String(value).toLowerCase().replace(/[^\p{L}\p{N}]/gu, '').replace(/^gpt/, '');
  const { locate, dispatcherFor, identityFor } = codexComposerRuntime();
  const initial = locate();
  const dispatch = dispatcherFor(initial);
  const identity = identityFor(initial);
  if (expectedTargetID !== null && (typeof expectedTargetID !== 'string' ||
      !expectedTargetID.length || identity !== expectedTargetID)) {
    fail('The selected Web Deck chat is no longer active. Refresh and select it again.');
  }
  const route = location.href;
  const ensureActive = () => {
    if ((expectedTargetID === null && !document.hasFocus()) || location.href !== route) fail('Codex changed focus or chat; the preset stopped.');
    const active = locate();
    const activeIdentity = identityFor(active);
    const same = typeof identity === 'string' ? activeIdentity === identity :
      activeIdentity === identity || activeIdentity?.alternate === identity;
    if (!same) fail('The active composer changed; the preset stopped.');
    return active;
  };
  ensureActive();
  const props = initial.props;
  if (!Array.isArray(props.models) || !Array.isArray(props.modelOptions)) {
    fail('Codex is still loading its model catalog. Retry when the models are available.');
  }
  if (props.disabled || props.modelOptionsDisabled || props.reasoningEffortDisabled ||
      props.daybreak?.isSaving || props.daybreak?.disabled) fail('Codex currently disables model or reasoning changes.');
  const models = props.modelOptions.filter(option =>
    normalize(option.model?.model) === normalize(preset.model) ||
    normalize(option.model?.displayName) === normalize(preset.model));
  if (models.length !== 1) fail('The configured model was not found uniquely in your Codex catalog.');
  const option = models[0];
  const model = option.model.model;
  if (option.disabledReason != null) fail('Codex currently disables this model.');
  if (props.lockedModelSlug === model) fail('Codex locks this model selection.');
  if (!option.model.supportedReasoningEfforts?.some(level => level.reasoningEffort === preset.effort)) {
    fail('The selected model does not support the configured reasoning effort.');
  }
  if (props.onBeforeSelectModel?.(model) === false) fail('Complete Codex\'s model confirmation, then retry.');
  ensureActive();
  if (props.selectionMode !== 'model') {
    if (typeof props.onSelectModelOption !== 'function') fail('Codex did not expose explicit model selection.');
    props.onSelectModelOption();
  }
  ensureActive();
  const changed = props.model !== model || props.reasoningEffort !== preset.effort;
  if (changed) {
    const applied = await dispatch(model, preset.effort);
    if (applied !== true) fail('Codex did not confirm the model change.');
  }
  let stable = 0;
  for (let attempt = 0; attempt < 40; attempt++) {
    const active = ensureActive();
    if (active.props.model === model && active.props.reasoningEffort === preset.effort) {
      if (++stable >= 3) return { model, displayName: option.model.displayName ?? model, effort: preset.effort, changed };
    } else stable = 0;
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  fail('Codex accepted the update, but its composer did not retain the full preset.');
}

// Model-only Web Deck state. No transcript, messages, pending approvals or
// arbitrary runtime properties are returned to the paired device.
function readCodexDeck() {
  const { locate, identityFor } = codexComposerRuntime();
  const composer = locate();
  const targetID = identityFor(composer);
  if (typeof targetID !== 'string' || !targetID.length) {
    throw new Error('Open a saved Codex chat before using Web Deck.');
  }
  const { model, reasoningEffort: effort } = composer.props;
  if (typeof model !== 'string' || !model.length || typeof effort !== 'string' || !effort.length) {
    throw new Error('Codex is still loading its model selection.');
  }
  const title = composer.owners.map(owner => owner.memoizedProps).find(props =>
    props?.conversationId === targetID && typeof props.title === 'string' && props.title.length)?.title;
  return { targetID, title: title ?? 'Current Codex chat', model, effort };
}
