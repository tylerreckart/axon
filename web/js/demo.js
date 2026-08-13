import { PresenceDriver, simulatedEnvelope } from "./presence.js";
import { AudioPresence } from "./audio.js";
import { ThoughtformRenderer, loadShaderSources } from "./renderer.js";

const hud = {
  mode: document.getElementById("mode-label"),
  turn: document.getElementById("turn-label"),
  amp: document.getElementById("meter-amp"),
  chaos: document.getElementById("meter-chaos"),
  json: document.getElementById("protocol-json"),
  status: document.getElementById("status"),
};

function setPressed(mode) {
  for (const btn of document.querySelectorAll("[data-mode]")) {
    btn.setAttribute("aria-pressed", String(btn.dataset.mode === mode));
  }
}

function isMobile() {
  return window.matchMedia("(max-width: 720px), (pointer: coarse)").matches;
}

function wireButtons(onMode) {
  for (const btn of document.querySelectorAll("[data-mode]")) {
    btn.addEventListener("click", () => onMode(btn.dataset.mode));
  }
}

async function main() {
  const canvas = document.getElementById("presence");
  hud.status.textContent = "loading shader…";

  let sources;
  try {
    const root = new URL("../../", import.meta.url);
    sources = await loadShaderSources(root.href.replace(/\/$/, ""));
  } catch (err) {
    hud.status.textContent =
      "Could not load shaders. Serve the repo root (python3 -m http.server 4173) rather than opening the HTML file.";
    throw err;
  }

  const renderer = new ThoughtformRenderer(canvas, sources);
  const driver = new PresenceDriver({ quality: isMobile() ? 0.55 : 1 });
  const audio = new AudioPresence();

  let micOn = false;
  let autoPlay = false;
  let autoT = 0;
  let last = performance.now();

  const applyMode = (mode) => {
    autoPlay = false;
    document.getElementById("auto").setAttribute("aria-pressed", "false");
    driver.setMode(mode);
    setPressed(mode);
    if (mode === "think") {
      driver.ingestArbiterEvent("request_received");
    }
  };

  wireButtons(applyMode);
  setPressed("idle");

  document.getElementById("mic").addEventListener("click", async () => {
    const btn = document.getElementById("mic");
    try {
      if (!micOn) {
        await audio.enableMic();
        micOn = true;
        btn.setAttribute("aria-pressed", "true");
        btn.textContent = "mic on";
        applyMode("listen");
      } else {
        audio.disableMic();
        micOn = false;
        btn.setAttribute("aria-pressed", "false");
        btn.textContent = "mic";
        if (driver.targetMode === "listen") applyMode("idle");
      }
    } catch (err) {
      hud.status.textContent = `mic denied: ${err.message || err}`;
    }
  });

  document.getElementById("auto").addEventListener("click", () => {
    autoPlay = !autoPlay;
    document.getElementById("auto").setAttribute("aria-pressed", String(autoPlay));
    if (autoPlay) {
      autoT = 0;
      micOn = false;
      audio.disableMic();
      document.getElementById("mic").setAttribute("aria-pressed", "false");
      document.getElementById("mic").textContent = "mic";
    }
  });

  window.addEventListener("keydown", (e) => {
    if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return;
    const map = { "1": "idle", "2": "listen", "3": "think", "4": "speak" };
    if (map[e.key]) applyMode(map[e.key]);
    if (e.key === "a" || e.key === "A") document.getElementById("auto").click();
    if (e.key === "m" || e.key === "M") document.getElementById("mic").click();
  });

  const simulateTurn = (t) => {
    const cycle = t % 14;
    if (cycle < 2.2) {
      driver.ingestAlfredTurn({ phase: "idle" });
      driver.setAudio({ rms: 0, low: 0, mid: 0, high: 0 });
    } else if (cycle < 5.2) {
      driver.ingestAlfredTurn({ phase: "recording", turnId: "demo-turn" });
      driver.setAudio(simulatedEnvelope(cycle, "listen"));
    } else if (cycle < 8.6) {
      driver.ingestAlfredTurn({
        phase: "thinking",
        turnId: "demo-turn",
        transcript: "what is on my calendar",
      });
      if (cycle < 5.5) driver.ingestArbiterEvent("request_received");
      else if (cycle < 6.2) driver.ingestArbiterEvent("agent_start");
      else if (cycle < 7.2) driver.ingestArbiterEvent("tool_call");
      else driver.ingestArbiterEvent("text");
      driver.setAudio({ rms: 0.05, low: 0.04, mid: 0.03, high: 0.06 });
    } else {
      driver.ingestAlfredTurn({ phase: "speaking", turnId: "demo-turn" });
      driver.setAudio(simulatedEnvelope(cycle, "speak"));
    }
    setPressed(driver.targetMode);
  };

  window.thoughtformSetMode = applyMode;
  window.thoughtformDriver = driver;
  hud.status.textContent = "webgl2 · gotham";

  const loop = (now) => {
    const dt = Math.min(0.05, (now - last) / 1000);
    last = now;

    renderer.resize(isMobile() ? 1.5 : 2);

    if (autoPlay) {
      autoT += dt;
      simulateTurn(autoT);
    } else if (micOn && driver.targetMode === "listen") {
      driver.setAudio(audio.sample());
    } else if (driver.targetMode === "listen") {
      driver.setAudio(simulatedEnvelope(now / 1000, "listen"));
    } else if (driver.targetMode === "speak") {
      driver.setAudio(simulatedEnvelope(now / 1000, "speak"));
    } else if (driver.targetMode === "think") {
      driver.setAudio({ rms: 0.04 + 0.02 * Math.sin(now / 400), low: 0.03, mid: 0.04, high: 0.05 });
    } else {
      driver.setAudio({ rms: 0, low: 0, mid: 0, high: 0 });
    }

    const frame = driver.tick(dt);
    renderer.render(frame);

    hud.mode.textContent = frame.mode;
    hud.turn.textContent = frame.turnId || "—";
    hud.amp.style.setProperty("--level", `${Math.round(frame.amplitude * 100)}%`);
    hud.chaos.style.setProperty("--level", `${Math.round(frame.chaos * 100)}%`);
    hud.json.textContent = JSON.stringify(driver.toJSON(), null, 2);

    requestAnimationFrame(loop);
  };

  requestAnimationFrame(loop);
}

main().catch((err) => {
  console.error(err);
  hud.status.textContent = String(err.message || err);
});
