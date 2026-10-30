"use strict";
const TOKEN = document.querySelector("meta[name=token]").content;
const $ = (s) => document.querySelector(s);
const PAGE_LOADED = Date.now() / 1000;
const FS = 800, TRIG = 24;

const S = { status: null, report: null, rows: [], thr: [], taps: [], paused: false, pausedEnd: 0, cfgSynced: false };

async function api(cmd, body = {}) {
  const r = await fetch("/api/" + cmd, {
    method: "POST", headers: { "Content-Type": "application/json", "X-Token": TOKEN }, body: JSON.stringify(body),
  });
  const j = await r.json();
  if (!r.ok) { alert(j.error || r.statusText); throw new Error(j.error); }
  if (j.report !== undefined) setReport(j.report);
  if (j.status) onStatus(j.status);
  return j;
}

const css = (v) => getComputedStyle(document.documentElement).getPropertyValue(v).trim();
const COL = {};
for (const k of ["x", "y", "z", "mag", "thr", "good", "accent", "warn", "gate", "line", "muted", "text", "bad"]) COL[k] = css("--" + k);
const AXES = [COL.x, COL.y, COL.z];
const OUTCOME_COLOR = { predicted: COL.good, recorded: COL.accent, rejected: COL.warn, gated: COL.gate, detected: COL.text };

const zoneNum = (label) => (label && label[0] === "z" ? +label.slice(1) + 1 : null);
const zoneName = (label) => (label === "noise" ? "noise" : label ? "Zone " + zoneNum(label) : "–");
function labelColor(label, nZones) {
  if (label === "noise") return COL.gate;
  return `hsl(${(zoneNum(label) - 1) * 360 / Math.max(nZones, 1)}, 70%, 62%)`;
}
const pct = (v) => (v == null ? "–" : Math.round(v * 100) + "%");
const fmt = (v, d = 2) => (v == null ? "–" : (+v).toFixed(d));

function canvas2d(cv) {
  const dpr = window.devicePixelRatio || 1;
  const w = cv.clientWidth, h = cv.clientHeight;
  if (cv.width !== Math.round(w * dpr) || cv.height !== Math.round(h * dpr)) {
    cv.width = Math.round(w * dpr); cv.height = Math.round(h * dpr);
  }
  const c = cv.getContext("2d");
  c.setTransform(dpr, 0, 0, dpr, 0, 0);
  c.clearRect(0, 0, w, h);
  c.font = "11px -apple-system, system-ui, sans-serif";
  return [c, w, h];
}

// ---------------------------------------------------------------- tabs
for (const b of document.querySelectorAll("#tabs button")) {
  b.onclick = () => {
    document.querySelectorAll("#tabs button").forEach((x) => x.classList.toggle("on", x === b));
    document.querySelectorAll(".tab").forEach((t) => t.classList.toggle("on", t.id === b.dataset.tab));
    if (b.dataset.tab === "model") renderReport();
  };
}

// ---------------------------------------------------------------- stream
function connect() {
  const es = new EventSource("/stream");
  es.addEventListener("samples", (e) => {
    const m = JSON.parse(e.data);
    for (const r of m.rows) S.rows.push(r);
    if (m.rows.length) S.thr.push([m.rows[m.rows.length - 1][0], m.thr]);
    if (S.rows.length > 6000) S.rows = S.rows.slice(-4000);
    if (S.thr.length > 1500) S.thr = S.thr.slice(-1000);
  });
  es.addEventListener("tap", (e) => onTap(JSON.parse(e.data)));
  es.addEventListener("status", (e) => onStatus(JSON.parse(e.data)));
  es.onerror = () => { $("#pSensors").textContent = "Disconnected"; $("#pSensors").className = "pill bad"; };
}

// ---------------------------------------------------------------- scope
const lanes = { g: 10, m: 5, a: 0.01 };
function drawScope() {
  requestAnimationFrame(drawScope);
  if (!$("#monitor").classList.contains("on")) return;
  const [c, w, h] = canvas2d($("#scope"));
  const rows = S.rows;
  if (!rows.length) { c.fillStyle = COL.muted; c.fillText("Waiting for sensor data…", 12, 20); return; }
  const win = +$("#scopeWin").value;
  const tEnd = S.paused ? S.pausedEnd : rows[rows.length - 1][0];
  const t0 = tEnd - win;
  let i0 = rows.length - 1;
  while (i0 > 0 && rows[i0][0] > t0) i0--;
  const vis = rows.slice(i0);
  const X = (t) => ((t - t0) / win) * w;
  const H = [0.40, 0.25, 0.35].map((f) => f * (h - 18));
  const tops = [0, H[0], H[0] + H[1]];

  let gMax = 0, mMax = 0, aMax = 0;
  for (const r of vis) {
    gMax = Math.max(gMax, Math.abs(r[1]), Math.abs(r[2]), Math.abs(r[3]));
    aMax = Math.max(aMax, Math.abs(r[4]), Math.abs(r[5]), Math.abs(r[6]));
    mMax = Math.max(mMax, r[7]);
  }
  const thrNow = S.thr.length ? S.thr[S.thr.length - 1][1] : 1;
  const ease = (cur, target) => (target > cur ? target : cur + (target - cur) * 0.05);
  lanes.g = ease(lanes.g, Math.max(2, gMax * 1.15));
  lanes.m = ease(lanes.m, Math.max(thrNow * 1.6, mMax * 1.1));
  lanes.a = ease(lanes.a, Math.max(0.004, aMax * 1.15));

  // lane frames
  c.strokeStyle = COL.line; c.lineWidth = 1;
  for (let k = 0; k < 3; k++) {
    c.strokeRect(0.5, tops[k] + 0.5, w - 1, H[k] - 1);
  }
  for (let s = 0; s <= win; s++) {
    const x = Math.round(X(tEnd - s)) + 0.5;
    c.beginPath(); c.moveTo(x, 0); c.lineTo(x, h - 18); c.stroke();
    c.fillStyle = COL.muted; c.fillText(s === 0 ? "now" : `-${s}s`, Math.min(x + 3, w - 26), h - 4);
  }
  const lane = (k, idxs, scale, symmetric, colors) => {
    const top = tops[k], ht = H[k];
    const Y = symmetric ? (v) => top + ht / 2 - (v / scale) * (ht / 2 - 4) : (v) => top + ht - 3 - (v / scale) * (ht - 8);
    if (symmetric) { c.strokeStyle = COL.line; c.beginPath(); c.moveTo(0, top + ht / 2); c.lineTo(w, top + ht / 2); c.stroke(); }
    idxs.forEach((col, j) => {
      c.strokeStyle = colors[j]; c.lineWidth = 1.2; c.beginPath();
      vis.forEach((r, n) => { const x = X(r[0]), y = Y(r[col]); n ? c.lineTo(x, y) : c.moveTo(x, y); });
      c.stroke();
    });
    return Y;
  };
  lane(0, [1, 2, 3], lanes.g, true, AXES);
  const Ym = lane(1, [7], lanes.m, false, [COL.mag]);
  lane(2, [4, 5, 6], lanes.a, true, AXES);
  // trigger line
  c.strokeStyle = COL.thr; c.setLineDash([5, 4]); c.beginPath();
  let started = false;
  for (const [t, v] of S.thr) {
    if (t < t0) continue;
    const x = X(t), y = Ym(Math.min(v, lanes.m));
    started ? c.lineTo(x, y) : (c.moveTo(0, y), c.lineTo(x, y), (started = true));
  }
  c.stroke(); c.setLineDash([]);
  // tap markers
  for (const tp of S.taps) {
    if (tp.t < t0 || tp.t > tEnd) continue;
    const x = Math.round(X(tp.t)) + 0.5;
    c.strokeStyle = OUTCOME_COLOR[tp.outcome] || COL.text; c.lineWidth = 2;
    c.beginPath(); c.moveTo(x, 0); c.lineTo(x, h - 18); c.stroke();
    c.fillStyle = c.strokeStyle; c.fillText(tp.text, x + 4, 12);
  }
  c.fillStyle = COL.muted;
  c.fillText(`gyro twist  ±${fmt(lanes.g, 1)} °/s`, 6, tops[0] + 13);
  c.fillText(`|twist|  0–${fmt(lanes.m, 1)} °/s   trigger ${fmt(thrNow, 2)}`, 6, tops[1] + 13);
  c.fillText(`accel shake  ±${fmt(lanes.a, 3)} g`, 6, tops[2] + 13);
}
$("#pauseBtn").onclick = () => {
  S.paused = !S.paused;
  S.pausedEnd = S.rows.length ? S.rows[S.rows.length - 1][0] : 0;
  $("#pauseBtn").textContent = S.paused ? "Resume" : "Pause";
};

// ---------------------------------------------------------------- detector settings
const SLIDERS = { k: "#vK", min_thresh: "#vMin", refractory: "#vRef", gate_s: "#vGate", reject_factor: "#vRej" };
for (const [key, out] of Object.entries(SLIDERS)) {
  const el = document.getElementById(key);
  el.oninput = () => ($(out).textContent = el.value);
  el.onchange = () => api("config", { [key]: +el.value });
}
$("#gating").onchange = (e) => api("config", { gating: e.target.checked });

function syncConfig(cfg) {
  for (const [key, out] of Object.entries(SLIDERS)) {
    const el = document.getElementById(key);
    if (document.activeElement !== el) { el.value = cfg[key]; $(out).textContent = cfg[key]; }
  }
  $("#gating").checked = cfg.gating;
  $("#actionsOn").checked = cfg.actions_enabled;
}

// ---------------------------------------------------------------- taps
function tapSummary(ev) {
  if (ev.outcome === "gated") return `ignored: ${ev.gated}`;
  if (ev.outcome === "recorded") return ev.label === "noise" ? "noise example" : `recorded for ${zoneName(ev.label)}`;
  if (ev.outcome === "predicted") return `${zoneName(ev.pred.label)} · ${pct(ev.pred.conf)}`;
  if (ev.outcome === "rejected") return `${ev.pred.rejected} (nearest ${zoneName(ev.pred.label)})`;
  return "tap detected (no model yet)";
}

function onTap(ev) {
  const short = ev.outcome === "predicted" ? zoneNum(ev.pred.label)
    : ev.outcome === "recorded" ? (ev.label === "noise" ? "n" : zoneNum(ev.label)) : "";
  S.taps.push({ t: ev.t, outcome: ev.outcome, text: String(short) });
  if (S.taps.length > 200) S.taps.shift();
  S.lastTap = ev;
  drawTap(ev);
  addLog($("#log"), ev, tapSummary(ev));
  const fresh = ev.wall > PAGE_LOADED - 0.5;
  if (!fresh) return;
  if (ev.outcome === "recorded" && ev.label !== "noise") flash(zoneCell("#calGrid", ev.label), "flash-rec");
  if (ev.outcome === "gated") { flash($("#calGrid"), "flash-gate"); flash($("#liveGrid"), "flash-gate"); }
  if (ev.pred) {
    addLog($("#liveLog"), ev, tapSummary(ev));
    if (ev.outcome === "predicted") {
      flash(zoneCell("#liveGrid", ev.pred.label), ev.pred.conf >= 0.6 ? "flash-ok" : "flash-weak", 450);
      $("#liveMsg").innerHTML = `<b>${zoneName(ev.pred.label)}</b> · ${pct(ev.pred.conf)} confident · novelty ${fmt(ev.pred.novelty, 1)}${ev.action ? " · ran action" : ""}`;
    } else {
      flash($("#liveGrid"), "flash-rej", 450);
      $("#liveMsg").innerHTML = `Rejected: ${ev.pred.rejected} (closest ${zoneName(ev.pred.label)}, novelty ${fmt(ev.pred.novelty, 1)})`;
    }
  } else if (ev.outcome === "gated") {
    $("#liveMsg").textContent = `Ignored (${ev.gated})`;
  }
}

function addLog(ol, ev, text) {
  const li = document.createElement("li");
  const time = new Date(ev.wall * 1000).toLocaleTimeString([], { hour12: false });
  li.innerHTML = `<span class="muted">${time}</span><span class="tag t-${ev.outcome}">${ev.outcome}</span><span></span>`;
  li.lastChild.textContent = `${text} · ${fmt(ev.peak_g, 1)}°/s`;
  ol.prepend(li);
  while (ol.children.length > 60) ol.lastChild.remove();
}

function drawTap(ev) {
  const [c, w, h] = canvas2d($("#tapWave"));
  const g = ev.g, n = g.length;
  let m = 0.5;
  for (const r of g) m = Math.max(m, Math.abs(r[0]), Math.abs(r[1]), Math.abs(r[2]));
  const X = (i) => (i / (n - 1)) * w, Y = (v) => h / 2 - (v / (m * 1.1)) * (h / 2 - 6);
  c.strokeStyle = COL.line; c.beginPath(); c.moveTo(0, h / 2); c.lineTo(w, h / 2); c.stroke();
  c.setLineDash([4, 4]); c.strokeStyle = COL.thr; c.beginPath(); c.moveTo(X(TRIG), 0); c.lineTo(X(TRIG), h); c.stroke(); c.setLineDash([]);
  for (let a = 0; a < 3; a++) {
    c.strokeStyle = AXES[a]; c.lineWidth = 1.5; c.beginPath();
    g.forEach((r, i) => (i ? c.lineTo(X(i), Y(r[a])) : c.moveTo(X(i), Y(r[a]))));
    c.stroke();
  }
  c.fillStyle = COL.muted;
  c.fillText(`gyro twist, ±${fmt(m * 1.1, 1)} °/s · ${Math.round((n / FS) * 1000)} ms window · dashed = trigger`, 6, 12);
  $("#tapWhen").textContent = new Date(ev.wall * 1000).toLocaleTimeString([], { hour12: false });
  const rows = [
    ["Outcome", `<span class="t-${ev.outcome}">${tapSummary(ev)}</span>`],
    ["Peak twist", `${fmt(ev.peak_g, 2)} °/s`],
    ["Peak shake", `${fmt(ev.peak_a, 4)} g`],
    ["Twist / shake", `${fmt(ev.ratio, 0)} (°/s)/g`],
    ["Trigger / noise", `${fmt(ev.threshold, 2)} / ${fmt(ev.noise, 2)} °/s`],
    ["Lid angle", ev.lid == null ? "–" : ev.lid + "°"],
  ];
  if (ev.pred) rows.push(["Novelty", `${fmt(ev.pred.novelty, 2)} (reject > ${S.status ? S.status.cfg.reject_factor : "?"})`]);
  $("#tapInfo").innerHTML = rows.map(([k, v]) => `<dt>${k}</dt><dd>${v}</dd>`).join("");
}

function flash(el, cls, ms = 350) {
  if (!el) return;
  el.classList.remove(cls); void el.offsetWidth; el.classList.add(cls);
  setTimeout(() => el.classList.remove(cls), ms);
}

// ---------------------------------------------------------------- grids
function buildGrid(el, rows, cols) {
  const shape = `${rows}x${cols}`;
  if (el.dataset.shape === shape) return false;
  el.dataset.shape = shape;
  el.style.gridTemplateColumns = `repeat(${cols}, 1fr)`;
  el.style.gridTemplateRows = `repeat(${rows}, 1fr)`;
  el.innerHTML = "";
  for (let i = 0; i < rows * cols; i++) {
    const d = document.createElement("div");
    d.className = "zone"; d.dataset.label = "z" + i;
    d.innerHTML = `<div class="num">${i + 1}</div><div class="cnt"></div><div class="bar"></div>`;
    el.appendChild(d);
  }
  return true;
}
const zoneCell = (grid, label) => $(grid).querySelector(`[data-label="${label}"]`);
$("#calFull").onclick = () => $("#calWrap").requestFullscreen();
$("#liveFull").onclick = () => $("#liveWrap").requestFullscreen();

// ---------------------------------------------------------------- status
let dsKey = "";
function onStatus(st) {
  S.status = st;
  const p = (id, text, cls = "") => { const el = $(id); el.textContent = text; el.className = "pill " + cls; };
  const rate = Math.min(st.rates.gyro || 0, st.rates.accel || 0);
  p("#pSensors", `IMU ${st.rates.gyro || 0} Hz`, rate > 500 ? "ok" : "bad");
  p("#pLid", st.lid == null ? "Lid –" : `Lid ${st.lid}°`);
  p("#pNoise", `Noise ${fmt(st.noise, 2)} °/s`);
  p("#pThr", `Trigger ${fmt(st.threshold, 2)} °/s`);
  const modeText = { idle: st.model ? "Live" : "Monitoring", calibrate: "Calibrating", negatives: `Recording noise ${Math.max(0, st.neg_left || 0).toFixed(0)}s` }[st.mode];
  p("#pMode", modeText, st.mode === "idle" ? "" : "hot");
  p("#pModel", st.model ? `${st.model.name} · ${pct(st.model.acc)}` : "No model", st.model ? "ok" : "");

  const problems = [];
  if (st.error) problems.push(`Sensor error: ${st.error}`);
  if (rate < 50 && !st.error && Date.now() / 1000 - PAGE_LOADED > 3) {
    problems.push("No IMU data arriving." + (st.access !== "granted"
      ? " Allow Input Monitoring for the app that started LidTap (System Settings → Privacy & Security → Input Monitoring), then restart it." : ""));
  }
  $("#banner").hidden = !problems.length;
  $("#banner").textContent = problems.join(" ");

  if (!S.cfgSynced) { syncConfig(st.cfg); S.cfgSynced = true; $("#cRows").value = st.grid.rows; $("#cCols").value = st.grid.cols; }
  // A model trained in the background (end of calibration) only shows up here as a new timestamp.
  const trainedAt = st.model ? st.model.trained_at : null;
  if (trainedAt !== (S.report ? S.report.trained_at : null) && !S.fetchingReport) {
    S.fetchingReport = true;
    fetch("/api/state").then((r) => r.json()).then((j) => setReport(j.report)).finally(() => (S.fetchingReport = false));
  }
  renderCalibrate(st);
  renderLive(st);
}

function renderCalibrate(st) {
  const { rows, cols } = st.grid;
  buildGrid($("#calGrid"), rows, cols);
  const per = st.calib ? st.calib.per_zone : +$("#cPer").value;
  for (const cell of $("#calGrid").children) {
    const n = st.counts[cell.dataset.label] || 0;
    cell.querySelector(".cnt").textContent = `${n} / ${per}`;
    cell.querySelector(".bar").style.width = Math.min(100, (n / per) * 100) + "%";
    cell.classList.toggle("target", !!st.calib && st.calib.target === cell.dataset.label);
  }
  const msg = $("#calMsg");
  if (st.mode === "calibrate") {
    msg.innerHTML = `Tap <b>${zoneName(st.calib.target)}</b> ${st.calib.left_in_block > 1 ? `× ${st.calib.left_in_block}` : "once"} · ${st.calib.pos} of ${st.calib.total} done`;
    $("#calTitle").textContent = "Calibrating…";
  } else if (st.mode === "negatives") {
    msg.innerHTML = `<b>Recording noise</b> for ${Math.max(0, st.neg_left).toFixed(0)} s: knock the desk, move the lid, pick the laptop up. Don't tap zones.`;
    $("#calTitle").textContent = "Recording noise…";
  } else {
    msg.innerHTML = "Press <b>Start calibration</b>, then tap the highlighted zone.";
    $("#calTitle").textContent = "Zone grid";
  }
  $("#calStart").disabled = st.mode !== "idle";
  $("#negStart").disabled = st.mode !== "idle";
  $("#calStop").disabled = st.mode === "idle";

  const key = JSON.stringify([st.counts, rows, cols]);
  if (key !== dsKey) {
    dsKey = key;
    const labels = Object.keys(st.counts).sort((a, b) => (a === "noise") - (b === "noise") || zoneNum(a) - zoneNum(b));
    const total = Object.values(st.counts).reduce((a, b) => a + b, 0);
    $("#dsTable").innerHTML = labels.length
      ? labels.map((l) => `<tr><td>${zoneName(l)}</td><td>${st.counts[l]}</td><td><button data-del="${l}" title="Delete these taps">✕</button></td></tr>`).join("") +
        `<tr><td><b>Total</b></td><td><b>${total}</b></td><td></td></tr>`
      : `<tr><td class="muted">No taps recorded yet.</td></tr>`;
    $("#dsTable").querySelectorAll("[data-del]").forEach((b) => {
      b.onclick = () => confirm(`Delete all ${zoneName(b.dataset.del)} taps?`) && api("delete_label", { label: b.dataset.del });
    });
  }
}

$("#calStart").onclick = () => {
  const body = { rows: +$("#cRows").value, cols: +$("#cCols").value, per_zone: +$("#cPer").value, block: +$("#cBlock").value };
  const st = S.status;
  const zoneTaps = Object.entries(st.counts).filter(([l]) => l !== "noise").reduce((a, [, n]) => a + n, 0);
  if ((body.rows !== st.grid.rows || body.cols !== st.grid.cols) && zoneTaps &&
      !confirm(`Changing the grid to ${body.rows}×${body.cols} deletes the ${zoneTaps} zone taps recorded for ${st.grid.rows}×${st.grid.cols}. Continue?`)) return;
  api("calibrate", body);
};
$("#calStop").onclick = () => api("stop");
$("#negStart").onclick = () => api("negatives", { seconds: 30 });
$("#undoBtn").onclick = () => api("undo");
$("#clearBtn").onclick = () => confirm("Delete every recorded tap and the model?") && api("clear");

// ---------------------------------------------------------------- live
function renderLive(st) {
  const rebuilt = buildGrid($("#liveGrid"), st.grid.rows, st.grid.cols);
  if (rebuilt || !$("#actionList").children.length) buildActions(st);
  if (!st.model && st.mode === "idle") $("#liveMsg").textContent = "No model yet: calibrate first (tab 2).";
}

function buildActions(st) {
  const n = st.grid.rows * st.grid.cols;
  const list = $("#actionList");
  list.innerHTML = "";
  for (let i = 0; i < n; i++) {
    const row = document.createElement("div");
    row.className = "row";
    row.innerHTML = `<span>Zone ${i + 1}</span><input type="text" data-zone="z${i}" placeholder="command (empty = none)">`;
    row.querySelector("input").value = st.cfg.actions["z" + i] || "";
    list.appendChild(row);
  }
}
$("#saveActions").onclick = () => {
  const actions = {};
  $("#actionList").querySelectorAll("input").forEach((el) => { if (el.value.trim()) actions[el.dataset.zone] = el.value.trim(); });
  api("config", { actions, actions_enabled: $("#actionsOn").checked });
};
$("#actionsOn").onchange = (e) => api("config", { actions_enabled: e.target.checked });

// ---------------------------------------------------------------- model report
function setReport(rep) { S.report = rep; if ($("#model").classList.contains("on")) renderReport(); }

$("#trainBtn").onclick = async () => {
  const b = $("#trainBtn"); b.disabled = true; b.textContent = "Training…";
  try { await api("train"); } finally { b.disabled = false; b.textContent = "Retrain"; }
};
$("#modelKind").onchange = (e) => api("config", { model_kind: e.target.value });

function renderReport() {
  const rep = S.report;
  const empty = (sel, text) => ($(sel).innerHTML = `<div class="empty">${text}</div>`);
  if (!rep) {
    $("#accTable").innerHTML = `<tr><td class="empty">No model yet. Record taps in at least two zones on the Calibrate tab, then press Retrain.</td></tr>`;
    empty("#confusion", "–"); empty("#sigs", "–"); $("#modelKind").innerHTML = "";
    for (const id of ["#learn", "#pca"]) canvas2d($(id));
    return;
  }
  const kinds = rep.models.map((m) => [m.kind, m.name]);
  const cur = S.status ? S.status.cfg.model_kind : "auto";
  const bestName = rep.models.find((m) => m.kind === rep.best).name;
  $("#modelKind").innerHTML = [["auto", `Auto (${bestName})`], ...kinds]
    .map(([k, n]) => `<option value="${k}" ${k === cur ? "selected" : ""}>${n}</option>`).join("");

  const cls = (v) => (v == null ? "" : v >= 0.9 ? COL.good : v >= 0.75 ? COL.warn : COL.bad);
  $("#accTable").innerHTML =
    `<tr><th>Model (${rep.n} taps)</th>${rep.layouts.map((l) => `<th>${l}</th>`).join("")}</tr>` +
    rep.models.map((m) =>
      `<tr class="${m.kind === rep.active ? "active" : ""} ${m.kind === rep.best ? "best" : ""}"><td>${m.name}</td>` +
      rep.layouts.map((l) => `<td style="color:${cls(m.acc[l])}">${pct(m.acc[l])}</td>`).join("") + "</tr>").join("");

  drawLearning(rep.learning || []);
  renderConfusion(rep);
  drawPca(rep);
  renderSignatures(rep);
}

function drawLearning(pts) {
  const [c, w, h] = canvas2d($("#learn"));
  const L = 34, B = 22, T = 8, R = 8;
  const maxN = pts.length ? pts[pts.length - 1].n : 10;
  const X = (n) => L + (n / maxN) * (w - L - R), Y = (a) => T + (1 - a) * (h - T - B);
  c.strokeStyle = COL.line; c.fillStyle = COL.muted;
  for (const a of [0, 0.25, 0.5, 0.75, 1]) {
    c.beginPath(); c.moveTo(L, Y(a)); c.lineTo(w - R, Y(a)); c.stroke(); c.fillText(a * 100 + "%", 2, Y(a) + 4);
  }
  c.fillText("x: taps per zone", w - 92, T + 22);
  if (!pts.length) { c.fillText("Needs ≥3 taps per zone", L + 10, h / 2); return; }
  c.strokeStyle = COL.accent; c.lineWidth = 2; c.beginPath();
  pts.forEach((p, i) => (i ? c.lineTo(X(p.n), Y(p.acc)) : c.moveTo(X(p.n), Y(p.acc))));
  c.stroke();
  c.fillStyle = COL.accent;
  for (const p of pts) {
    c.beginPath(); c.arc(X(p.n), Y(p.acc), 3, 0, 7); c.fill();
    c.fillText(p.n, X(p.n) - 3, h - 8);
  }
}

function renderConfusion(rep) {
  if (!rep.confusion) { $("#confusion").innerHTML = `<div class="empty">Needs ≥2 taps per zone.</div>`; return; }
  const short = (l) => (l === "noise" ? "N" : zoneNum(l));
  let html = `<table class="cm"><tr><th></th>${rep.labels.map((l) => `<th>${short(l)}</th>`).join("")}</tr>`;
  rep.confusion.forEach((row, i) => {
    const sum = row.reduce((a, b) => a + b, 0) || 1;
    html += `<tr><th>${short(rep.labels[i])}</th>` + row.map((v, j) => {
      const a = v / sum;
      const bg = i === j ? `rgba(62,207,142,${a})` : `rgba(242,95,92,${a})`;
      return `<td style="background:${bg}">${v || ""}</td>`;
    }).join("") + "</tr>";
  });
  $("#confusion").innerHTML = html + "</table>";
}

function drawPca(rep) {
  const [c, w, h] = canvas2d($("#pca"));
  const pts = rep.pca || [];
  const nZones = rep.grid.rows * rep.grid.cols;
  if (!pts.length) return;
  let xs = pts.map((p) => p[0]), ys = pts.map((p) => p[1]);
  const [x0, x1, y0, y1] = [Math.min(...xs), Math.max(...xs), Math.min(...ys), Math.max(...ys)];
  const X = (v) => 12 + ((v - x0) / (x1 - x0 || 1)) * (w - 24), Y = (v) => h - 12 - ((v - y0) / (y1 - y0 || 1)) * (h - 24);
  for (const [px, py, lab] of pts) {
    c.fillStyle = labelColor(lab, nZones);
    c.globalAlpha = 0.85; c.beginPath(); c.arc(X(px), Y(py), 4, 0, 7); c.fill();
  }
  c.globalAlpha = 1;
  // label each cluster at its centroid
  for (const lab of rep.labels) {
    const mine = pts.filter((p) => p[2] === lab);
    const cx = mine.reduce((a, p) => a + p[0], 0) / mine.length, cy = mine.reduce((a, p) => a + p[1], 0) / mine.length;
    c.fillStyle = "#fff"; c.font = "bold 12px -apple-system, system-ui";
    c.fillText(lab === "noise" ? "noise" : zoneNum(lab), X(cx) - 4, Y(cy) + 4);
  }
  $("#pcaLegend").innerHTML = rep.labels.map((l) => `<span><i class="dot" style="background:${labelColor(l, nZones)}"></i> ${zoneName(l)}</span>`).join("");
}

function renderSignatures(rep) {
  const el = $("#sigs");
  const { rows, cols } = rep.grid;
  el.style.gridTemplateColumns = `repeat(${cols}, 1fr)`;
  el.innerHTML = "";
  const labels = [...Array(rows * cols).keys()].map((i) => "z" + i);
  if (rep.signatures.noise) labels.push("noise");
  for (const lab of labels) {
    const d = document.createElement("div");
    d.className = "sig";
    d.innerHTML = `<div class="h">${zoneName(lab)}</div><canvas></canvas>`;
    el.appendChild(d);
    const sig = rep.signatures[lab];
    const [c, w, h] = canvas2d(d.querySelector("canvas"));
    c.strokeStyle = COL.line; c.beginPath(); c.moveTo(0, h / 2); c.lineTo(w, h / 2); c.stroke();
    if (!sig) { c.fillStyle = COL.muted; c.fillText("no taps", 6, h / 2 - 4); continue; }
    for (let a = 0; a < 3; a++) {
      c.strokeStyle = AXES[a]; c.lineWidth = 1.5; c.beginPath();
      sig.forEach((r, i) => { const x = (i / (sig.length - 1)) * w, y = h / 2 - r[a] * (h / 2 - 4); i ? c.lineTo(x, y) : c.moveTo(x, y); });
      c.stroke();
    }
  }
}

// ---------------------------------------------------------------- boot
(async () => {
  const r = await fetch("/api/state");
  const j = await r.json();
  onStatus(j.status);
  S.report = j.report;
  renderReport();
  connect();
  requestAnimationFrame(drawScope);
  window.addEventListener("resize", () => { if (S.lastTap) drawTap(S.lastTap); if ($("#model").classList.contains("on")) renderReport(); });
})();
