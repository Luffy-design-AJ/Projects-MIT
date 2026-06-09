const canvas = document.getElementById("game");
const ctx = canvas.getContext("2d");

const ui = {
  phase: document.getElementById("phasePill"),
  run: document.getElementById("runPill"),
  memory: document.getElementById("memoryPill"),
  hpText: document.getElementById("hpText"),
  hpBar: document.getElementById("hpBar"),
  swarmText: document.getElementById("swarmText"),
  swarmBar: document.getElementById("swarmBar"),
  resText: document.getElementById("resText"),
  resBar: document.getElementById("resBar"),
  signals: document.getElementById("signals"),
  interp: document.getElementById("interpretation"),
  adapt: document.getElementById("adaptation"),
  choice: document.getElementById("choiceScreen"),
  choiceTitle: document.getElementById("choiceTitle"),
  choiceBody: document.getElementById("choiceBody"),
  choiceGrid: document.getElementById("choiceGrid"),
  toast: document.getElementById("toast"),
  levels: document.getElementById("levelList"),
  devAnts: document.getElementById("devAnts"),
  devExplore: document.getElementById("devExplore"),
  devNoise: document.getElementById("devNoise"),
  devStamp: document.getElementById("devStamp"),
  devSat: document.getElementById("devSat"),
  devFootDiff: document.getElementById("devFootDiff"),
  resetMemory: document.getElementById("resetMemory")
};

const TAU = Math.PI * 2;
const dirs8 = [[1,0],[-1,0],[0,1],[0,-1],[1,1],[1,-1],[-1,1],[-1,-1]];
const keys = new Set();
const pointer = { x: 0, y: 0, cx: 0, cy: 0, down: false };
const SAVE_KEY = "node-zero-antgame-combat-memory-v2";

const G = { cols: 120, rows: 72, cell: 14 };
const WORLD = { w: G.cols * G.cell, h: G.rows * G.cell };
const MAX_ANTS = 150;

const nodeImg = new Image();
nodeImg.src = "assets/coordination-node.png";
const nightborneSheet = new Image();
nightborneSheet.src = "assets/nightborne-sheet.png";
const enemyImgs = {
  idle: makeImg("assets/nightborne-idle.gif"),
  run: makeImg("assets/nightborne-run.gif"),
  attack: makeImg("assets/nightborne-attack.gif"),
  hurt: makeImg("assets/nightborne-hurt.gif"),
  death: makeImg("assets/nightborne-death.gif")
};
let playerSprite = null;
let enemySheet = null;

function makeImg(src) {
  const img = new Image();
  img.src = src;
  return img;
}

const params = {
  antCount: MAX_ANTS,
  explore: 0.08,
  noise: 0.07,
  returnNoise: 0.12,
  stamp: 0.34,
  satCap: 1,
  satPen: 0.8,
  footDecay: 0.9985,
  footDiffusion: 0.05,
  footDeposit: 0.075,
  leadDecay: 0.9978,
  signalDecay: 0.989,
  freshDecay: 0.982,
  leadW: 4.2,
  huntW: 5.4,
  scatterW: 5.8,
  echoW: 4.7,
  consumeW: 3.8,
  footW: 1.45,
  homeW: 1.9,
  dangerW: 4.4,
  freshBonus: 3.5
};

const fieldDefs = {
  lead: { color: [213, 163, 67], label: "Lead A" },
  hunt: { color: [255, 107, 74], label: "Hunt" },
  scatter: { color: [122, 167, 255], label: "Scatter" },
  echo: { color: [185, 147, 255], label: "Echo" },
  consume: { color: [110, 231, 200], label: "Consume" },
  foot: { color: [88, 206, 184], label: "Foot trail" },
  home: { color: [124, 198, 112], label: "Home" },
  danger: { color: [226, 99, 88], label: "Danger" },
  fresh: { color: [245, 241, 218], label: "Freshness" }
};

const signals = {
  hunt: { key: "KeyQ", label: "Hunt", sub: "red predator pheromone", cooldown: 3.8, radius: 5 },
  scatter: { key: "KeyE", label: "Scatter", sub: "blue evasion chemical", cooldown: 4.1, radius: 6 },
  echo: { key: "KeyR", label: "Echo", sub: "purple false trail", cooldown: 5.6, radius: 5 },
  consume: { key: "KeyF", label: "Consume", sub: "matter recall field", cooldown: 5.2, radius: 5 },
  veil: { key: "KeyV", label: "Veil", sub: "quiet low-signature colony", cooldown: 6.5, radius: 6 }
};

const levels = [
  {
    name: "Gradient Gate",
    phase: "Curiosity",
    goal: "Use Lead A to bend ants around the sealed rib. Hunt only after they have a route.",
    spawn: { x: 14, y: 55 },
    arena: { x: 8, y: 12, w: 55, h: 48 },
    enemies: [
      { type: "duelist", x: 52, y: 26 },
      { type: "duelist", x: 52, y: 48 },
      { type: "jammer", x: 42, y: 37 }
    ],
    walls: [
      { x: 26, y: 16, w: 5, h: 37 },
      { x: 31, y: 16, w: 15, h: 4 },
      { x: 31, y: 49, w: 15, h: 4 }
    ],
    hint: "The short line jams. Paint a curved Lead A decision point above or below the rib, then pulse Hunt."
  },
  {
    name: "Split Current",
    phase: "Pattern",
    goal: "Enemies punish clustering. Maintain two chemical lanes and Scatter through the pressure wave.",
    spawn: { x: 14, y: 36 },
    arena: { x: 8, y: 9, w: 78, h: 54 },
    enemies: [
      { type: "splitter", x: 62, y: 22 },
      { type: "splitter", x: 62, y: 50 },
      { type: "predator", x: 76, y: 36 },
      { type: "duelist", x: 48, y: 36 }
    ],
    walls: [
      { x: 34, y: 14, w: 4, h: 17 },
      { x: 34, y: 42, w: 4, h: 17 },
      { x: 46, y: 30, w: 22, h: 4 },
      { x: 46, y: 39, w: 22, h: 4 }
    ],
    hint: "Lead A should split before the center. Scatter is not panic; it keeps gradients from becoming a blob."
  },
  {
    name: "False Choir",
    phase: "Mastery",
    goal: "Predictors read your most common lane. Echo creates a phantom gradient while ants use the real one.",
    spawn: { x: 15, y: 54 },
    arena: { x: 7, y: 8, w: 96, h: 58 },
    enemies: [
      { type: "predictor", x: 70, y: 22 },
      { type: "predictor", x: 70, y: 50 },
      { type: "jammer", x: 83, y: 36 },
      { type: "warden", x: 93, y: 36 }
    ],
    walls: [
      { x: 31, y: 10, w: 4, h: 23 },
      { x: 31, y: 42, w: 4, h: 22 },
      { x: 53, y: 18, w: 4, h: 36 },
      { x: 75, y: 10, w: 4, h: 20 },
      { x: 75, y: 43, w: 4, h: 21 }
    ],
    hint: "Echo stamps a louder fake route. Cast it away from the real Lead A lane to pull intelligent enemies off-model."
  }
];

const mutations = [
  { id: "collectivePanic", title: "Collective Panic", text: "Enemy deaths stamp fear into nearby intelligent enemies, making them misread gradients." },
  { id: "queenMemory", title: "Queen Memory", text: "Known levels begin with a faint home field and cleaner ant confidence." },
  { id: "cannibalBloom", title: "Cannibal Bloom", text: "Dead ants become matter nodes that Consume can convert back into swarm mass." },
  { id: "falseTrail", title: "False Trail", text: "Dashing deposits a purple echo trail that predictors may choose over the real lane." },
  { id: "distributedConsensus", title: "Distributed Consensus", text: "Ants near isolated enemies locally weight Hunt higher without direct orders." },
  { id: "emergencyFragmentation", title: "Emergency Fragmentation", text: "Near collapse, the hive auto-stamps Scatter and drops sacrificial mines." }
];

const memory = loadMemory();

const game = {
  time: 0,
  stepAcc: 0,
  level: 0,
  run: memory.runs + 1,
  phase: "planning",
  pausedForChoice: false,
  hitstop: 0,
  shake: 0,
  resonance: 1,
  activeSignal: null,
  activeSignalTime: 0,
  fields: {},
  solid: new Uint8Array(G.cols * G.rows),
  permanent: new Uint8Array(G.cols * G.rows),
  ants: [],
  enemies: [],
  biomass: [],
  pulses: [],
  mines: [],
  projectiles: [],
  player: {
    x: 14 * G.cell,
    y: 55 * G.cell,
    vx: 0,
    vy: 0,
    hp: 100,
    dash: 0,
    invuln: 0,
    facing: 0,
    lastMoveX: 1,
    lastMoveY: 0,
    cast: 0,
    walk: 0
  },
  camera: { x: 0, y: 0, sx: 0, sy: 0 },
  stats: {
    casts: 0,
    dashes: 0,
    signalUse: {},
    clusterTotal: 0,
    clusterSamples: 0,
    damage: 0
  }
};

nodeImg.addEventListener("load", () => {
  playerSprite = keyedSprite(nodeImg, 832, 1280, 260, 130, 360, 820, "white");
});

nightborneSheet.addEventListener("load", () => {
  enemySheet = keyedSprite(nightborneSheet, 1840, 400, 0, 0, 1840, 400, "black");
});

function keyedSprite(img, sw, sh, sx, sy, cw, ch, key) {
  const c = document.createElement("canvas");
  c.width = cw;
  c.height = ch;
  const g = c.getContext("2d");
  g.drawImage(img, sx, sy, cw, ch, 0, 0, cw, ch);
  const data = g.getImageData(0, 0, cw, ch);
  for (let i = 0; i < data.data.length; i += 4) {
    const r = data.data[i];
    const gg = data.data[i + 1];
    const b = data.data[i + 2];
    if (key === "white" && r > 218 && gg > 214 && b > 206) data.data[i + 3] = 0;
    if (key === "black" && r < 6 && gg < 6 && b < 6) data.data[i + 3] = 0;
  }
  g.putImageData(data, 0, 0);
  return c;
}

function loadMemory() {
  const fallback = { runs: 0, memory: 0, deaths: 0, mutations: [], habits: { favoriteSignal: "none", clustering: 0, casts: 0, dashes: 0 } };
  try {
    return { ...fallback, ...JSON.parse(localStorage.getItem(SAVE_KEY) || "{}") };
  } catch {
    return fallback;
  }
}

function saveMemory() {
  localStorage.setItem(SAVE_KEY, JSON.stringify(memory));
}

function hasMutation(id) {
  return memory.mutations.includes(id);
}

function idx(x, y) {
  return y * G.cols + x;
}

function clamp(v, a, b) {
  return Math.max(a, Math.min(b, v));
}

function rand(a, b) {
  return a + Math.random() * (b - a);
}

function lerp(a, b, t) {
  return a + (b - a) * t;
}

function dist2(ax, ay, bx, by) {
  return (ax - bx) ** 2 + (ay - by) ** 2;
}

function dist(ax, ay, bx, by) {
  return Math.hypot(ax - bx, ay - by);
}

function norm(x, y) {
  const d = Math.hypot(x, y) || 1;
  return { x: x / d, y: y / d, d };
}

function cellFromWorld(x, y) {
  return {
    x: clamp(Math.floor(x / G.cell), 0, G.cols - 1),
    y: clamp(Math.floor(y / G.cell), 0, G.rows - 1)
  };
}

function worldFromCell(x, y) {
  return { x: x * G.cell + G.cell / 2, y: y * G.cell + G.cell / 2 };
}

function field(name) {
  return game.fields[name];
}

function sample(name, x, y) {
  x = clamp(x, 0, G.cols - 1);
  y = clamp(y, 0, G.rows - 1);
  return field(name)[idx(x, y)] || 0;
}

function stamp(name, x, y, r, v, permanent = false) {
  const arr = field(name);
  for (let yy = y - r; yy <= y + r; yy++) {
    for (let xx = x - r; xx <= x + r; xx++) {
      if (xx < 0 || yy < 0 || xx >= G.cols || yy >= G.rows) continue;
      const d = Math.abs(xx - x) + Math.abs(yy - y);
      if (d > r) continue;
      const cap = permanent ? params.satCap * 1.5 : params.satCap;
      arr[idx(xx, yy)] = clamp(arr[idx(xx, yy)] + v * (1 - d / (r + 1)), 0, cap);
    }
  }
}

function blocked(x, y) {
  return x < 0 || y < 0 || x >= G.cols || y >= G.rows || game.solid[idx(x, y)] === 1;
}

function saturationPenalty(v) {
  const opt = params.satCap * 0.5;
  if (v < opt) return 1;
  const excess = (v - opt) / (params.satCap - opt + 1e-6);
  return Math.max(params.satPen, 1 - excess * (1 - params.satPen));
}

function wrappedDelta(a, b) {
  let d = (b - a + dirs8.length) % dirs8.length;
  if (d > dirs8.length / 2) d -= dirs8.length;
  return d;
}

function diffuse(name, decay, spread) {
  const arr = field(name);
  const copy = new Float32Array(arr);
  for (let y = 1; y < G.rows - 1; y++) {
    for (let x = 1; x < G.cols - 1; x++) {
      const i = idx(x, y);
      if (game.solid[i]) {
        arr[i] = 0;
        continue;
      }
      const n = copy[idx(x + 1, y)] + copy[idx(x - 1, y)] + copy[idx(x, y + 1)] + copy[idx(x, y - 1)];
      arr[i] = (copy[i] * (1 - spread) + n * spread * 0.25) * decay;
    }
  }
}

function initFields() {
  for (const name of Object.keys(fieldDefs)) game.fields[name] = new Float32Array(G.cols * G.rows);
}

function spawnAnt(cx, cy) {
  return {
    x: cx + Math.floor(rand(-2, 3)),
    y: cy + Math.floor(rand(-2, 3)),
    dir: Math.floor(rand(0, 8)),
    carry: false,
    scout: true,
    confidence: 0,
    straightness: 1,
    prevLead: 0,
    prevHome: 0,
    prevFoot: 0,
    everHit: false,
    panic: 0,
    age: rand(0, 4)
  };
}

function buildSignalButtons() {
  ui.signals.innerHTML = "";
  for (const [id, sig] of Object.entries(signals)) {
    sig.cooldownLeft = 0;
    const b = document.createElement("button");
    b.className = "signal";
    b.dataset.signal = id;
    b.innerHTML = `<strong>${sig.label}</strong><small>${sig.sub}</small>`;
    b.addEventListener("click", () => castSignal(id));
    ui.signals.appendChild(b);
  }
}

function buildLevelButtons() {
  ui.levels.innerHTML = "";
  levels.forEach((level, i) => {
    const b = document.createElement("button");
    b.className = `level-button${i === game.level ? " active" : ""}`;
    b.innerHTML = `<strong>${i + 1}. ${level.name}</strong><small>${level.phase}: ${level.goal}</small>`;
    b.addEventListener("click", () => loadLevel(i));
    ui.levels.appendChild(b);
  });
}

function addRect(x, y, w, h, permanent = true) {
  for (let yy = y; yy < y + h; yy++) {
    for (let xx = x; xx < x + w; xx++) {
      if (xx < 0 || yy < 0 || xx >= G.cols || yy >= G.rows) continue;
      game.solid[idx(xx, yy)] = 1;
      if (permanent) game.permanent[idx(xx, yy)] = 1;
    }
  }
}

function loadLevel(i) {
  game.level = i;
  game.phase = "planning";
  game.time = 0;
  game.stepAcc = 0;
  game.hitstop = 0;
  game.pausedForChoice = false;
  game.resonance = 1;
  game.activeSignal = null;
  game.fields = {};
  game.solid = new Uint8Array(G.cols * G.rows);
  game.permanent = new Uint8Array(G.cols * G.rows);
  game.ants = [];
  game.enemies = [];
  game.biomass = [];
  game.pulses = [];
  game.mines = [];
  game.projectiles = [];
  initFields();

  addRect(0, 0, G.cols, 4);
  addRect(0, G.rows - 4, G.cols, 4);
  addRect(0, 0, 4, G.rows);
  addRect(G.cols - 4, 0, 4, G.rows);
  for (const w of levels[i].walls) addRect(w.x, w.y, w.w, w.h);

  const spawn = levels[i].spawn;
  game.player.x = spawn.x * G.cell;
  game.player.y = spawn.y * G.cell;
  game.player.vx = 0;
  game.player.vy = 0;
  game.player.hp = 100;
  game.player.dash = 0;
  const antCount = Number(ui.devAnts.value || params.antCount);
  params.antCount = antCount;
  for (let n = 0; n < antCount; n++) game.ants.push(spawnAnt(spawn.x, spawn.y));

  for (const e of levels[i].enemies) game.enemies.push(makeEnemy(e));

  if (hasMutation("queenMemory")) {
    for (let yy = levels[i].arena.y; yy < levels[i].arena.y + levels[i].arena.h; yy += 2) {
      stamp("home", spawn.x, yy, 1, 0.08);
    }
  }
  buildLevelButtons();
  updateLevelCopy();
  ui.choice.classList.add("hidden");
  toast(levels[i].hint);
}

function makeEnemy(e) {
  const base = {
    duelist: { hp: 64, speed: 46, r: 15, color: "#d6c8ff" },
    splitter: { hp: 86, speed: 36, r: 18, color: "#ff6b4a" },
    jammer: { hp: 92, speed: 32, r: 19, color: "#7aa7ff" },
    predator: { hp: 68, speed: 62, r: 14, color: "#d5a343" },
    predictor: { hp: 78, speed: 44, r: 16, color: "#b993ff" },
    warden: { hp: 260, speed: 28, r: 24, color: "#f0e8ff" }
  }[e.type];
  return {
    ...base,
    type: e.type,
    x: e.x,
    y: e.y,
    vx: 0,
    vy: 0,
    maxHp: base.hp + memory.memory * 0.35,
    hp: base.hp + memory.memory * 0.35,
    attack: rand(1, 2.4),
    hurt: 0,
    fear: 0,
    state: "idle",
    dead: 0
  };
}

function updateLevelCopy() {
  ui.interp.textContent = levels[game.level].goal;
  const h = memory.habits;
  if (memory.runs === 0) ui.adapt.textContent = "No model yet. It is watching your chemical handwriting.";
  else if (h.favoriteSignal !== "none") ui.adapt.textContent = `It remembers your ${h.favoriteSignal.toUpperCase()} bias and adds intelligent counters.`;
  else ui.adapt.textContent = "It remembers your lane density and dash exits from earlier bodies.";
}

function castSignal(id) {
  const sig = signals[id];
  if (!sig || sig.cooldownLeft > 0 || game.pausedForChoice) return;
  const c = cellFromWorld(pointer.x || game.player.x, pointer.y || game.player.y);
  sig.cooldownLeft = sig.cooldown;
  game.resonance = clamp(game.resonance - 0.22, 0, 1);
  game.activeSignal = id;
  game.activeSignalTime = 0.55;
  game.player.cast = 0.38;
  game.stats.casts++;
  game.stats.signalUse[id] = (game.stats.signalUse[id] || 0) + 1;
  stamp(id === "veil" ? "scatter" : id, c.x, c.y, sig.radius, params.stamp * 2.4, true);
  stamp("fresh", c.x, c.y, sig.radius + 1, 1, true);
  if (id === "echo" || hasMutation("falseTrail")) stamp("echo", c.x + Math.sign(game.player.lastMoveX) * 6, c.y, sig.radius, params.stamp * 1.6);
  if (id === "consume") consumeMatter(c.x, c.y);
  game.pulses.push({ x: c.x, y: c.y, r: 1, max: sig.radius + 6, life: 0.55, color: fieldDefs[id === "veil" ? "scatter" : id].color, arcana: true });
  toast(`${sig.label} arcana stamped into the grid.`);
}

function consumeMatter(cx, cy) {
  let gained = 0;
  game.biomass = game.biomass.filter((b) => {
    if (Math.abs(b.x - cx) + Math.abs(b.y - cy) < 18) {
      gained += b.value;
      return false;
    }
    return true;
  });
  for (let i = 0; i < gained; i++) game.ants.push(spawnAnt(cx, cy));
}

function stampLeadAtPointer() {
  const c = cellFromWorld(pointer.x, pointer.y);
  stamp("lead", c.x, c.y, 2, params.stamp);
  stamp("fresh", c.x, c.y, 2, 1, true);
  game.player.cast = Math.max(game.player.cast, 0.1);
}

function update(dt) {
  if (game.pausedForChoice) return;
  game.time += dt;
  if (game.hitstop > 0) {
    game.hitstop -= dt;
    return;
  }
  for (const sig of Object.values(signals)) sig.cooldownLeft = Math.max(0, sig.cooldownLeft - dt);
  game.activeSignalTime = Math.max(0, game.activeSignalTime - dt);
  if (game.activeSignalTime === 0) game.activeSignal = null;
  updatePlayer(dt);
  updateFields(dt);
  updateAnts(dt);
  updateEnemies(dt);
  updateProjectiles(dt);
  updateMatter(dt);
  updateCamera(dt);
  checkLevelState();
  updateUi();
}

function updatePlayer(dt) {
  const p = game.player;
  const mx = (keys.has("KeyD") || keys.has("ArrowRight") ? 1 : 0) - (keys.has("KeyA") || keys.has("ArrowLeft") ? 1 : 0);
  const my = (keys.has("KeyS") || keys.has("ArrowDown") ? 1 : 0) - (keys.has("KeyW") || keys.has("ArrowUp") ? 1 : 0);
  const n = norm(mx, my);
  const moving = n.d > 0.1;
  if (moving) {
    p.lastMoveX = n.x;
    p.lastMoveY = n.y;
    p.facing = Math.atan2(n.y, n.x);
    p.walk += dt * 10;
  }
  const speed = p.dash > 0 ? 520 : 180;
  p.vx = lerp(p.vx * 0.78, n.x * speed, moving ? dt * 12 : dt * 4);
  p.vy = lerp(p.vy * 0.78, n.y * speed, moving ? dt * 12 : dt * 4);
  p.x += p.vx * dt;
  p.y += p.vy * dt;
  constrainPlayer();
  p.dash = Math.max(0, p.dash - dt);
  p.invuln = Math.max(0, p.invuln - dt);
  p.cast = Math.max(0, p.cast - dt);
  game.resonance = clamp(game.resonance + dt * 0.18, 0, 1);
  const pc = cellFromWorld(p.x, p.y);
  stamp("home", pc.x, pc.y, 2, 0.035);
  if (moving) stamp("lead", pc.x, pc.y, 1, 0.018);
  if (keys.has("ShiftLeft") || keys.has("ShiftRight")) stamp("home", pc.x, pc.y, 5, 0.12);
  if (pointer.down) stampLeadAtPointer();
  if (p.hp <= 0) handleDeath();
}

function dash() {
  const p = game.player;
  if (p.dash > 0 || game.resonance < 0.16) return;
  p.dash = 0.16;
  p.invuln = 0.35;
  p.vx = p.lastMoveX * 640;
  p.vy = p.lastMoveY * 640;
  game.resonance -= 0.16;
  game.stats.dashes++;
  const c = cellFromWorld(p.x, p.y);
  stamp("lead", c.x, c.y, 4, 0.28);
  if (hasMutation("falseTrail")) stamp("echo", c.x, c.y, 5, 0.42);
  game.pulses.push({ x: c.x, y: c.y, r: 1, max: 9, life: 0.28, color: [245, 241, 218], arcana: true });
}

function constrainPlayer() {
  const p = game.player;
  p.x = clamp(p.x, G.cell * 5, WORLD.w - G.cell * 5);
  p.y = clamp(p.y, G.cell * 5, WORLD.h - G.cell * 5);
  const c = cellFromWorld(p.x, p.y);
  if (blocked(c.x, c.y)) {
    p.x -= p.vx * 0.028;
    p.y -= p.vy * 0.028;
    p.vx *= -0.2;
    p.vy *= -0.2;
  }
}

function updateFields() {
  diffuse("lead", params.leadDecay, 0.045);
  diffuse("hunt", params.signalDecay, 0.075);
  diffuse("scatter", 0.985, 0.1);
  diffuse("echo", 0.988, 0.085);
  diffuse("consume", 0.991, 0.05);
  diffuse("home", 0.997, 0.04);
  diffuse("danger", 0.972, 0.09);
  diffuse("foot", params.footDecay, params.footDiffusion);
  const fresh = field("fresh");
  for (let i = 0; i < fresh.length; i++) fresh[i] *= params.freshDecay;
}

function updateAnts(dt) {
  game.stepAcc += dt;
  const stepRate = 0.055;
  while (game.stepAcc >= stepRate) {
    for (const ant of game.ants) updateAnt(ant);
    game.stepAcc -= stepRate;
  }
  const c = antCentroid();
  let spread = 0;
  for (let i = 0; i < game.ants.length; i += 5) spread += Math.sqrt(dist2(game.ants[i].x, game.ants[i].y, c.x, c.y));
  game.stats.clusterTotal += clamp(1 - spread / Math.max(1, game.ants.length / 5) / 15, 0, 1);
  game.stats.clusterSamples++;
}

function updateAnt(ant) {
  ant.age++;
  ant.panic = Math.max(0, ant.panic - 0.02);
  const playerCell = cellFromWorld(game.player.x, game.player.y);
  const nearest = nearestEnemyCell(ant.x, ant.y);
  const candidates = [];
  for (let offset = -2; offset <= 2; offset++) {
    const d = (ant.dir + offset + dirs8.length) % dirs8.length;
    const [dx, dy] = dirs8[d];
    const nx = ant.x + dx;
    const ny = ant.y + dy;
    if (blocked(nx, ny)) continue;
    const lead = sample("lead", nx, ny);
    const hunt = sample("hunt", nx, ny);
    const scatter = sample("scatter", nx, ny);
    const echo = sample("echo", nx, ny);
    const consume = sample("consume", nx, ny);
    const home = sample("home", nx, ny);
    const foot = sample("foot", nx, ny);
    const danger = sample("danger", nx, ny);
    const fresh = sample("fresh", nx, ny);
    const leadS = saturationPenalty(lead);
    const homeS = saturationPenalty(home);
    const dLead = lead - ant.prevLead;
    const dHome = home - ant.prevHome;
    const dFoot = foot - ant.prevFoot;
    const freshMult = 1 + fresh * params.freshBonus;
    let score = 0.32 - Math.abs(offset) * 0.08;
    score += lead * leadS * params.leadW * freshMult;
    score += home * homeS * params.homeW;
    score += foot * params.footW;
    score += dLead * 1.2 + dHome * 0.75 + dFoot * 0.55;
    score -= danger * params.dangerW;

    if (nearest) {
      const toEnemy = norm(nearest.x - ant.x, nearest.y - ant.y);
      const towardEnemy = dx * toEnemy.x + dy * toEnemy.y;
      const flank = -dy * toEnemy.x + dx * toEnemy.y;
      score += hunt * params.huntW * (0.7 + Math.abs(flank) * 0.45 + Math.max(0, towardEnemy) * 0.4);
      if (hasMutation("distributedConsensus") && nearest.d < 18) score += Math.max(0, towardEnemy) * 0.55;
    }

    const toPlayer = norm(playerCell.x - ant.x, playerCell.y - ant.y);
    score += scatter * params.scatterW * (-dx * toPlayer.x - dy * toPlayer.y + 0.55);
    score += echo * params.echoW * (Math.sin((ant.age + nx * 7 + ny * 3) * 0.1) * 0.5 + 0.7);
    score += consume * params.consumeW;
    if (lead + home + foot < 0.03) score += params.explore;
    score += rand(-params.noise, params.noise);
    if (ant.panic > 0) score += rand(-0.8, 0.8);
    candidates.push({ d, nx, ny, score, lead, home, foot });
  }
  if (!candidates.length) {
    ant.dir = (ant.dir + 4) % dirs8.length;
    return;
  }
  candidates.sort((a, b) => b.score - a.score);
  let chosen = candidates[0];
  const variability = ant.everHit ? 0.1 : 0.18;
  if (candidates[1] && Math.random() < variability) chosen = candidates[1];
  const turn = wrappedDelta(ant.dir, chosen.d);
  if (Math.abs(turn) > 1 && Math.random() < 0.45) {
    ant.dir = (ant.dir + Math.sign(turn) + dirs8.length) % dirs8.length;
    const [dx, dy] = dirs8[ant.dir];
    if (!blocked(ant.x + dx, ant.y + dy)) {
      ant.x += dx;
      ant.y += dy;
    }
  } else {
    ant.dir = chosen.d;
    ant.x = chosen.nx;
    ant.y = chosen.ny;
  }
  ant.straightness = 0.8 * ant.straightness + 0.2 * (Math.abs(turn) <= 1 ? 1 : 0.25);
  ant.confidence = 0.9 * ant.confidence + 0.1 * ant.straightness;
  ant.prevLead = sample("lead", ant.x, ant.y);
  ant.prevHome = sample("home", ant.x, ant.y);
  ant.prevFoot = sample("foot", ant.x, ant.y);
  stamp("foot", ant.x, ant.y, 1, params.footDeposit);
  damageEnemiesAt(ant.x, ant.y, 0.33 + sample("hunt", ant.x, ant.y) * 0.22);
}

function updateEnemies(dt) {
  for (let i = game.enemies.length - 1; i >= 0; i--) {
    const e = game.enemies[i];
    if (e.dead > 0) {
      e.dead -= dt;
      if (e.dead <= 0) game.enemies.splice(i, 1);
      continue;
    }
    e.attack -= dt;
    e.hurt = Math.max(0, e.hurt - dt);
    e.fear = Math.max(0, e.fear - dt);
    const pc = cellFromWorld(game.player.x, game.player.y);
    const fake = bestEchoCell(e);
    const target = fake || pc;
    const n = norm(target.x - e.x, target.y - e.y);
    const fearMult = e.fear > 0 ? -1 : 1;
    e.vx = lerp(e.vx, n.x * e.speed * fearMult, dt * 2.6);
    e.vy = lerp(e.vy, n.y * e.speed * fearMult, dt * 2.6);
    e.x += e.vx * dt;
    e.y += e.vy * dt;
    if (blocked(Math.round(e.x), Math.round(e.y))) {
      e.x -= e.vx * dt * 2;
      e.y -= e.vy * dt * 2;
      e.vx *= -0.4;
      e.vy *= -0.4;
    }
    e.state = Math.hypot(e.vx, e.vy) > 6 ? "run" : "idle";
    if (e.attack <= 0) enemyAttack(e);
    const wp = worldFromCell(e.x, e.y);
    if (dist(wp.x, wp.y, game.player.x, game.player.y) < 30 && game.player.invuln <= 0) hurtPlayer(e.type === "warden" ? 15 : 7);
    if (e.hp <= 0) killEnemy(e);
  }
}

function enemyAttack(e) {
  e.attack = e.type === "warden" ? 1.3 : e.type === "splitter" ? 2.2 : 1.8;
  e.state = "attack";
  if (e.type === "jammer") {
    stamp("danger", Math.round(e.x), Math.round(e.y), 8, 1, true);
    for (const ant of game.ants) if (dist2(ant.x, ant.y, e.x, e.y) < 100) ant.panic = 1.2;
    game.pulses.push({ x: e.x, y: e.y, r: 1, max: 10, life: 0.45, color: [122, 167, 255] });
    return;
  }
  const pc = cellFromWorld(game.player.x, game.player.y);
  const n = norm(pc.x - e.x, pc.y - e.y);
  const shots = e.type === "splitter" ? 3 : e.type === "warden" ? 6 : 1;
  for (let i = 0; i < shots; i++) {
    const a = Math.atan2(n.y, n.x) + (i - (shots - 1) / 2) * 0.28;
    game.projectiles.push({ x: e.x, y: e.y, vx: Math.cos(a) * 32, vy: Math.sin(a) * 32, life: 2.5, r: 0.65 });
  }
}

function updateProjectiles(dt) {
  game.projectiles = game.projectiles.filter((p) => {
    p.life -= dt;
    p.x += p.vx * dt;
    p.y += p.vy * dt;
    stamp("danger", Math.round(p.x), Math.round(p.y), 2, 0.16);
    const pc = cellFromWorld(game.player.x, game.player.y);
    if (dist2(p.x, p.y, pc.x, pc.y) < 5 && game.player.invuln <= 0) {
      hurtPlayer(6);
      p.life = 0;
    }
    for (let i = game.ants.length - 1; i >= 0; i--) {
      const a = game.ants[i];
      if (dist2(p.x, p.y, a.x, a.y) < 1.4) {
        loseAnt(i, a);
        p.life -= 0.25;
        break;
      }
    }
    return p.life > 0 && !blocked(Math.round(p.x), Math.round(p.y));
  });
}

function updateMatter(dt) {
  game.biomass = game.biomass.filter((b) => {
    b.life -= dt * 0.02;
    return b.life > 0;
  });
  game.pulses = game.pulses.filter((p) => {
    p.life -= dt;
    p.r += (p.max - p.r) * 0.24;
    return p.life > 0;
  });
  for (let i = game.mines.length - 1; i >= 0; i--) {
    const m = game.mines[i];
    m.life -= dt;
    for (const e of game.enemies) {
      if (dist2(m.x, m.y, e.x, e.y) < 14) {
        e.hp -= 22;
        game.pulses.push({ x: m.x, y: m.y, r: 1, max: 8, life: 0.35, color: [255, 107, 74] });
        m.life = 0;
      }
    }
    if (m.life <= 0) game.mines.splice(i, 1);
  }
}

function damageEnemiesAt(x, y, amount) {
  for (const e of game.enemies) {
    if (e.dead > 0) continue;
    const r = e.type === "warden" ? 5 : 3.2;
    if (dist2(x, y, e.x, e.y) < r * r) {
      e.hp -= amount;
      e.hurt = 0.12;
      e.everHit = true;
      game.stats.damage += amount;
    }
  }
}

function loseAnt(i, ant) {
  game.ants.splice(i, 1);
  if (hasMutation("cannibalBloom")) game.biomass.push({ x: ant.x, y: ant.y, value: 1, life: 1 });
}

function killEnemy(e) {
  e.dead = 0.7;
  e.state = "death";
  game.biomass.push({ x: Math.round(e.x), y: Math.round(e.y), value: e.type === "warden" ? 18 : 5, life: 1 });
  game.hitstop = 0.035;
  if (hasMutation("collectivePanic")) {
    for (const other of game.enemies) if (other !== e && dist2(e.x, e.y, other.x, other.y) < 260) other.fear = 1.4;
  }
}

function bestEchoCell(e) {
  if (e.type !== "predictor" && e.type !== "warden") return null;
  let best = null;
  let bestV = 0.18;
  for (let y = Math.max(4, Math.floor(e.y - 14)); y < Math.min(G.rows - 4, e.y + 14); y++) {
    for (let x = Math.max(4, Math.floor(e.x - 14)); x < Math.min(G.cols - 4, e.x + 14); x++) {
      const v = sample("echo", x, y);
      if (v > bestV) {
        bestV = v;
        best = { x, y };
      }
    }
  }
  return best;
}

function nearestEnemyCell(x, y) {
  let best = null;
  let bd = 9999;
  for (const e of game.enemies) {
    if (e.dead > 0) continue;
    const d = Math.sqrt(dist2(x, y, e.x, e.y));
    if (d < bd) {
      bd = d;
      best = { x: e.x, y: e.y, d, type: e.type };
    }
  }
  return best;
}

function antCentroid() {
  if (!game.ants.length) return cellFromWorld(game.player.x, game.player.y);
  let x = 0;
  let y = 0;
  for (const a of game.ants) {
    x += a.x;
    y += a.y;
  }
  return { x: x / game.ants.length, y: y / game.ants.length };
}

function hurtPlayer(amount) {
  if (game.player.invuln > 0) return;
  game.player.hp = clamp(game.player.hp - amount, 0, 100);
  game.player.invuln = 0.38;
  game.hitstop = 0.045;
  if (game.player.hp < 30 && hasMutation("emergencyFragmentation")) {
    const c = cellFromWorld(game.player.x, game.player.y);
    stamp("scatter", c.x, c.y, 8, 1, true);
    for (let i = 0; i < 4; i++) game.mines.push({ x: c.x + rand(-4, 4), y: c.y + rand(-4, 4), life: 8 });
  }
}

function handleDeath() {
  game.player.hp = 100;
  memory.deaths++;
  memory.memory += 4 + Math.round(game.stats.damage / 80);
  commitHabits();
  showChoice("Node Collapse", "The body failed. The hive keeps the gradients it learned to prefer.", true);
}

function checkLevelState() {
  const alive = game.enemies.some((e) => e.dead <= 0);
  if (!alive && !game.pausedForChoice) {
    memory.memory += 2;
    commitHabits();
    showChoice("Arena Stabilized", "The chemical proof holds. Choose how the hive mutates before the next level.", false);
  }
}

function commitHabits() {
  const favoriteSignal = Object.entries(game.stats.signalUse).sort((a, b) => b[1] - a[1])[0]?.[0] || "none";
  memory.habits = {
    favoriteSignal,
    clustering: (memory.habits.clustering + game.stats.clusterTotal / Math.max(1, game.stats.clusterSamples)) * 0.5,
    casts: Math.round((memory.habits.casts + game.stats.casts) * 0.5),
    dashes: Math.round((memory.habits.dashes + game.stats.dashes) * 0.5)
  };
  saveMemory();
}

function showChoice(title, body, death) {
  game.pausedForChoice = true;
  ui.choiceTitle.textContent = title;
  ui.choiceBody.textContent = body;
  ui.choiceGrid.innerHTML = "";
  const options = mutations.filter((m) => !memory.mutations.includes(m.id)).sort(() => Math.random() - 0.5).slice(0, 3);
  for (const option of options.length ? options : mutations.slice(0, 3)) {
    const b = document.createElement("button");
    b.className = "choice-option";
    b.innerHTML = `<strong>${option.title}</strong><span>${option.text}</span>`;
    b.addEventListener("click", () => {
      if (!memory.mutations.includes(option.id)) memory.mutations.push(option.id);
      memory.runs = Math.max(memory.runs, game.run);
      memory.memory += 2;
      saveMemory();
      ui.choice.classList.add("hidden");
      if (death) {
        game.run = memory.runs + 1;
        loadLevel(hasMutation("queenMemory") ? game.level : 0);
      } else {
        loadLevel(Math.min(levels.length - 1, game.level + 1));
      }
    });
    ui.choiceGrid.appendChild(b);
  }
  ui.choice.classList.remove("hidden");
}

function updateCamera(dt) {
  const lead = game.player.dash > 0 ? 130 : 58;
  const targetX = game.player.x + game.player.lastMoveX * lead - canvas.width / 2;
  const targetY = game.player.y + game.player.lastMoveY * lead - canvas.height / 2;
  game.camera.x = lerp(game.camera.x, clamp(targetX, 0, WORLD.w - canvas.width), dt * 5);
  game.camera.y = lerp(game.camera.y, clamp(targetY, 0, WORLD.h - canvas.height), dt * 5);
  game.shake = Math.max(0, game.shake - dt * 22);
  game.camera.sx = (Math.random() - 0.5) * game.shake;
  game.camera.sy = (Math.random() - 0.5) * game.shake;
}

function render() {
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  ctx.save();
  ctx.translate(-game.camera.x + game.camera.sx, -game.camera.y + game.camera.sy);
  drawNotebookGrid();
  drawPheromones();
  drawWalls();
  drawMatter();
  drawEnemies();
  drawProjectiles();
  drawAnts();
  drawPlayer();
  drawPulses();
  ctx.restore();
}

function drawNotebookGrid() {
  ctx.fillStyle = "#f0e9d8";
  ctx.fillRect(0, 0, WORLD.w, WORLD.h);
  ctx.strokeStyle = "rgba(70,58,38,0.12)";
  ctx.lineWidth = 1;
  for (let x = 0; x <= G.cols; x++) {
    ctx.beginPath();
    ctx.moveTo(x * G.cell, 0);
    ctx.lineTo(x * G.cell, WORLD.h);
    ctx.stroke();
  }
  for (let y = 0; y <= G.rows; y++) {
    ctx.beginPath();
    ctx.moveTo(0, y * G.cell);
    ctx.lineTo(WORLD.w, y * G.cell);
    ctx.stroke();
  }
  const a = levels[game.level].arena;
  ctx.strokeStyle = "rgba(30,127,97,0.38)";
  ctx.lineWidth = 3;
  ctx.strokeRect(a.x * G.cell, a.y * G.cell, a.w * G.cell, a.h * G.cell);
}

function drawPheromones() {
  const order = ["foot", "lead", "hunt", "scatter", "echo", "consume", "home", "danger", "fresh"];
  const sx = clamp(Math.floor(game.camera.x / G.cell) - 2, 0, G.cols - 1);
  const ex = clamp(Math.ceil((game.camera.x + canvas.width) / G.cell) + 2, 0, G.cols - 1);
  const sy = clamp(Math.floor(game.camera.y / G.cell) - 2, 0, G.rows - 1);
  const ey = clamp(Math.ceil((game.camera.y + canvas.height) / G.cell) + 2, 0, G.rows - 1);
  for (const name of order) {
    const [r, g, b] = fieldDefs[name].color;
    const arr = field(name);
    for (let y = sy; y <= ey; y++) {
      for (let x = sx; x <= ex; x++) {
        const v = arr[idx(x, y)];
        if (v <= 0.018) continue;
        const alpha = Math.min(name === "fresh" ? 0.18 : 0.74, v * (name === "foot" ? 0.42 : 0.55));
        ctx.fillStyle = `rgba(${r},${g},${b},${alpha})`;
        ctx.fillRect(x * G.cell, y * G.cell, G.cell, G.cell);
      }
    }
  }
}

function drawWalls() {
  for (let y = 0; y < G.rows; y++) {
    for (let x = 0; x < G.cols; x++) {
      if (!game.solid[idx(x, y)]) continue;
      ctx.fillStyle = game.permanent[idx(x, y)] ? "#6c6850" : "#8a7c5a";
      ctx.fillRect(x * G.cell, y * G.cell, G.cell, G.cell);
      ctx.fillStyle = "rgba(0,0,0,0.14)";
      ctx.fillRect(x * G.cell + G.cell - 2, y * G.cell, 2, G.cell);
      ctx.fillRect(x * G.cell, y * G.cell + G.cell - 2, G.cell, 2);
    }
  }
}

function drawAnts() {
  for (const a of game.ants) {
    const wp = worldFromCell(a.x, a.y);
    const danger = sample("danger", a.x, a.y);
    ctx.fillStyle = danger > 0.1 ? "#ff6b4a" : "#14201f";
    ctx.fillRect(wp.x - 2, wp.y - 2, 4, 4);
    if (sample("hunt", a.x, a.y) > 0.1) {
      ctx.fillStyle = "rgba(255,107,74,0.7)";
      ctx.fillRect(wp.x - 1, wp.y - 1, 2, 2);
    }
  }
}

function drawPlayer() {
  const p = game.player;
  ctx.save();
  ctx.translate(p.x, p.y);
  ctx.scale(p.lastMoveX < -0.1 ? -1 : 1, 1);
  const bob = Math.sin(p.walk) * (Math.abs(p.vx) + Math.abs(p.vy) > 10 ? 2 : 0);
  ctx.globalAlpha = p.invuln > 0 ? 0.65 + Math.sin(game.time * 40) * 0.2 : 1;
  if (p.dash > 0 && playerSprite) {
    ctx.globalAlpha = 0.35;
    ctx.drawImage(playerSprite, -30 - p.lastMoveX * 26, -60 - bob, 60, 108);
    ctx.globalAlpha = 1;
  }
  if (playerSprite) {
    ctx.drawImage(playerSprite, -26, -62 - bob, 52, 112);
  } else {
    ctx.fillStyle = "#080b0d";
    ctx.beginPath();
    ctx.moveTo(0, -28);
    ctx.lineTo(18, 24);
    ctx.lineTo(-18, 24);
    ctx.closePath();
    ctx.fill();
  }
  if (p.cast > 0) {
    ctx.strokeStyle = "rgba(213,163,67,0.9)";
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.arc(0, -18, 26 + Math.sin(game.time * 40) * 4, -0.4, TAU - 0.4);
    ctx.stroke();
  }
  ctx.restore();
}

function drawEnemies() {
  for (const e of game.enemies) {
    const wp = worldFromCell(e.x, e.y);
    const row = e.dead > 0 ? 3 : e.hurt > 0 ? 3 : e.state === "attack" ? 2 : e.state === "run" ? 0 : 1;
    const frame = Math.floor(game.time * (e.state === "attack" ? 12 : 8) + e.x) % (row === 2 ? 9 : row === 1 ? 6 : 8);
    const sx = frame * 80;
    const sy = row * 80;
    ctx.save();
    ctx.translate(wp.x, wp.y);
    ctx.scale(e.vx < -1 ? -1 : 1, 1);
    if (enemySheet) ctx.drawImage(enemySheet, sx, sy, 80, 80, -38, -42, 76, 76);
    else ctx.drawImage(enemyImgs.idle, -34, -43, 68, 68);
    ctx.restore();
    ctx.fillStyle = "rgba(46,40,32,0.8)";
    ctx.fillRect(wp.x - 22, wp.y - 34, 44, 4);
    ctx.fillStyle = e.color;
    ctx.fillRect(wp.x - 22, wp.y - 34, 44 * clamp(e.hp / e.maxHp, 0, 1), 4);
  }
}

function drawMatter() {
  for (const b of game.biomass) {
    const wp = worldFromCell(b.x, b.y);
    ctx.fillStyle = "rgba(110,231,200,0.68)";
    ctx.fillRect(wp.x - 5, wp.y - 5, 10, 10);
  }
  for (const m of game.mines) {
    const wp = worldFromCell(m.x, m.y);
    ctx.strokeStyle = "rgba(255,107,74,0.7)";
    ctx.strokeRect(wp.x - 6, wp.y - 6, 12, 12);
  }
}

function drawProjectiles() {
  ctx.fillStyle = "#c0392b";
  for (const p of game.projectiles) {
    const wp = worldFromCell(p.x, p.y);
    ctx.beginPath();
    ctx.arc(wp.x, wp.y, 5, 0, TAU);
    ctx.fill();
  }
}

function drawPulses() {
  for (const p of game.pulses) {
    const [r, g, b] = p.color;
    const wp = worldFromCell(p.x, p.y);
    ctx.strokeStyle = `rgba(${r},${g},${b},${Math.max(0, p.life)})`;
    ctx.lineWidth = p.arcana ? 4 : 2;
    ctx.beginPath();
    ctx.arc(wp.x, wp.y, p.r * G.cell, 0, TAU);
    ctx.stroke();
    if (p.arcana) {
      ctx.beginPath();
      ctx.arc(wp.x, wp.y, (p.r * 0.55 + 1) * G.cell, 0.3, Math.PI * 1.7);
      ctx.stroke();
    }
  }
}

function updateUi() {
  ui.phase.textContent = `${levels[game.level].phase}`;
  ui.run.textContent = `Run ${game.run}`;
  ui.memory.textContent = `Memory ${memory.memory}`;
  ui.hpText.textContent = Math.ceil(game.player.hp);
  ui.hpBar.style.transform = `scaleX(${clamp(game.player.hp / 100, 0, 1)})`;
  ui.swarmText.textContent = game.ants.length;
  ui.swarmBar.style.transform = `scaleX(${clamp(game.ants.length / Number(ui.devAnts.value), 0, 1)})`;
  ui.resText.textContent = game.resonance > 0.96 ? "Ready" : `${Math.round(game.resonance * 100)}%`;
  ui.resBar.style.transform = `scaleX(${game.resonance})`;
  for (const button of ui.signals.querySelectorAll(".signal")) {
    const id = button.dataset.signal;
    button.classList.toggle("active", game.activeSignal === id);
    button.classList.toggle("cooling", signals[id].cooldownLeft > 0);
    button.querySelector("small").textContent = signals[id].cooldownLeft > 0 ? `${signals[id].cooldownLeft.toFixed(1)}s` : signals[id].sub;
  }
}

function toast(text) {
  ui.toast.textContent = text;
  ui.toast.classList.add("show");
  clearTimeout(toast.t);
  toast.t = setTimeout(() => ui.toast.classList.remove("show"), 2200);
}

function resize() {
  const rect = canvas.getBoundingClientRect();
  const w = Math.floor(rect.width);
  const h = Math.floor(rect.height);
  if (canvas.width !== w || canvas.height !== h) {
    canvas.width = w;
    canvas.height = h;
  }
}

function frame(now) {
  const t = now / 1000;
  const dt = Math.min(0.033, t - (frame.last || t));
  frame.last = t;
  resize();
  update(dt);
  render();
  requestAnimationFrame(frame);
}

function bindInputs() {
  window.addEventListener("keydown", (e) => {
    if (e.code === "Space") {
      dash();
      e.preventDefault();
    }
    for (const [id, sig] of Object.entries(signals)) if (e.code === sig.key) castSignal(id);
    keys.add(e.code);
  });
  window.addEventListener("keyup", (e) => keys.delete(e.code));
  canvas.addEventListener("mousemove", (e) => {
    const r = canvas.getBoundingClientRect();
    pointer.x = game.camera.x + (e.clientX - r.left) * (canvas.width / r.width);
    pointer.y = game.camera.y + (e.clientY - r.top) * (canvas.height / r.height);
    const c = cellFromWorld(pointer.x, pointer.y);
    pointer.cx = c.x;
    pointer.cy = c.y;
  });
  canvas.addEventListener("mousedown", () => {
    pointer.down = true;
    stampLeadAtPointer();
  });
  window.addEventListener("mouseup", () => {
    pointer.down = false;
  });
  ui.devAnts.addEventListener("change", () => loadLevel(game.level));
  ui.devExplore.addEventListener("input", () => params.explore = Number(ui.devExplore.value) / 100);
  ui.devNoise.addEventListener("input", () => params.noise = Number(ui.devNoise.value) / 100);
  ui.devStamp.addEventListener("input", () => params.stamp = Number(ui.devStamp.value) / 100);
  ui.devSat.addEventListener("input", () => params.satCap = Number(ui.devSat.value) / 100);
  ui.devFootDiff.addEventListener("input", () => params.footDiffusion = Number(ui.devFootDiff.value) / 100);
  ui.resetMemory.addEventListener("click", () => {
    localStorage.removeItem(SAVE_KEY);
    location.reload();
  });
}

function init() {
  initFields();
  buildSignalButtons();
  bindInputs();
  loadLevel(0);
  requestAnimationFrame(frame);
}

init();
