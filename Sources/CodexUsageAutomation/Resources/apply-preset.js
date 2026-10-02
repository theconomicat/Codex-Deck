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
  return { locate, dispatcherFor, identityFor, currentRoot };
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

// Only the current saved composer's catalog, dictation controls and its
// currently mounted approval/question are exposed. Never read chat messages.
function codexDeckRuntime() {
  const runtime = codexComposerRuntime();
  const composer = runtime.locate();
  const targetID = runtime.identityFor(composer);
  const route = location.href;
  if (typeof targetID !== 'string' || !targetID.length) throw new Error('Open a saved Codex chat before using Web Deck.');
  const ensureActive = () => {
    const active = runtime.locate();
    if (location.href !== route || runtime.identityFor(active) !== targetID) {
      throw new Error('The selected Web Deck chat is no longer active. Refresh and select it again.');
    }
    return active;
  };
  const walk = (start, visit) => {
    const stack = [start], seen = new Set();
    while (stack.length) {
      const node = stack.pop();
      if (!node || seen.has(node)) continue;
      if (seen.size >= 100000) throw new Error('The Codex control search reached its limit.');
      seen.add(node);
      visit(node);
      // A subtree walk must not visit its root's siblings.
      for (let child = node.child; child; child = child.sibling) {
        stack.push(child);
        if (stack.length > 100000) throw new Error('The Codex control search reached its limit.');
      }
    }
  };
  const visible = node => {
    const element = node.stateNode;
    return element?.isConnected === true && typeof element.getClientRects === 'function' &&
      element.getClientRects().length > 0 &&
      !element.closest?.('[hidden], [inert], [aria-hidden="true"], [data-app-shell-active-page="false"]') &&
      element.checkVisibility?.({ checkOpacity: true, checkVisibilityCSS: true }) !== false;
  };
  const dictation = active => {
    const candidates = active.owners.filter(owner => owner.memoizedProps?.voiceControls);
    if (candidates.length !== 1) {
      if (globalThis.__codexUsageDeckDictation?.targetID === targetID) delete globalThis.__codexUsageDeckDictation;
      return { state: { available: false, recording: false, owned: false } };
    }
    const props = candidates[0].memoizedProps, voice = props.voiceControls;
    const recording = voice.isDictating === true;
    const ownership = globalThis.__codexUsageDeckDictation;
    const sameRecording = ownership?.targetID === targetID && ownership.start === voice.startDictation && ownership.stop === voice.stopDictation;
    if (ownership?.targetID === targetID && (!sameRecording || (!recording && !voice.isDictationStarting && !ownership.starting))) {
      delete globalThis.__codexUsageDeckDictation;
    }
    const owned = !!sameRecording && (recording || ownership.starting);
    const controls = [];
    walk(candidates[0], node => {
      const control = node.memoizedProps;
      if (typeof control?.startDictation === 'function' && control.stopDictation === voice.stopDictation &&
          Object.hasOwn(control, 'isVisible') && Object.hasOwn(control, 'disabled')) {
        let mounted = false;
        walk(node, child => { if (visible(child)) mounted = true; });
        if (mounted && !controls.includes(control)) controls.push(control);
      }
    });
    const nativeControl = controls.length === 1 ? controls[0] : null;
    const available = ((recording && owned) || (nativeControl?.isVisible === true && !nativeControl.disabled && voice.isDictationButtonVisible === true)) &&
      typeof voice.startDictation === 'function' && typeof voice.stopDictation === 'function' &&
      voice.isDictationSupported === true &&
      !props.isInteractionBlocked && props.interactionsEnabled !== false &&
      !voice.isDictationStarting && !voice.isTranscribing && (!voice.isMicrophoneBusy || recording) &&
      (voice.realtimeSession?.thread?.phase ?? 'inactive') === 'inactive';
    return { state: { available, recording, owned }, voice, nativeControl };
  };
  const pending = () => {
    const owners = [];
    walk(runtime.currentRoot(), node => {
      const props = node.memoizedProps;
      if (props?.conversationId !== targetID || !props.pendingRequest?.type) return;
      let mounted = false;
      walk(node, child => { if (visible(child)) mounted = true; });
      if (mounted) owners.push(node);
    });
    // The root panel and its specialized child can share the same pendingRequest.
    const entries = new Map(), ids = new Set();
    let unavailable;
    for (const owner of owners) {
      const request = owner.memoizedProps.pendingRequest;
      // The permission panel receives the normalized item too; its enclosing
      // pendingRequest is the identity-bearing request, not a second request.
      if (owners.some(parent => parent !== owner && parent.memoizedProps.pendingRequest?.type === 'permissionRequest' &&
          parent.memoizedProps.pendingRequest.item === request)) continue;
      if (!['userInput', 'approval', 'permissionRequest'].includes(request.type)) {
        unavailable = 'This request must be answered in Codex.';
        continue;
      }
      const item = request.item;
      if (!item || request.environmentInput != null || request.isOnboardingDynamicInput) {
        unavailable = 'This request must be answered in Codex.';
        continue;
      }
      const nativeID = request.type === 'approval' ? item.approvalRequestId : item.requestId;
      if (!(typeof nativeID === 'string' && nativeID.length > 0) && !Number.isSafeInteger(nativeID)) {
        unavailable = 'This request has an unsupported identity. Answer it in Codex.';
        continue;
      }
      const id = `${request.type}:${typeof nativeID}:${String(nativeID)}`;
      ids.add(id);
      let data, submit, binding;
      if (request.type === 'userInput') {
        if (!Array.isArray(item.questions) || !item.questions.length || item.questions.length > 12) {
          unavailable = 'This question set must be answered in Codex.';
          continue;
        }
        // Codex's C6r/T6r adapters normalize public options:null/missing to [].
        // Its mounted Gr/Zr callbacks require arrays, so do not invent a shape
        // that the bound submit callback itself cannot consume.
        const valid = item.questions.every(question => typeof question?.id === 'string' && question.id.length > 0 &&
          typeof question.question === 'string' && question.question.length > 0 && Array.isArray(question.options) &&
          question.options.every(option => typeof option?.label === 'string' && option.label.length > 0 &&
            (option.description == null || typeof option.description === 'string')) &&
          new Set(question.options.map(option => option.label)).size === question.options.length &&
          (question.isOther == null || typeof question.isOther === 'boolean') &&
          (question.isSecret == null || typeof question.isSecret === 'boolean'));
        if (!valid || new Set(item.questions.map(question => question.id)).size !== item.questions.length) {
          unavailable = 'This question has an unsupported format. Answer it in Codex.';
          continue;
        }
        const callbacks = new Set();
        walk(owner, node => {
          const props = node.memoizedProps;
          if (Array.isArray(props?.questionAndOptions) && typeof props.onSubmit === 'function' &&
              /\.replyWithUserInputResponse\s*\(/.test(Function.prototype.toString.call(props.onSubmit))) callbacks.add(props.onSubmit);
        });
        if (callbacks.size !== 1) { unavailable = 'This question cannot be answered remotely in this Codex version.'; continue; }
        submit = [...callbacks][0];
        binding = [submit];
        data = { id, kind: 'question', title: 'Codex needs your answer', detail: '',
          questions: item.questions.map(question => ({ id: question.id, prompt: question.question,
            isSecret: question.isSecret === true, allowOther: question.isOther === true || question.options.length === 0,
            options: question.options.map(option => ({ id: option.label, label: option.label, description: option.description ?? '' })) })) };
      } else {
        const actions = [];
        walk(owner, node => {
          const candidate = node.memoizedProps?.actions;
          if (typeof candidate?.onApprove === 'function' && typeof candidate.onDeny === 'function' &&
              !actions.some(action => action.onApprove === candidate.onApprove && action.onDeny === candidate.onDeny)) actions.push(candidate);
        });
        if (actions.length !== 1) { unavailable = 'This approval cannot be answered remotely in this Codex version.'; continue; }
        binding = [actions[0].onApprove, actions[0].onDeny];
        submit = decision => decision === 'approve' ? actions[0].onApprove() : actions[0].onDeny();
        let title, detail;
        if (request.type === 'permissionRequest') {
          if (!item.permissions || typeof item.permissions !== 'object' || Array.isArray(item.permissions)) {
            unavailable = 'These permissions must be reviewed in Codex.';
            continue;
          }
          title = item.reason || 'Allow these permissions for this turn?';
          detail = JSON.stringify(item.permissions, null, 2);
        } else if (item.type === 'exec' && Array.isArray(item.cmd) && item.cmd.every(part => typeof part === 'string')) {
          title = item.approvalReason || 'Allow this command?';
          detail = JSON.stringify({ command: item.cmd, cwd: item.cwd ?? null, network: item.networkApprovalContext ?? null,
            proposedNetworkPolicyAmendments: item.proposedNetworkPolicyAmendments ?? null,
            proposedExecpolicyAmendment: item.proposedExecpolicyAmendment ?? null }, null, 2);
        } else if (item.type === 'patch' && item.changes && typeof item.changes === 'object') {
          title = 'Allow these file changes?';
          detail = JSON.stringify({ changes: item.changes, grantRoot: item.grantRoot ?? null,
            visualizationActivities: item.visualizationActivities ?? [] }, null, 2);
        } else { unavailable = 'This approval must be reviewed in Codex.'; continue; }
        data = { id, kind: 'approval', title, detail,
          choices: [{ id: 'approve', label: 'Allow once' }, { id: 'deny', label: 'Deny' }] };
      }
      // The exact displayed request is the concurrency token. Do not truncate
      // commands or permissions: oversized requests must be reviewed on the Mac.
      const fingerprint = JSON.stringify({ request: data, hostID: owner.memoizedProps.hostId ?? null });
      if (new TextEncoder().encode(fingerprint).length > 10000) {
        unavailable = 'This request is too large to review here. Open it in Codex.';
        continue;
      }
      const entry = { data: { ...data, fingerprint }, submit, binding };
      const previous = entries.get(id);
      if (previous && (previous.data.fingerprint !== fingerprint ||
          previous.binding.some((callback, index) => callback !== binding[index]))) {
        throw new Error('Several different pending requests share the same identity.');
      }
      entries.set(id, entry);
    }
    return { entries, ids, unavailable };
  };
  return { composer, targetID, ensureActive, dictation, pending };
}

function readCodexDeck() {
  const { composer, targetID, dictation, pending } = codexDeckRuntime();
  const { model, reasoningEffort: effort } = composer.props;
  if (typeof model !== 'string' || !model.length || typeof effort !== 'string' || !effort.length) {
    throw new Error('Codex is still loading its model selection.');
  }
  const title = composer.owners.map(owner => owner.memoizedProps).find(props =>
    props?.conversationId === targetID && typeof props.title === 'string' && props.title.length)?.title;
  const disabled = composer.props.disabled || composer.props.modelOptionsDisabled || composer.props.reasoningEffortDisabled ||
    composer.props.daybreak?.isSaving || composer.props.daybreak?.disabled;
  const models = disabled ? [] : (composer.props.modelOptions ?? []).filter(option => option.disabledReason == null &&
    option.model?.model !== composer.props.lockedModelSlug && typeof option.model?.model === 'string' &&
    Array.isArray(option.model.supportedReasoningEfforts)).map(option => ({
      id: option.model.model, name: option.model.displayName ?? option.model.model,
      efforts: option.model.supportedReasoningEfforts.map(level => level.reasoningEffort).filter(level => typeof level === 'string')
    }));
  const requests = pending();
  return { targetID, title: title ?? 'Current Codex chat', model, effort, models,
    dictation: dictation(composer).state, pending: [...requests.entries.values()].map(entry => entry.data),
    ...(requests.unavailable ? { pendingUnavailable: requests.unavailable } : {}) };
}

async function performCodexDeckAction(input) {
  const runtime = codexDeckRuntime();
  const fail = message => { throw new Error(message); };
  if (!input || input.targetID !== runtime.targetID) fail('The selected Web Deck chat is no longer active. Refresh and select it again.');
  if (input.type === 'model') {
    const result = await applyCodexPreset({ model: input.model, effort: input.effort }, input.targetID);
    return { ok: true, message: `${result.displayName} · ${result.effort}`, ...result };
  }
  if (input.type === 'dictation') {
    if (typeof input.recording !== 'boolean') fail('Invalid dictation action.');
    const control = runtime.dictation(runtime.ensureActive());
    if (!control.state.available) fail('Mac dictation is not available in this composer.');
    if (control.state.recording && !control.state.owned) fail('This recording was started in Codex. Stop it on the Mac.');
    let startedOwnership;
    if (control.state.recording !== input.recording) {
      // Native tap mode plus insert-only stop never sends the composer text.
      if (input.recording) {
        const ownership = { targetID: runtime.targetID, start: control.voice.startDictation, stop: control.voice.stopDictation, starting: true };
        startedOwnership = ownership;
        globalThis.__codexUsageDeckDictation = ownership;
        try { await control.nativeControl.startDictation('tap'); }
        catch (error) { if (globalThis.__codexUsageDeckDictation === ownership) delete globalThis.__codexUsageDeckDictation; throw error; }
      } else {
        await control.voice.stopDictation('insert');
        delete globalThis.__codexUsageDeckDictation;
      }
    }
    try {
      for (let attempt = 0; attempt < 60; attempt++) {
        const current = runtime.dictation(runtime.ensureActive()).state;
        if (current.recording === input.recording && (!input.recording || current.owned)) {
          return { ok: true, message: input.recording ? 'Mac microphone on.' : 'Recording stopped. Transcript stays in the Mac composer.' };
        }
        await new Promise(resolve => setTimeout(resolve, 50));
      }
      fail('Codex did not confirm the microphone state. Check microphone access on the Mac.');
    } finally {
      if (startedOwnership) startedOwnership.starting = false;
    }
  }
  if (!['approval', 'question'].includes(input.type) || typeof input.id !== 'string' || typeof input.fingerprint !== 'string') fail('Unsupported Web Deck action.');
  runtime.ensureActive();
  const entry = runtime.pending().entries.get(input.id);
  if (!entry || entry.data.kind !== input.type || entry.data.fingerprint !== input.fingerprint) fail('This request changed or was already answered. Refresh before responding.');
  let response;
  if (input.type === 'approval') {
    if (!['approve', 'deny'].includes(input.decision)) fail('Only allowing once or denying this request is supported.');
    response = input.decision;
  } else {
    if (!Array.isArray(input.answers) || input.answers.length !== entry.data.questions.length ||
        new Set(input.answers.map(answer => answer?.id)).size !== input.answers.length) fail('Answer each current question exactly once.');
    response = entry.data.questions.map(question => {
      const answer = input.answers.find(answer => answer?.id === question.id);
      if (!answer || Object.keys(answer).some(key => !['id', 'optionID', 'text'].includes(key))) fail('The answer does not match the current question.');
      if (answer.optionID != null) {
        if (typeof answer.optionID !== 'string' || !question.options.some(option => option.id === answer.optionID) ||
            (answer.text != null && answer.text !== '')) fail('Choose one of the current options, or provide a separate custom answer.');
        return { selectedOptionId: answer.optionID, freeformText: '' };
      }
      if (!question.allowOther || typeof answer.text !== 'string' || !answer.text.trim() || answer.text.length > 8000) fail('Enter a valid answer to the current question.');
      return { selectedOptionId: null, freeformText: answer.text.trim() };
    });
  }
  runtime.ensureActive();
  await entry.submit(response);
  // UI wrappers return void. Confirm that the exact pending request disappears
  // instead of claiming that merely calling a callback approved anything.
  for (let attempt = 0; attempt < 80; attempt++) {
    runtime.ensureActive();
    if (!runtime.pending().ids.has(input.id)) return { ok: true, message: input.type === 'approval' ? 'Response received by Codex.' : 'Answer received by Codex.' };
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  fail('Codex has not confirmed this response. Review the pending request on the Mac.');
}
