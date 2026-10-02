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
            this.state.feedback = { tone: "info", message: "The active chat changed. Presets now apply to the chat shown above." };
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

    async logout() {
      if (this.state.busy || !this.csrf) return;
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

  function mount(document, controller) {
    const byID = id => document.getElementById(id);
    const grid = byID("presets");
    let presetSignature = "";
    let keys = [];
    const element = (tag, className, text) => {
      const node = document.createElement(tag);
      node.className = className;
      if (text !== undefined) node.textContent = text;
      return node;
    };
    const render = state => {
      const { snapshot, phase, busy, feedback } = state;
      const pairing = phase === "pairing";
      byID("pairing").hidden = !pairing;
      byID("deck-content").hidden = pairing;
      byID("logout").hidden = !controller.csrf;
      byID("logout").disabled = busy;
      byID("refresh").disabled = busy;
      byID("retry-pairing").disabled = busy;
      byID("connection").dataset.state = phase;
      byID("connection-label").textContent = { loading: "Connecting", pairing: "Not paired", ready: "Connected", unavailable: "Codex unavailable", offline: "Offline" }[phase];
      byID("target-title").textContent = snapshot?.target?.title || (phase === "loading" ? "Waiting for Codex…" : "Open a chat on your Mac");
      byID("target-title").title = snapshot?.target?.title || "";
      byID("usage").textContent = snapshot?.usage?.replace(/^Usage\s*·\s*/, "") || "Usage unavailable";
      byID("feedback").hidden = !feedback;
      byID("feedback").dataset.tone = feedback?.tone || "info";
      byID("feedback").textContent = feedback?.message || "";
      const presets = snapshot?.presets || [];
      const signature = JSON.stringify(presets);
      if (signature !== presetSignature) {
        presetSignature = signature;
        keys = presets.map(preset => {
          const button = element("button", "deck-key");
          button.type = "button";
          const top = element("span", "key-top");
          const status = element("span", "key-status");
          top.append(element("span", "key-number", String(preset.slot).padStart(2, "0")), status);
          const name = modelLabel(preset.model);
          const effort = effortLabels[preset.effort] || preset.effort;
          button.append(top, element("span", "key-model", name), element("span", "key-effort", effort));
          button.setAttribute("aria-label", `${preset.slot}: ${preset.title || `${name}, ${effort}`}`);
          button.addEventListener("click", () => void controller.applyPreset(preset));
          return { button, status, preset };
        });
        grid.replaceChildren(...keys.map(key => key.button));
      }
      for (const { button, status, preset } of keys) {
        const selected = isPresetSelected(snapshot?.selection, preset);
        const applying = state.applyingSlot === preset.slot;
        button.disabled = !controller.canApply();
        button.setAttribute("aria-pressed", String(selected));
        button.setAttribute("aria-busy", String(applying));
        status.textContent = applying ? "Applying…" : selected ? "Selected" : "";
      }
      grid.setAttribute("aria-busy", String(phase === "loading" || busy));
      byID("deck-hint").textContent = busy ? "Waiting for confirmation from your Mac…"
        : snapshot?.busy ? "A change is in progress on your Mac. Please wait."
        : phase === "offline" ? "Connection lost. Reconnecting while this page is open…"
        : snapshot?.message || (controller.canApply() ? "Tap a key to change the active chat. Focus a key to use 1–5." : "Open a Codex chat and enable Direct Switching on your Mac.");
    };
    byID("refresh").addEventListener("click", () => void controller.refresh());
    byID("retry-pairing").addEventListener("click", () => void controller.refresh());
    byID("logout").addEventListener("click", () => void controller.logout());
    document.addEventListener("visibilitychange", () => controller.visibilityChanged());
    document.addEventListener("pointerdown", () => { document.documentElement.dataset.input = "pointer"; });
    document.addEventListener("keydown", event => {
      document.documentElement.dataset.input = "keyboard";
      if (event.repeat || event.altKey || event.ctrlKey || event.metaKey || event.shiftKey || !grid.contains(event.target)) return;
      const key = keys.find(item => String(item.preset.slot) === event.key);
      if (key && !key.button.disabled) { event.preventDefault(); key.button.click(); }
    });
    return render;
  }

  if (typeof module !== "undefined" && module.exports) {
    module.exports = { DeckController, consumePairingToken, modelLabel, isPresetSelected, POLL_INTERVAL };
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
