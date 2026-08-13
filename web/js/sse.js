/** Split Arbiter `text/event-stream` into `{ event, data }` frames. */

export function parseSseBuffer(buffer) {
  const frames = [];
  const parts = buffer.split("\n\n");
  const rest = parts.pop() ?? "";
  for (const block of parts) {
    if (!block.trim() || block.startsWith(":")) continue;
    let event = "message";
    const dataLines = [];
    for (const line of block.split("\n")) {
      if (line.startsWith("event:")) event = line.slice(6).trim();
      else if (line.startsWith("data:")) dataLines.push(line.slice(5).trimStart());
    }
    frames.push({ event, data: dataLines.join("\n") });
  }
  return { frames, rest };
}

export function parseSseData(data) {
  if (!data) return null;
  try {
    return JSON.parse(data);
  } catch {
    return data;
  }
}

/**
 * @param {Response} response fetch() of an Arbiter SSE endpoint
 * @param {{ ingestArbiterEvent: (name: string, payload?: unknown) => void }} driver
 */
export async function consumeArbiterSSE(response, driver) {
  if (!response.body) throw new Error("SSE response has no body");
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buf = "";
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    buf += decoder.decode(value, { stream: true });
    const parsed = parseSseBuffer(buf);
    buf = parsed.rest;
    for (const frame of parsed.frames) {
      driver.ingestArbiterEvent(frame.event, parseSseData(frame.data));
    }
  }
}
