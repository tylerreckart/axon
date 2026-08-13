const UNIFORM_NAMES = [
  "u_resolution",
  "u_time",
  "u_weights",
  "u_amplitude",
  "u_bands",
  "u_progress",
  "u_attention",
  "u_chaos",
  "u_quality",
  "u_color_a",
  "u_color_b",
  "u_color_c",
  "u_bg",
];

function compile(gl, type, source, label) {
  const shader = gl.createShader(type);
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    const log = gl.getShaderInfoLog(shader) || "compile failed";
    gl.deleteShader(shader);
    throw new Error(`${label} shader: ${log}`);
  }
  return shader;
}

export async function loadShaderSources(base = "") {
  const prefix = base.replace(/\/$/, "");
  const [vert, frag] = await Promise.all([
    fetch(`${prefix}/shaders/axon.vert.glsl`).then((r) => {
      if (!r.ok) throw new Error(`failed to load vertex shader (${r.status})`);
      return r.text();
    }),
    fetch(`${prefix}/shaders/axon.frag.glsl`).then((r) => {
      if (!r.ok) throw new Error(`failed to load fragment shader (${r.status})`);
      return r.text();
    }),
  ]);
  return { vert, frag };
}

export class AxonRenderer {
  /**
   * @param {HTMLCanvasElement} canvas
   * @param {{vert: string, frag: string}} sources
   */
  constructor(canvas, sources) {
    this.canvas = canvas;
    const gl = canvas.getContext("webgl2", {
      alpha: false,
      antialias: false,
      premultipliedAlpha: false,
      preserveDrawingBuffer: false,
      powerPreference: "high-performance",
    });
    if (!gl) {
      throw new Error("WebGL 2 is required (Safari iOS 15+, Chrome, Firefox, Edge).");
    }
    this.gl = gl;

    const vs = compile(gl, gl.VERTEX_SHADER, sources.vert, "vertex");
    const fs = compile(gl, gl.FRAGMENT_SHADER, sources.frag, "fragment");
    const program = gl.createProgram();
    gl.attachShader(program, vs);
    gl.attachShader(program, fs);
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
      throw new Error(`program link: ${gl.getProgramInfoLog(program)}`);
    }
    gl.deleteShader(vs);
    gl.deleteShader(fs);
    this.program = program;
    gl.useProgram(program);

    this.locations = {};
    for (const name of UNIFORM_NAMES) {
      this.locations[name] = gl.getUniformLocation(program, name);
    }

    this.vao = gl.createVertexArray();
    gl.bindVertexArray(this.vao);
    // Dummy attribute so iOS Safari is happy drawing a gl_VertexID triangle.
    const buf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buf);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([0, 1, 2]), gl.STATIC_DRAW);
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 1, gl.FLOAT, false, 0, 0);
    gl.clearColor(0.02, 0.008, 0.0, 1);
  }

  resize(dprCap = 2) {
    const dpr = Math.min(window.devicePixelRatio || 1, dprCap);
    const w = Math.max(1, Math.floor(this.canvas.clientWidth * dpr));
    const h = Math.max(1, Math.floor(this.canvas.clientHeight * dpr));
    if (this.canvas.width !== w || this.canvas.height !== h) {
      this.canvas.width = w;
      this.canvas.height = h;
    }
    this.gl.viewport(0, 0, w, h);
  }

  render(frame) {
    const gl = this.gl;
    const loc = this.locations;
    gl.useProgram(this.program);
    gl.bindVertexArray(this.vao);
    gl.uniform2f(loc.u_resolution, this.canvas.width, this.canvas.height);
    gl.uniform1f(loc.u_time, frame.time);
    gl.uniform4f(loc.u_weights, frame.weights[0], frame.weights[1], frame.weights[2], frame.weights[3]);
    gl.uniform1f(loc.u_amplitude, frame.amplitude);
    gl.uniform3f(loc.u_bands, frame.bands[0], frame.bands[1], frame.bands[2]);
    gl.uniform1f(loc.u_progress, frame.progress);
    gl.uniform1f(loc.u_attention, frame.attention);
    gl.uniform1f(loc.u_chaos, frame.chaos);
    gl.uniform1f(loc.u_quality, frame.quality);
    gl.uniform3f(loc.u_color_a, frame.colorA[0], frame.colorA[1], frame.colorA[2]);
    gl.uniform3f(loc.u_color_b, frame.colorB[0], frame.colorB[1], frame.colorB[2]);
    gl.uniform3f(loc.u_color_c, frame.colorC[0], frame.colorC[1], frame.colorC[2]);
    gl.uniform3f(loc.u_bg, frame.background[0], frame.background[1], frame.background[2]);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
  }
}
