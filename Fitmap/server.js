const http = require("http");
const fs = require("fs");
const path = require("path");
const { URL } = require("url");

const PORT = process.env.PORT || 5173;
const HOST = process.env.HOST || "127.0.0.1";
const PUBLIC_DIR = path.join(__dirname, "public");

const bounds = {
  minLat: 37.735,
  maxLat: 37.815,
  minLng: -122.51,
  maxLng: -122.37
};

const naturalAreas = [
  { lat: 37.7694, lng: -122.4862, radiusKm: 1.35, strength: 1, name: "Golden Gate Park" },
  { lat: 37.806, lng: -122.475, radiusKm: 1.4, strength: 0.92, name: "Presidio" },
  { lat: 37.7598, lng: -122.4269, radiusKm: 0.75, strength: 0.72, name: "Dolores Park" },
  { lat: 37.768, lng: -122.451, radiusKm: 0.85, strength: 0.85, name: "Buena Vista / Panhandle" },
  { lat: 37.806, lng: -122.425, radiusKm: 0.9, strength: 0.76, name: "Bay waterfront" },
  { lat: 37.755, lng: -122.505, radiusKm: 1.2, strength: 0.9, name: "Ocean Beach" }
];

const hills = [
  { lat: 37.7544, lng: -122.4477, radiusKm: 0.9, height: 280 },
  { lat: 37.7596, lng: -122.4469, radiusKm: 0.7, height: 210 },
  { lat: 37.8024, lng: -122.4182, radiusKm: 0.7, height: 160 },
  { lat: 37.7825, lng: -122.4336, radiusKm: 0.8, height: 125 }
];

const graph = buildGraph(54, 42);

function buildGraph(cols, rows) {
  const nodes = [];
  const byKey = new Map();

  for (let row = 0; row < rows; row += 1) {
    for (let col = 0; col < cols; col += 1) {
      const lat = lerp(bounds.minLat, bounds.maxLat, row / (rows - 1));
      const lng = lerp(bounds.minLng, bounds.maxLng, col / (cols - 1));
      const node = {
        id: `${col}:${row}`,
        col,
        row,
        lat,
        lng,
        elevation: elevationAt(lat, lng),
        nature: natureAt(lat, lng),
        traffic: trafficAt(lat, lng)
      };
      nodes.push(node);
      byKey.set(node.id, node);
    }
  }

  const nodeById = new Map(nodes.map((node) => [node.id, node]));
  const adjacency = new Map(nodes.map((node) => [node.id, []]));
  const directions = [
    [1, 0],
    [-1, 0],
    [0, 1],
    [0, -1],
    [1, 1],
    [1, -1],
    [-1, 1],
    [-1, -1]
  ];

  for (const node of nodes) {
    for (const [dc, dr] of directions) {
      const neighbor = byKey.get(`${node.col + dc}:${node.row + dr}`);
      if (!neighbor) continue;
      const midpoint = {
        lat: (node.lat + neighbor.lat) / 2,
        lng: (node.lng + neighbor.lng) / 2
      };
      const distanceKm = haversineKm(node, neighbor);
      const traffic = (node.traffic + neighbor.traffic + trafficAt(midpoint.lat, midpoint.lng)) / 3;
      const nature = (node.nature + neighbor.nature + natureAt(midpoint.lat, midpoint.lng)) / 3;
      const elevationGainM = Math.max(0, neighbor.elevation - node.elevation);
      adjacency.get(node.id).push({
        to: neighbor.id,
        distanceKm,
        traffic,
        nature,
        elevationGainM
      });
    }
  }

  return { nodes, nodeById, adjacency };
}

function route(req, res, body) {
  try {
    const input = JSON.parse(body || "{}");
    const start = sanitizePoint(input.start) || { lat: 37.7749, lng: -122.4194 };
    const destination = sanitizePoint(input.destination) || { lat: 37.7694, lng: -122.4862 };
    const requiredStops = Array.isArray(input.requiredStops)
      ? input.requiredStops.map(sanitizePoint).filter(Boolean)
      : [];
    const weights = normalizeWeights(input.weights || {});
    const mode = input.mode === "loop" ? "loop" : "destination";
    const targetDistanceKm = clamp(Number(input.distanceKm) || 8, 1, 80);

    const best = findBestTargetRoute({
      mode,
      start,
      destination,
      requiredStops,
      targetDistanceKm,
      weights
    });

    if (!best) {
      sendJson(res, 422, { error: "No route found for the requested waypoints." });
      return;
    }

    sendJson(res, 200, {
      mode,
      waypoints: best.waypoints,
      path: best.route.path,
      metrics: best.metrics,
      legend: {
        elevation: "Higher slider values avoid elevation gain.",
        traffic: "Higher slider values avoid congested edges and reduce estimated delay.",
        nature: "Higher slider values reward rivers, beaches, parks, forests, and green corridors."
      }
    });
  } catch (error) {
    sendJson(res, 400, { error: error.message });
  }
}

function findBestTargetRoute({ mode, start, destination, requiredStops, targetDistanceKm, weights }) {
  const candidates = mode === "loop"
    ? buildLoopWaypointCandidates(start, requiredStops, targetDistanceKm)
    : buildDestinationWaypointCandidates(start, requiredStops, destination, targetDistanceKm);
  let best = null;

  for (const waypoints of candidates) {
    const routeResult = routeWaypoints(waypoints, weights);
    if (!routeResult) continue;
    const metrics = summarizeRoute(routeResult.path, routeResult.edges, targetDistanceKm);
    const targetMissKm = Math.abs(metrics.distanceKm - targetDistanceKm);
    const candidate = { waypoints, route: routeResult, metrics, targetMissKm };
    if (!best || candidate.targetMissKm < best.targetMissKm) {
      best = candidate;
    }
  }

  return best;
}

function routeWaypoints(waypoints, weights) {
  const routeParts = [];
  for (let i = 0; i < waypoints.length - 1; i += 1) {
    const part = aStar(nearestNode(waypoints[i]), nearestNode(waypoints[i + 1]), weights);
    if (!part) return null;
    routeParts.push(part);
  }
  return mergeRouteParts(routeParts);
}

function aStar(startNode, goalNode, weights) {
  const open = new MinHeap();
  const cameFrom = new Map();
  const edgeFrom = new Map();
  const gScore = new Map([[startNode.id, 0]]);
  const closed = new Set();

  open.push({ id: startNode.id, score: heuristic(startNode, goalNode) });

  while (!open.isEmpty()) {
    const current = graph.nodeById.get(open.pop().id);
    if (closed.has(current.id)) continue;
    closed.add(current.id);

    if (current.id === goalNode.id) {
      return reconstructPath(current.id, cameFrom, edgeFrom);
    }

    for (const edge of graph.adjacency.get(current.id)) {
      const neighbor = graph.nodeById.get(edge.to);
      const tentative = (gScore.get(current.id) ?? Infinity) + edgeCost(edge, weights);
      if (tentative < (gScore.get(neighbor.id) ?? Infinity)) {
        cameFrom.set(neighbor.id, current.id);
        edgeFrom.set(neighbor.id, edge);
        gScore.set(neighbor.id, tentative);
        open.push({
          id: neighbor.id,
          score: tentative + heuristic(neighbor, goalNode)
        });
      }
    }
  }

  return null;
}

function edgeCost(edge, weights) {
  const elevationCost = (edge.elevationGainM / 100) * weights.elevation * 1.8;
  const trafficCost = edge.distanceKm * edge.traffic * weights.traffic * 2.4;
  const natureReward = edge.distanceKm * edge.nature * weights.nature * 1.8;
  return Math.max(0.03, edge.distanceKm + elevationCost + trafficCost - natureReward);
}

function reconstructPath(goalId, cameFrom, edgeFrom) {
  const ids = [goalId];
  const edges = [];
  let cursor = goalId;

  while (cameFrom.has(cursor)) {
    edges.push(edgeFrom.get(cursor));
    cursor = cameFrom.get(cursor);
    ids.push(cursor);
  }

  ids.reverse();
  edges.reverse();
  return {
    path: ids.map((id) => graph.nodeById.get(id)),
    edges
  };
}

function buildLoopWaypointCandidates(start, requiredStops, targetDistanceKm) {
  if (requiredStops.length > 0) {
    return [
      [start, ...requiredStops, start],
      ...buildStopLoopDetours(start, requiredStops, targetDistanceKm)
    ];
  }

  const bearings = [35, 145, 245];
  const baseRadiusKm = Math.max(0.45, targetDistanceKm / (2 * Math.PI));
  const scales = [0.85, 1, 1.08, 1.15, 1.25, 1.4];
  return scales.map((scale) => {
    const radiusKm = baseRadiusKm * scale;
    return [
      start,
      offsetPoint(start, radiusKm, bearings[0]),
      offsetPoint(start, radiusKm * 1.15, bearings[1]),
      offsetPoint(start, radiusKm * 0.95, bearings[2]),
      start
    ];
  });
}

function buildDestinationWaypointCandidates(start, requiredStops, destination, targetDistanceKm) {
  const base = [start, ...requiredStops, destination];
  const minimumStraightKm = waypointStraightDistance(base);
  const extraKm = targetDistanceKm - minimumStraightKm;
  if (extraKm <= 0.4) return [base];

  const anchor = requiredStops.at(-1) || start;
  const heading = bearingBetween(anchor, destination);
  const midpoint = interpolatePoint(anchor, destination, 0.5);
  const candidates = [base];
  const sides = [-1, 1];
  const scales = [0.35, 0.65, 1, 1.35];

  for (const side of sides) {
    for (const scale of scales) {
      const detourKm = Math.max(0.35, extraKm * scale);
      const scenicPull = offsetPoint(midpoint, detourKm, heading + side * 90);
      candidates.push([start, ...requiredStops, scenicPull, destination]);

      const splitA = offsetPoint(interpolatePoint(anchor, destination, 0.34), detourKm * 0.7, heading + side * 90);
      const splitB = offsetPoint(interpolatePoint(anchor, destination, 0.66), detourKm * 0.7, heading + side * 90);
      candidates.push([start, ...requiredStops, splitA, splitB, destination]);
    }
  }

  return candidates;
}

function buildStopLoopDetours(start, requiredStops, targetDistanceKm) {
  const base = [start, ...requiredStops, start];
  const minimumStraightKm = waypointStraightDistance(base);
  const extraKm = targetDistanceKm - minimumStraightKm;
  if (extraKm <= 0.4) return [];

  const anchor = requiredStops.at(-1);
  const heading = bearingBetween(anchor, start);
  const midpoint = interpolatePoint(anchor, start, 0.5);
  return [-1, 1].flatMap((side) => [0.45, 0.7, 1.0, 1.35].map((scale) => {
    const detour = offsetPoint(midpoint, Math.max(0.35, extraKm * scale), heading + side * 90);
    return [start, ...requiredStops, detour, start];
  }));
}

function mergeRouteParts(parts) {
  const path = [];
  const edges = [];
  for (const part of parts) {
    path.push(...(path.length ? part.path.slice(1) : part.path));
    edges.push(...part.edges);
  }
  return { path, edges };
}

function summarizeRoute(path, edges, targetDistanceKm = null) {
  const distanceKm = edges.reduce((sum, edge) => sum + edge.distanceKm, 0);
  const elevationGainM = edges.reduce((sum, edge) => sum + edge.elevationGainM, 0);
  const weightedTraffic = weightedAverage(edges, "traffic");
  const weightedNature = weightedAverage(edges, "nature");
  const baseMinutes = (distanceKm / 8.5) * 60;
  const trafficDelayMinutes = baseMinutes * weightedTraffic * 0.42;
  const travelMinutes = baseMinutes + trafficDelayMinutes;

  return {
    distanceKm: round(distanceKm, 2),
    elevationGainM: Math.round(elevationGainM),
    trafficLevel: round(weightedTraffic, 2),
    natureScore: round(weightedNature, 2),
    travelMinutes: Math.round(travelMinutes),
    trafficDelayMinutes: Math.round(trafficDelayMinutes),
    targetDistanceKm,
    targetMissKm: targetDistanceKm == null ? null : round(distanceKm - targetDistanceKm, 2),
    points: path.length
  };
}

function waypointStraightDistance(waypoints) {
  let total = 0;
  for (let i = 0; i < waypoints.length - 1; i += 1) {
    total += haversineKm(waypoints[i], waypoints[i + 1]);
  }
  return total;
}

function weightedAverage(edges, key) {
  const totalDistance = edges.reduce((sum, edge) => sum + edge.distanceKm, 0);
  if (!totalDistance) return 0;
  return edges.reduce((sum, edge) => sum + edge[key] * edge.distanceKm, 0) / totalDistance;
}

function nearestNode(point) {
  let best = graph.nodes[0];
  let bestDistance = Infinity;
  for (const node of graph.nodes) {
    const distance = haversineKm(point, node);
    if (distance < bestDistance) {
      best = node;
      bestDistance = distance;
    }
  }
  return best;
}

function normalizeWeights(weights) {
  return {
    elevation: clamp(Number(weights.elevation) || 0, 0, 1),
    traffic: clamp(Number(weights.traffic) || 0, 0, 1),
    nature: clamp(Number(weights.nature) || 0, 0, 1)
  };
}

function sanitizePoint(point) {
  if (!point) return null;
  const lat = Number(point.lat);
  const lng = Number(point.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  return {
    lat: clamp(lat, bounds.minLat, bounds.maxLat),
    lng: clamp(lng, bounds.minLng, bounds.maxLng)
  };
}

function elevationAt(lat, lng) {
  const base = 8 + 18 * Math.sin((lng + 122.46) * 70) * Math.cos((lat - 37.76) * 45);
  const hillBoost = hills.reduce((sum, hill) => {
    const d = haversineKm({ lat, lng }, hill);
    return sum + hill.height * Math.exp(-(d * d) / (2 * hill.radiusKm * hill.radiusKm));
  }, 0);
  return Math.max(0, base + hillBoost);
}

function natureAt(lat, lng) {
  const score = naturalAreas.reduce((max, area) => {
    const d = haversineKm({ lat, lng }, area);
    const value = area.strength * Math.exp(-(d * d) / (2 * area.radiusKm * area.radiusKm));
    return Math.max(max, value);
  }, 0);
  return clamp(score, 0, 1);
}

function trafficAt(lat, lng) {
  const downtown = Math.exp(-(haversineKm({ lat, lng }, { lat: 37.789, lng: -122.401 }) ** 2) / 5.2);
  const marketStreet = Math.exp(-Math.abs(lat - 37.775 - (lng + 122.42) * 0.09) * 90);
  const northSouth = Math.exp(-Math.abs(lng + 122.42) * 65);
  return clamp(0.12 + downtown * 0.65 + marketStreet * 0.32 + northSouth * 0.22, 0, 1);
}

function heuristic(a, b) {
  return haversineKm(a, b);
}

function haversineKm(a, b) {
  const radius = 6371;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const lat1 = toRad(a.lat);
  const lat2 = toRad(b.lat);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
  return 2 * radius * Math.asin(Math.sqrt(h));
}

function offsetPoint(origin, distanceKm, bearingDeg) {
  const radius = 6371;
  const bearing = toRad(bearingDeg);
  const lat1 = toRad(origin.lat);
  const lng1 = toRad(origin.lng);
  const ratio = distanceKm / radius;
  const lat2 = Math.asin(Math.sin(lat1) * Math.cos(ratio) + Math.cos(lat1) * Math.sin(ratio) * Math.cos(bearing));
  const lng2 = lng1 + Math.atan2(
    Math.sin(bearing) * Math.sin(ratio) * Math.cos(lat1),
    Math.cos(ratio) - Math.sin(lat1) * Math.sin(lat2)
  );
  return sanitizePoint({ lat: toDeg(lat2), lng: toDeg(lng2) });
}

function interpolatePoint(a, b, t) {
  return sanitizePoint({
    lat: lerp(a.lat, b.lat, t),
    lng: lerp(a.lng, b.lng, t)
  });
}

function bearingBetween(a, b) {
  const lat1 = toRad(a.lat);
  const lat2 = toRad(b.lat);
  const dLng = toRad(b.lng - a.lng);
  const y = Math.sin(dLng) * Math.cos(lat2);
  const x = Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLng);
  return (toDeg(Math.atan2(y, x)) + 360) % 360;
}

function serveStatic(req, res) {
  const reqUrl = new URL(req.url, `http://${req.headers.host}`);
  const requestedPath = reqUrl.pathname === "/" ? "/index.html" : reqUrl.pathname;
  const filePath = path.normalize(path.join(PUBLIC_DIR, requestedPath));

  if (!filePath.startsWith(PUBLIC_DIR)) {
    sendText(res, 403, "Forbidden");
    return;
  }

  fs.readFile(filePath, (error, content) => {
    if (error) {
      sendText(res, 404, "Not found");
      return;
    }
    res.writeHead(200, { "Content-Type": contentType(filePath) });
    res.end(content);
  });
}

function contentType(filePath) {
  const ext = path.extname(filePath);
  return {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".json": "application/json; charset=utf-8"
  }[ext] || "application/octet-stream";
}

function sendJson(res, status, value) {
  res.writeHead(status, { "Content-Type": "application/json; charset=utf-8" });
  res.end(JSON.stringify(value));
}

function sendText(res, status, text) {
  res.writeHead(status, { "Content-Type": "text/plain; charset=utf-8" });
  res.end(text);
}

function readBody(req, callback) {
  let body = "";
  req.on("data", (chunk) => {
    body += chunk;
    if (body.length > 1e6) req.destroy();
  });
  req.on("end", () => callback(body));
}

function lerp(a, b, t) {
  return a + (b - a) * t;
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function round(value, decimals) {
  const factor = 10 ** decimals;
  return Math.round(value * factor) / factor;
}

function toRad(deg) {
  return deg * Math.PI / 180;
}

function toDeg(rad) {
  return rad * 180 / Math.PI;
}

class MinHeap {
  constructor() {
    this.items = [];
  }

  isEmpty() {
    return this.items.length === 0;
  }

  push(item) {
    this.items.push(item);
    this.bubbleUp(this.items.length - 1);
  }

  pop() {
    const root = this.items[0];
    const end = this.items.pop();
    if (this.items.length > 0) {
      this.items[0] = end;
      this.sinkDown(0);
    }
    return root;
  }

  bubbleUp(index) {
    while (index > 0) {
      const parentIndex = Math.floor((index - 1) / 2);
      if (this.items[parentIndex].score <= this.items[index].score) break;
      [this.items[parentIndex], this.items[index]] = [this.items[index], this.items[parentIndex]];
      index = parentIndex;
    }
  }

  sinkDown(index) {
    while (true) {
      const left = index * 2 + 1;
      const right = left + 1;
      let smallest = index;
      if (left < this.items.length && this.items[left].score < this.items[smallest].score) smallest = left;
      if (right < this.items.length && this.items[right].score < this.items[smallest].score) smallest = right;
      if (smallest === index) break;
      [this.items[smallest], this.items[index]] = [this.items[index], this.items[smallest]];
      index = smallest;
    }
  }
}

const server = http.createServer((req, res) => {
  const reqUrl = new URL(req.url, `http://${req.headers.host}`);

  if (req.method === "GET" && reqUrl.pathname === "/api/health") {
    sendJson(res, 200, { ok: true, nodes: graph.nodes.length });
    return;
  }

  if (req.method === "POST" && reqUrl.pathname === "/api/route") {
    readBody(req, (body) => route(req, res, body));
    return;
  }

  if (req.method === "GET") {
    serveStatic(req, res);
    return;
  }

  sendText(res, 405, "Method not allowed");
});

server.listen(PORT, HOST, () => {
  console.log(`Fitmap prototype running at http://${HOST}:${PORT}`);
});
