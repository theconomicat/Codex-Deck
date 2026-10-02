(function () {
  "use strict";

  const POLL_INTERVAL = 5000;
  const effortLabels = { none: "None", minimal: "Minimal", low: "Low", medium: "Medium", high: "High", xhigh: "Extra High", max: "Max", ultra: "Ultra" };

  function modelLabel(model) {
    return String(model || "Model").replace(/^gpt-/i, "GPT-").replace(/-(astra|sol|luna|terra)$/i, (_, name) => " " + name[0].toUpperCase() + name.slice(1));
  }

  // Match PickerLabels.modelKey for read-only selected-state display.
  function modelIdentity(model) {
    return String(model || "").toLowerCase().replace(/[^\p{L}\p{N}]/gu, "").replace(/^gpt/, "");
  }

  function isPresetSelected(selection, preset) {
    const current = modelIdentity(selection?.model);
    return current !== "" && current === modelIdentity(preset.model) && selection.effort === preset.effort;
  }

  function consumePairingToken(location, history) {
    const token = new URLSearchParams(location.hash.slice(1)).get("pair");
    if (location.hash) history.replaceState(null, "", location.pathname + location.search);
    return token;
  }

  class DeckController {
    constructor({ fetch, onChange, isVisible = () => true,
      schedule = (callback, delay) => setTimeout(callback, delay),
      cancel = timer => clearTimeout(timer) }) {
      this.fetch = fetch;
      this.onChange = onChange;
      this.isVisible = isVisible;
      this.schedule = schedule;
      this.cancel = cancel;
      this.csrf = null;
      this.timer = null;
      this.readPromise = null;
      this.stopped = false;
      this.state = { phase: "loading", snapshot: null, busy: false, applyingSlot: null, feedback: null };
    }

    emit() { this.onChange(this.state); }

    async request(path, body) {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 12000);
      try {
        const headers = { Accept: "application/json" };
        if (body !== undefined) {
          headers["Content-Type"] = "application/json";
          if (this.csrf) headers["X-Deck-CSRF"] = this.csrf;
        }
        const response = await this.fetch(path, {
          method: body === undefined ? "GET" : "POST", headers,
          credentials: "same-origin", cache: "no-store", signal: controller.signal,
          ...(body === undefined ? {} : { body: JSON.stringify(body) })
        });
        const payload = await response.json();
        if (!response.ok) {
          const error = new Error(payload.error || "The Mac could not complete this request.");
          error.status = response.status;
          throw error;
        }
        return payload;
      } catch (error) {
        if (error.name === "AbortError") throw new Error("The Mac did not respond in time. Check the current model before trying again.");
        throw error;
      } finally {
        clearTimeout(timeout);
      }
    }

    clearTimer() {
      if (this.timer !== null) this.cancel(this.timer);
      this.timer = null;
    }

    scheduleRefresh() {
      this.clearTimer();
      if (this.stopped || !this.isVisible() || this.state.phase === "pairing" || this.state.busy) return;
      this.timer = this.schedule(() => { this.timer = null; void this.refresh(); }, POLL_INTERVAL);
    }

    setError(error, action = false) {
      if (error.status === 401) {
        this.csrf = null;
        this.state.snapshot = null;
        this.state.phase = "pairing";
        this.clearTimer();
      } else if (!error.status) {
        this.state.phase = "offline";
      }
      this.state.feedback = {
        tone: "error",
        source: action ? "action" : "connection",
        message: error.status === 401 ? "This device is not paired. Open a fresh pairing link from your Mac."
          : error.status === 409 ? (error.message + " Refresh the deck and review the active chat before trying again.")
          : error.message || (action ? "The result could not be confirmed. Check your Mac before retrying." : "Cannot reach your Mac. Keep Codex-Usage running and use the same Wi-Fi.")
      };
    }

    async start(token) {
      this.emit();
      if (token) {
        this.state.busy = true;
        this.emit();
        try {
          const result = await this.request("/api/pair", { token });
          this.csrf = result.csrf;
        } catch (error) {
          this.setError(error);
          this.state.phase = "pairing";
          this.state.busy = false;
          this.emit();
          return;
        }
        this.state.busy = false;
      }
      await this.refresh();
    }

    refresh() {
      if (this.readPromise) return this.readPromise;
      if (this.stopped || this.state.busy || !this.isVisible()) return Promise.resolve();
      this.clearTimer();
      this.readPromise = (async () => {
        try {
          const snapshot = await this.request("/api/state");
          if (!Array.isArray(snapshot.presets) || typeof snapshot.csrf !== "string") throw new Error("The Mac returned an unreadable state. Refresh to try again.");
          const previousTarget = this.state.snapshot?.target?.id;
          this.csrf = snapshot.csrf;
          this.state.snapshot = snapshot;
          this.state.phase = snapshot.connected ? "ready" : "unavailable";
          if (this.state.feedback?.source === "connection") this.state.feedback = null;
          if (previousTarget && previousTarget !== snapshot.target?.id) {
            this.state.feedback = { tone: "info", message: "The active chat changed. Open Usage to review the target chat." };
          }
        } catch (error) {
          this.setError(error);
        } finally {
          this.readPromise = null;
          this.emit();
          this.scheduleRefresh();
        }
      })();
      return this.readPromise;
    }

    canApply() {
      return this.state.phase === "ready" && !!this.state.snapshot?.target?.id && !this.state.busy && !this.state.snapshot?.busy;
    }

    async applyPreset(preset) {
      if (!this.canApply()) return false;
      const targetID = this.state.snapshot.target.id;
      const expected = { slot: preset.slot, model: preset.model, effort: preset.effort };
      this.state.busy = true;
      this.state.applyingSlot = preset.slot;
      this.state.feedback = null;
      this.clearTimer();
      this.emit();
      try {
        // Finish a poll first, then check that this key still belongs to the displayed chat.
        if (this.readPromise) await this.readPromise;
        const current = this.state.snapshot?.presets.find(item => item.slot === expected.slot);
        if (this.state.phase !== "ready" || this.state.snapshot?.busy || this.state.snapshot?.target?.id !== targetID || current?.model !== expected.model || current?.effort !== expected.effort) {
          const error = new Error("The active chat or preset changed.");
          error.status = 409;
          throw error;
        }
        const result = await this.request("/api/preset", { ...expected, targetID });
        if (result.ok !== true) throw new Error(result.error || "The model change could not be confirmed. Check your Mac before retrying.");
        this.state.feedback = { tone: "success", message: result.message || `${modelLabel(preset.model)} · ${effortLabels[preset.effort] || preset.effort} applied.` };
        return true;
      } catch (error) {
        this.setError(error, true);
        return false;
      } finally {
        this.state.busy = false;
        this.state.applyingSlot = null;
        this.emit();
        if (this.state.phase !== "pairing") await this.refresh();
      }
    }

    async control(action) {
      if (!this.canApply()) return false;
      const targetID = this.state.snapshot.target.id;
      // Capture the exact reviewed request before allowing an in-flight poll to finish.
      const expected = JSON.parse(JSON.stringify(action));
      this.state.busy = true;
      this.state.feedback = null;
      this.clearTimer();
      this.emit();
      try {
        if (this.readPromise) await this.readPromise;
        if (this.state.phase !== "ready" || this.state.snapshot?.busy || this.state.snapshot?.target?.id !== targetID || !validControl(expected, this.state.snapshot)) {
          const error = new Error("The active chat, model, or waiting request changed.");
          error.status = 409;
          throw error;
        }
        const result = await this.request("/api/control", { ...expected, targetID });
        if (result.ok !== true) throw new Error(result.error || "The action could not be confirmed. Check your Mac before retrying.");
        this.state.feedback = { tone: "success", message: result.message || "Applied." };
        return true;
      } catch (error) {
        this.setError(error, true);
        return false;
      } finally {
        this.state.busy = false;
        this.emit();
        if (this.state.phase !== "pairing") await this.refresh();
      }
    }

    async logout() {
      if (this.state.busy || !this.csrf) return;
      if (this.state.snapshot?.dictation?.recording && this.state.snapshot.dictation.owned) {
        this.state.feedback = { tone: "error", source: "action", message: "Stop Mac dictation before disconnecting." };
        this.emit();
        return;
      }
      this.state.busy = true;
      this.clearTimer();
      this.emit();
      try {
        if (this.readPromise) await this.readPromise;
        await this.request("/api/logout", {});
        this.csrf = null;
        this.state.snapshot = null;
        this.state.phase = "pairing";
        this.state.feedback = { tone: "info", message: "This device is disconnected. Open a new pairing link to reconnect." };
      } catch (error) {
        this.setError(error, true);
      } finally {
        this.state.busy = false;
        this.emit();
        this.scheduleRefresh();
      }
    }

    visibilityChanged() {
      this.clearTimer();
      if (this.isVisible() && this.state.phase !== "pairing") void this.refresh();
    }

    stop() { this.stopped = true; this.clearTimer(); }
  }

  function usagePercent(meter, now = Date.now()) {
    const value = meter?.remainingPercent;
    if (typeof value !== "number" || !Number.isFinite(value) || value < 0 || value > 100) return null;
    if (typeof meter.resetsAt === "number" && meter.resetsAt * 1000 <= now) return null;
    return value;
  }

  function validControl(action, snapshot) {
    if (action.type === "model") {
      const model = snapshot.models?.find(item => item.id === action.model);
      return !!model && model.efforts.includes(action.effort);
    }
    if (action.type === "dictation") return snapshot.dictation?.available === true && typeof action.recording === "boolean" && action.recording !== snapshot.dictation.recording && (action.recording || snapshot.dictation.owned === true);
    const pending = snapshot.pending?.find(item => item.id === action.id && item.fingerprint === action.fingerprint && item.kind === action.type);
    if (!pending) return false;
    if (action.type === "approval") return pending.choices?.some(choice => choice.id === action.decision) === true;
    if (action.type !== "question" || !Array.isArray(action.answers) || action.answers.length !== pending.questions?.length) return false;
    return pending.questions.every(question => {
      const matches = action.answers.filter(answer => answer.id === question.id);
      if (matches.length !== 1) return false;
      const answer = matches[0];
      if (answer.optionID) return question.options?.some(option => option.id === answer.optionID) === true && !answer.text;
      return (question.allowOther === true || !question.options?.length) && typeof answer.text === "string" && answer.text.trim().length > 0 && new TextEncoder().encode(answer.text).length <= 8000;
    });
  }

  // Media playback starts synchronously inside the gesture. Unlike a muted old
  // preference or Web Audio-only click, this uses the browser's media channel.
  function pressFeedback(window) {
    let media, audio, suspendTimer;
    try { media = new window.Audio("/click.wav"); media.preload = "auto"; media.volume = 0.75; } catch (_) {}
    const fallback = () => {
      const AudioContext = window.AudioContext || window.webkitAudioContext;
      if (!AudioContext) return;
      try {
        audio ||= new AudioContext();
        clearTimeout(suspendTimer);
        void audio.resume().then(() => {
          const oscillator = audio.createOscillator();
          const gain = audio.createGain();
          const now = audio.currentTime;
          oscillator.type = "triangle";
          oscillator.frequency.setValueAtTime(900, now);
          oscillator.frequency.exponentialRampToValueAtTime(250, now + 0.045);
          gain.gain.setValueAtTime(0.2, now);
          gain.gain.exponentialRampToValueAtTime(0.001, now + 0.055);
          oscillator.connect(gain); gain.connect(audio.destination);
          oscillator.start(now); oscillator.stop(now + 0.06);
          oscillator.onended = () => { oscillator.disconnect(); gain.disconnect(); };
          suspendTimer = setTimeout(() => { void audio.suspend().catch(() => {}); }, 100);
        }).catch(() => {});
      } catch (_) {}
    };
    return {
      play() {
        try { window.navigator.vibrate?.(12); } catch (_) {}
        if (!media) { fallback(); return; }
        try { media.currentTime = 0; const playing = media.play(); playing?.catch(fallback); }
        catch (_) { fallback(); }
      },
      suspend() { if (media) media.pause(); if (audio) void audio.suspend().catch(() => {}); }
    };
  }

  function mount(document, controller) {
    const byID = id => document.getElementById(id);
    const grid = byID("presets");
    const usageKey = byID("usage-key");
    const controls = byID("controls");
    const tactile = pressFeedback(document.defaultView);
    let presetSignature = "";
    let dismissedNotice = "";
    let keys = [];
    let catalogSignature = "";
    let requestSignature = "";
    let dialDragging = false;
    let lastEffort = "";
    const modelSelect = byID("model-select");
    const effortRange = byID("effort-range");
    const modelDialog = byID("model-controls");
    const requestsDialog = byID("requests");
    const element = (tag, className, text) => {
      const node = document.createElement(tag);
      node.className = className;
      if (text !== undefined) node.textContent = text;
      return node;
    };
    const selectedModel = () => controller.state.snapshot?.models?.find(model => model.id === modelSelect.value);
    const selectedEffort = () => selectedModel()?.efforts[Number(effortRange.value)];
    const updateDial = () => {
      const efforts = selectedModel()?.efforts || [];
      const value = selectedEffort();
      byID("effort-value").textContent = effortLabels[value] || value || "—";
      effortRange.setAttribute("aria-valuetext", effortLabels[value] || value || "Unavailable");
      byID("effort-min").textContent = effortLabels[efforts[0]] || efforts[0] || "";
      byID("effort-max").textContent = effortLabels[efforts.at(-1)] || efforts.at(-1) || "";
      const angle = efforts.length > 1 ? -135 + 270 * Number(effortRange.value) / (efforts.length - 1) : 0;
      byID("dial-indicator").setAttribute("transform", `rotate(${angle} 80 80)`);
    };
    const configureEffort = preferred => {
      const efforts = selectedModel()?.efforts || [];
      effortRange.max = String(Math.max(0, efforts.length - 1));
      effortRange.value = String(Math.max(0, efforts.indexOf(efforts.includes(preferred) ? preferred : efforts.includes("high") ? "high" : efforts[0])));
      lastEffort = selectedEffort();
      updateDial();
    };
    const applyModel = () => {
      const model = selectedModel();
      const effort = selectedEffort();
      if (!model || !effort || !controller.canApply()) return;
      if (isPresetSelected(controller.state.snapshot?.selection, { model: model.id, effort })) return;
      void controller.control({ type: "model", model: model.id, effort });
    };
    const renderRequests = state => {
      const pending = state.snapshot?.pending || [];
      const signature = JSON.stringify([state.snapshot?.target?.id, pending]);
      if (signature !== requestSignature) {
        requestSignature = signature;
        const content = byID("requests-content");
        content.replaceChildren();
        if (!pending.length) content.append(element("p", "secondary", "No questions or access requests are waiting."));
        for (const request of pending) {
          const section = element("section", "request-item");
          section.append(element("h3", "", request.title));
          if (request.detail) section.append(element("p", "request-detail", request.detail));
          if (request.kind === "approval") {
            const actions = element("div", "request-actions");
            for (const choice of request.choices || []) {
              const button = element("button", `control-button ${choice.id === "approve" ? "approve" : "deny"}`, choice.label);
              button.type = "button";
              button.addEventListener("click", () => void controller.control({ type: "approval", id: request.id, fingerprint: request.fingerprint, decision: choice.id }));
              actions.append(button);
            }
            section.append(actions);
          } else if (request.kind === "question") {
            const form = document.createElement("form");
            const fields = [];
            for (const [index, question] of (request.questions || []).entries()) {
              const field = element("fieldset", "question-field");
              field.append(element("legend", "", question.prompt));
              const options = question.options || [];
              const radios = [];
              let text;
              const addOption = (id, label, description) => {
                const wrapper = element("label", "question-option");
                const radio = document.createElement("input");
                radio.type = "radio"; radio.name = `question-${index}`; radio.value = id; radio.required = true;
                const copy = element("span", "", label);
                if (description) copy.append(element("small", "", description));
                wrapper.append(radio, copy); field.append(wrapper); radios.push(radio);
                return radio;
              };
              for (const option of options) addOption(option.id, option.label, option.description);
              let other;
              if (question.allowOther && options.length) other = addOption("", "Other", "Write an answer to this question");
              if (!options.length || question.allowOther) {
                text = document.createElement(question.isSecret ? "input" : "textarea");
                if (question.isSecret) { text.type = "password"; text.autocomplete = "off"; }
                else text.rows = 3;
                text.className = "question-text"; text.maxLength = 8000;
                text.setAttribute("aria-label", `Answer: ${question.prompt}`);
                text.placeholder = "Your answer";
                text.hidden = !!options.length;
                text.required = !options.length;
                for (const radio of radios) radio.addEventListener("change", () => {
                  text.hidden = !other?.checked; text.required = !!other?.checked;
                  if (other?.checked) text.focus();
                });
                field.append(text);
              }
              fields.push({ question, radios, text });
              form.append(field);
            }
            const actions = element("div", "request-actions");
            const send = element("button", "control-button approve", "Send answers");
            send.type = "submit"; actions.append(send); form.append(actions);
            const error = element("p", "request-error"); error.hidden = true; error.setAttribute("role", "alert"); form.append(error);
            form.addEventListener("submit", event => {
              event.preventDefault();
              const answers = fields.map(({ question, radios, text }) => {
                const optionID = radios.find(radio => radio.checked)?.value;
                return optionID ? { id: question.id, optionID } : { id: question.id, text: text?.value.trim() || "" };
              });
              const action = { type: "question", id: request.id, fingerprint: request.fingerprint, answers };
              if (!validControl(action, controller.state.snapshot)) { error.textContent = "Answer every question, or refresh if this request changed."; error.hidden = false; return; }
              error.hidden = true;
              void controller.control(action);
            });
            section.append(form);
          }
          content.append(section);
        }
      }
      for (const control of byID("requests-content").querySelectorAll("button, input, textarea")) control.disabled = !controller.canApply();
      byID("request-target").textContent = state.snapshot?.target?.title || "";
      byID("controls-status").textContent = state.feedback?.tone === "error" ? state.feedback.message : "";
      byID("requests-status").textContent = state.busy ? "Sending…" : state.feedback?.tone === "error" ? state.feedback.message : "";
    };
    const render = state => {
      const { snapshot, phase, busy, feedback } = state;
      const pairing = phase === "pairing";
      byID("pairing").hidden = !pairing;
      document.querySelector(".remote").dataset.pairing = String(pairing);
      grid.hidden = pairing;
      byID("micro-dock").hidden = pairing;
      if (pairing) for (const dialog of [controls, modelDialog, requestsDialog]) if (dialog.open) dialog.close();
      byID("logout").hidden = !controller.csrf;
      byID("logout").disabled = busy;
      byID("refresh").disabled = busy;
      byID("retry-pairing").disabled = busy;
      byID("connection-label").textContent = { loading: "Connecting", pairing: "Not paired", ready: "Connected", unavailable: "Codex unavailable", offline: "Offline" }[phase];
      byID("target-title").textContent = snapshot?.target?.title || "Open a chat on your Mac";
      byID("usage-details").textContent = snapshot?.usage || "Usage unavailable";
      byID("pending-unavailable").textContent = snapshot?.pendingUnavailable || "";
      byID("pending-unavailable").hidden = !snapshot?.pendingUnavailable;
      const models = (snapshot?.models || []).filter(model => typeof model.id === "string" && Array.isArray(model.efforts) && model.efforts.length);
      const modelSignature = JSON.stringify(models);
      if (catalogSignature !== modelSignature) {
        catalogSignature = modelSignature;
        modelSelect.replaceChildren(...models.map(model => { const option = element("option", "", model.name || modelLabel(model.id)); option.value = model.id; return option; }));
      }
      if (!busy && !dialDragging) {
        const model = models.find(model => modelIdentity(model.id) === modelIdentity(snapshot?.selection?.model));
        if (model) modelSelect.value = model.id;
        configureEffort(snapshot?.selection?.effort);
      }
      byID("open-model").disabled = !controller.canApply() || !models.length;
      byID("model-control-label").textContent = snapshot?.selection?.model ? `${modelLabel(snapshot.selection.model)} · ${effortLabels[snapshot.selection.effort] || snapshot.selection.effort}` : "Model & effort";
      byID("open-model").setAttribute("aria-label", `Model & effort: ${byID("model-control-label").textContent}`);
      byID("open-model").title = byID("model-control-label").textContent;
      modelSelect.disabled = !controller.canApply() || !models.length;
      effortRange.disabled = modelSelect.disabled || (selectedModel()?.efforts.length || 0) < 2;
      byID("model-status").textContent = busy ? "Applying…" : feedback?.tone === "error" ? feedback.message : "Drag the dial or slider. Changes apply when you release.";
      const dictation = snapshot?.dictation;
      byID("dictation").disabled = !controller.canApply() || !dictation?.available || (dictation.recording && !dictation.owned);
      byID("dictation").setAttribute("aria-pressed", phase === "offline" ? "mixed" : String(dictation?.recording === true));
      byID("dictation").setAttribute("aria-label", phase === "offline" ? "Mac dictation status unknown" : dictation?.recording ? dictation.owned ? "Stop Mac dictation" : "Dictation is active on the Mac" : "Start Mac dictation");
      byID("dictation").title = phase === "offline" ? "Recording status unknown. Check your Mac." : dictation?.recording && !dictation.owned ? "Dictation was started on the Mac; stop it there" : dictation?.available ? "Uses the microphone connected to your Mac" : "Mac dictation is unavailable in the active chat";
      byID("dictation-label").textContent = phase === "offline" ? "Mic unknown" : dictation?.recording ? dictation.owned ? "Stop mic" : "Mic on Mac" : "Mac mic";
      const pendingCount = snapshot?.pending?.length || 0;
      byID("open-requests").hidden = !pendingCount;
      byID("open-requests").disabled = phase !== "ready";
      byID("requests-label").textContent = `${pendingCount} ${pendingCount === 1 ? "request" : "requests"}`;
      renderRequests(state);
      const percent = phase === "offline" ? null : usagePercent(snapshot?.usageMeter);
      const value = percent === null ? "—" : `${Math.round(percent)}%`;
      byID("usage-value").textContent = value;
      byID("usage-ring").setAttribute("stroke-dasharray", `${percent ?? 0} 100`);
      usageKey.dataset.level = percent === null ? "unknown" : percent < 10 ? "low" : percent < 25 ? "medium" : "normal";
      usageKey.setAttribute("aria-label", `${percent === null ? "Usage unavailable" : `${value} remaining`}. Open deck controls`);
      let message = feedback?.tone !== "success" ? feedback?.message : "";
      if (!message && phase === "offline") message = "Connection lost. Reconnecting…";
      if (!message && phase === "unavailable") message = snapshot?.message || "Open a Codex chat and enable Direct Switching on your Mac.";
      byID("notice").hidden = !message || message === dismissedNotice;
      byID("notice").dataset.tone = feedback?.tone || "info";
      byID("notice-text").textContent = message || "";
      byID("feedback").textContent = feedback?.message || message || "";
      const presets = (snapshot?.presets || []).slice(0, 5);
      const signature = JSON.stringify(presets);
      if (signature !== presetSignature) {
        presetSignature = signature;
        keys = presets.map(preset => {
          const button = element("button", "deck-key model-key");
          button.type = "button";
          const top = element("span", "key-top");
          const status = element("span", "sr-only");
          const led = element("span", "key-led");
          led.setAttribute("aria-hidden", "true");
          top.append(element("span", "key-number", String(preset.slot).padStart(2, "0")), led, status);
          const name = modelLabel(preset.model);
          const effort = effortLabels[preset.effort] || preset.effort;
          button.append(top, element("span", "key-model", name), element("span", "key-effort", effort));
          button.setAttribute("aria-label", `${preset.slot}: ${preset.title || `${name}, ${effort}`}`);
          button.addEventListener("click", () => void controller.applyPreset(preset));
          return { button, status, preset };
        });
        grid.replaceChildren(...keys.map(key => key.button), usageKey);
      }
      for (const { button, status, preset } of keys) {
        const selected = phase === "ready" && isPresetSelected(snapshot?.selection, preset);
        const applying = state.applyingSlot === preset.slot;
        button.disabled = !controller.canApply();
        button.setAttribute("aria-pressed", String(selected));
        button.setAttribute("aria-busy", String(applying));
        status.textContent = applying ? "Applying…" : selected ? "Selected" : "";
      }
      grid.setAttribute("aria-busy", String(phase === "loading" || busy));
    };
    document.addEventListener("click", event => {
      const button = event.target.closest?.("button, input[type=radio]");
      if (button && !button.disabled) tactile.play();
    }, true);
    document.addEventListener("pointerdown", () => { document.documentElement.dataset.input = "pointer"; }, true);
    document.addEventListener("keydown", () => { document.documentElement.dataset.input = "keyboard"; }, true);
    usageKey.addEventListener("click", () => controls.showModal());
    byID("close-controls").addEventListener("click", () => controls.close());
    for (const button of document.querySelectorAll("[data-close]")) button.addEventListener("click", () => byID(button.dataset.close).close());
    byID("open-model").addEventListener("click", () => modelDialog.showModal());
    byID("open-requests").addEventListener("click", () => requestsDialog.showModal());
    byID("dictation").addEventListener("click", () => void controller.control({ type: "dictation", recording: !controller.state.snapshot?.dictation?.recording }));
    modelSelect.addEventListener("change", () => { tactile.play(); configureEffort(controller.state.snapshot?.selection?.effort); applyModel(); });
    effortRange.addEventListener("input", () => {
      if (selectedEffort() !== lastEffort) { tactile.play(); lastEffort = selectedEffort(); }
      updateDial();
    });
    effortRange.addEventListener("pointerdown", () => { dialDragging = true; });
    effortRange.addEventListener("pointerup", () => { dialDragging = false; });
    effortRange.addEventListener("change", () => { dialDragging = false; applyModel(); });
    effortRange.addEventListener("pointercancel", () => { dialDragging = false; render(controller.state); });
    const dial = byID("effort-dial");
    const turnDial = event => {
      const rect = dial.getBoundingClientRect();
      const angle = Math.atan2(event.clientX - rect.left - rect.width / 2, -(event.clientY - rect.top - rect.height / 2)) * 180 / Math.PI;
      const count = selectedModel()?.efforts.length || 0;
      const value = Math.round((Math.max(-135, Math.min(135, angle)) + 135) / 270 * Math.max(0, count - 1));
      effortRange.value = String(value);
      if (selectedEffort() !== lastEffort) { tactile.play(); lastEffort = selectedEffort(); }
      updateDial();
    };
    dial.addEventListener("pointerdown", event => {
      if (effortRange.disabled) return;
      event.preventDefault(); dialDragging = true; dial.setPointerCapture(event.pointerId); turnDial(event);
    });
    dial.addEventListener("pointermove", event => { if (dialDragging && dial.hasPointerCapture(event.pointerId)) turnDial(event); });
    dial.addEventListener("pointerup", event => {
      if (!dial.hasPointerCapture(event.pointerId)) return;
      turnDial(event); dialDragging = false; dial.releasePointerCapture(event.pointerId); applyModel();
    });
    dial.addEventListener("pointercancel", () => { dialDragging = false; render(controller.state); });
    byID("fullscreen").addEventListener("click", async () => {
      const help = byID("fullscreen-help");
      if (!document.fullscreenEnabled) {
        help.textContent = "Full screen is unavailable in this browser. On iPhone, use Safari’s Share → Add to Home Screen, then open the saved deck. Rotate your device for landscape.";
        help.hidden = false;
        return;
      }
      try {
        if (document.fullscreenElement) await document.exitFullscreen();
        else await document.documentElement.requestFullscreen();
        controls.close();
      } catch (_) { help.textContent = "Full screen could not open. Try your browser’s full-screen control."; help.hidden = false; }
    });
    document.addEventListener("fullscreenchange", () => {
      byID("fullscreen").textContent = document.fullscreenElement ? "Exit full screen" : "Enter full screen";
    });
    byID("dismiss-notice").addEventListener("click", () => { dismissedNotice = byID("notice-text").textContent; byID("notice").hidden = true; });
    byID("refresh").addEventListener("click", () => { dismissedNotice = ""; void controller.refresh(); });
    byID("retry-pairing").addEventListener("click", () => { dismissedNotice = ""; void controller.refresh(); });
    byID("logout").addEventListener("click", () => void controller.logout());
    document.addEventListener("visibilitychange", () => {
      if (document.hidden) tactile.suspend();
      controller.visibilityChanged();
    });
    document.addEventListener("keydown", event => {
      if (event.repeat || event.altKey || event.ctrlKey || event.metaKey || event.shiftKey || !grid.contains(event.target)) return;
      const key = keys.find(item => String(item.preset.slot) === event.key);
      if (key && !key.button.disabled) { event.preventDefault(); key.button.click(); }
    });
    return render;
  }

  if (typeof module !== "undefined" && module.exports) {
    module.exports = { validControl, pressFeedback, DeckController, consumePairingToken, modelLabel, isPresetSelected, usagePercent, POLL_INTERVAL };
  } else {
    const token = consumePairingToken(window.location, window.history);
    let render = () => {};
    const controller = new DeckController({ fetch: window.fetch.bind(window), onChange: state => render(state), isVisible: () => !document.hidden });
    render = mount(document, controller);
    window.addEventListener("pagehide", () => controller.stop());
    window.addEventListener("pageshow", event => { if (event.persisted) { controller.stopped = false; controller.visibilityChanged(); } });
    void controller.start(token);
  }
})();
