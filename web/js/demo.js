import { PresenceDriver, simulatedEnvelope } from "./presence.js";
import { AxonRenderer, loadShaderSources } from "./renderer.js";

function isMobile() {
  return window.matchMedia("(max-width: 720px), (pointer: coarse)").matches;
}

function simulateTurn(driver, t) {
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
}

async function main() {
  const canvas = document.getElementById("presence");
  const root = new URL("../../", import.meta.url);
  const sources = await loadShaderSources(root.href.replace(/\/$/, ""));
  const renderer = new AxonRenderer(canvas, sources);
  const driver = new PresenceDriver({ quality: isMobile() ? 0.55 : 1 });

  let t = 0;
  let last = performance.now();

  const loop = (now) => {
    const dt = Math.min(0.05, (now - last) / 1000);
    last = now;
    t += dt;
    renderer.resize(isMobile() ? 1.5 : 2);
    simulateTurn(driver, t);
    renderer.render(driver.tick(dt));
    requestAnimationFrame(loop);
  };

  requestAnimationFrame(loop);
}

main().catch((err) => {
  console.error(err);
});
