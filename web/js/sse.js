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
