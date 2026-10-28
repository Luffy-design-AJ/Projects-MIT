const state = {
  start: { lat: 37.7749, lng: -122.4194 },
  destination: { lat: 37.7694, lng: -122.4862 },
  requiredStops: [],
  routeLayer: null,
  markers: [],
  lastMetrics: null
};

const els = {
  panels: document.querySelectorAll(".panel"),
  tools: document.querySelectorAll(".tool-button"),
  routeStatus: document.getElementById("routeStatus"),
  distanceSelect: document.getElementById("distanceSelect"),
  startInput: document.getElementById("startInput"),
  destinationInput: document.getElementById("destinationInput"),
  destinationField: document.getElementById("destinationField"),
  elevationSlider: document.getElementById("elevationSlider"),
  trafficSlider: document.getElementById("trafficSlider"),
  natureSlider: document.getElementById("natureSlider"),
  elevationValue: document.getElementById("elevationValue"),
  trafficValue: document.getElementById("trafficValue"),
  natureValue: document.getElementById("natureValue"),
  routeButton: document.getElementById("routeButton"),
  clearRoute: document.getElementById("clearRoute"),
  editCurrentRoute: document.getElementById("editCurrentRoute"),
  distanceMetric: document.getElementById("distanceMetric"),
  previousRoute: document.getElementById("previousRoute"),
  nextRoute: document.getElementById("nextRoute"),
  locateButton: document.getElementById("locateButton"),
  undoButton: document.getElementById("undoButton"),
  helpButton: document.getElementById("helpButton"),
  copyShare: document.getElementById("copyShare"),
  shareInput: document.getElementById("shareInput")
};

const map = L.map("map", {
  zoomControl: false
}).setView([37.7749, -122.445], 13);

requestAnimationFrame(() => map.invalidateSize());
window.addEventListener("resize", () => map.invalidateSize());

L.control.zoom({ position: "bottomright" }).addTo(map);

L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
  maxZoom: 19,
  attribution: "&copy; OpenStreetMap contributors"
}).addTo(map);

function switchPanel(name) {
  els.panels.forEach((panel) => {
    panel.classList.toggle("active", panel.id === `${name}Panel`);
  });
  els.tools.forEach((button) => {
    button.classList.toggle("active", button.dataset.panel === name);
  });
}

function updateSliderLabels() {
  els.elevationValue.value = `${els.elevationSlider.value}%`;
  els.trafficValue.value = `${els.trafficSlider.value}%`;
  els.natureValue.value = `${els.natureSlider.value}%`;
}

function currentMode() {
  return document.querySelector("input[name='routeMode']:checked").value;
}

function syncInputs() {
  els.startInput.value = formatPoint(state.start);
  els.destinationInput.value = formatPoint(state.destination);
  els.destinationField.style.display = currentMode() === "loop" ? "none" : "grid";
  updateSliderLabels();
  renderMarkers();
}

async function buildRoute() {
  const parsedStart = parsePoint(els.startInput.value);
  const parsedDestination = parsePoint(els.destinationInput.value);

  if (!parsedStart) {
    setStatus("Start location is not valid.");
    els.startInput.focus();
    return;
  }

  if (currentMode() === "destination" && !parsedDestination) {
    setStatus("Finish location is not valid.");
    els.destinationInput.focus();
    return;
  }

  state.start = parsedStart;
  if (parsedDestination) state.destination = parsedDestination;
  syncInputs();
  setLoading(true);

  try {
    const response = await fetch("/api/route", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        mode: currentMode(),
        start: state.start,
        destination: state.destination,
        requiredStops: state.requiredStops,
        distanceKm: Number(els.distanceSelect.value),
        weights: {
          elevation: Number(els.elevationSlider.value) / 100,
          traffic: Number(els.trafficSlider.value) / 100,
          nature: Number(els.natureSlider.value) / 100
        }
      })
    });

    const result = await response.json();
    if (!response.ok) throw new Error(result.error || "Route request failed");
    drawRoute(result);
    setStatus("Route calculated");
  } catch (error) {
    setStatus(error.message);
  } finally {
    setLoading(false);
  }
}

function drawRoute(result) {
  if (state.routeLayer) state.routeLayer.remove();

  const latLngs = result.path.map((point) => [point.lat, point.lng]);
  state.routeLayer = L.polyline(latLngs, {
    color: "#f22d2d",
    weight: 4,
    opacity: 0.96,
    lineJoin: "round",
    lineCap: "round"
  }).addTo(map);

  state.routeLayer.bindPopup(`
    <div class="route-popup">
      <strong>${formatDistance(result.metrics.distanceKm)}</strong>
      <span>${result.metrics.travelMinutes} min</span>
      <span>Nature ${Math.round(result.metrics.natureScore * 100)}%</span>
    </div>
  `);

  state.lastMetrics = result.metrics;
  renderDistance(result.metrics.distanceKm);
  renderMarkers(result.waypoints);
  map.fitBounds(state.routeLayer.getBounds(), { padding: [70, 70] });
  map.invalidateSize();
}

function renderDistance(distanceKm) {
  els.distanceMetric.textContent = formatDistance(distanceKm);
}

function formatDistance(distanceKm) {
  const useMiles = document.getElementById("mileUnits").checked;
  if (useMiles) return `${(distanceKm * 0.621371).toFixed(2)} mi`;
  return `${Number(distanceKm).toFixed(2)} km`;
}

function renderMarkers(waypoints = null) {
  state.markers.forEach((marker) => marker.remove());
  state.markers = [];

  const points = waypoints || [
    state.start,
    ...(currentMode() === "destination" ? [state.destination] : [])
  ];

  points.forEach((point, index) => {
    const isStart = index === 0;
    const isFinish = index === points.length - 1 && points.length > 1 && currentMode() === "destination";
    const label = isStart ? "1" : String(index + 1);
    const className = isStart ? "start" : isFinish ? "finish" : "stop";
    const marker = L.marker([point.lat, point.lng], {
      icon: numberedIcon(label, className)
    }).addTo(map);
    marker.bindPopup(isStart ? "Start" : isFinish ? "Finish" : `Route point ${index + 1}`);
    state.markers.push(marker);
  });
}

function numberedIcon(label, className) {
  return L.divIcon({
    className: "",
    html: `<span class="trail-pin ${className}">${label}</span>`,
    iconSize: [22, 22],
    iconAnchor: [11, 11]
  });
}

function parsePoint(value) {
  const parts = String(value).split(",").map((part) => Number(part.trim()));
  if (parts.length !== 2 || parts.some((part) => !Number.isFinite(part))) return null;
  return { lat: parts[0], lng: parts[1] };
}

function formatPoint(point) {
  return `${point.lat.toFixed(4)}, ${point.lng.toFixed(4)}`;
}

function mapCenterPoint() {
  const center = map.getCenter();
  return { lat: center.lat, lng: center.lng };
}

function setStatus(text) {
  els.routeStatus.textContent = text;
}

function setLoading(isLoading) {
  els.routeButton.disabled = isLoading;
  els.routeButton.textContent = isLoading ? "…" : "+";
  if (isLoading) setStatus("Calculating route");
}

function varyRoute(direction) {
  const distances = Array.from(els.distanceSelect.options).map((option) => Number(option.value));
  const currentIndex = distances.indexOf(Number(els.distanceSelect.value));
  const nextIndex = Math.min(distances.length - 1, Math.max(0, currentIndex + direction));
  els.distanceSelect.value = String(distances[nextIndex]);
  buildRoute();
}

els.tools.forEach((button) => {
  button.addEventListener("click", () => switchPanel(button.dataset.panel));
});

document.querySelectorAll("input[name='routeMode']").forEach((input) => {
  input.addEventListener("change", () => {
    syncInputs();
    buildRoute();
  });
});

[els.elevationSlider, els.trafficSlider, els.natureSlider].forEach((slider) => {
  slider.addEventListener("input", updateSliderLabels);
  slider.addEventListener("change", buildRoute);
});

els.distanceSelect.addEventListener("change", buildRoute);
els.routeButton.addEventListener("click", buildRoute);
els.previousRoute.addEventListener("click", () => varyRoute(-1));
els.nextRoute.addEventListener("click", () => varyRoute(1));

els.clearRoute.addEventListener("click", () => {
  if (state.routeLayer) state.routeLayer.remove();
  state.routeLayer = null;
  state.requiredStops = [];
  els.distanceMetric.textContent = "-- km";
  setStatus("Route cleared");
  renderMarkers();
});

els.editCurrentRoute.addEventListener("click", () => switchPanel("route"));
els.helpButton.addEventListener("click", () => switchPanel("help"));
els.undoButton.addEventListener("click", () => {
  state.requiredStops.pop();
  buildRoute();
});

els.locateButton.addEventListener("click", () => {
  if (!navigator.geolocation) {
    setStatus("Location unavailable");
    return;
  }

  navigator.geolocation.getCurrentPosition(
    (position) => {
      state.start = {
        lat: position.coords.latitude,
        lng: position.coords.longitude
      };
      syncInputs();
      map.setView([state.start.lat, state.start.lng], 14);
      buildRoute();
    },
    () => setStatus("Location unavailable")
  );
});

document.querySelector("[data-copy-start]").addEventListener("click", () => {
  state.start = mapCenterPoint();
  syncInputs();
});

document.querySelector("[data-copy-destination]").addEventListener("click", () => {
  state.destination = mapCenterPoint();
  syncInputs();
});

els.copyShare.addEventListener("click", async () => {
  const url = `${location.origin}${location.pathname}?start=${encodeURIComponent(formatPoint(state.start))}&distance=${els.distanceSelect.value}`;
  els.shareInput.value = url;
  try {
    await navigator.clipboard.writeText(url);
    els.copyShare.textContent = "Copied";
  } catch {
    els.shareInput.select();
  }
});

document.getElementById("mileUnits").addEventListener("change", () => {
  if (state.lastMetrics) renderDistance(state.lastMetrics.distanceKm);
});

map.on("click", (event) => {
  const point = {
    lat: event.latlng.lat,
    lng: event.latlng.lng
  };

  if (currentMode() === "destination") {
    state.destination = point;
    setStatus("Finish moved");
  } else {
    state.start = point;
    setStatus("Start moved");
  }

  syncInputs();
});

syncInputs();
buildRoute();
