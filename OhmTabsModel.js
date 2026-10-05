// OhmTabs — pure state, protocol codec, journal and reconciliation logic.
// QML imports this; Node tests require() it. No I/O, no Hyprland.
//
// Everything that arrives from the backend socket, the journal file or the
// CLI is treated as untrusted input: tokens, workspace names, labels and
// geometry are validated before they influence an action.

var PLUGIN_ID = "tech.loopedmatrix.ohmtabs"
var PROTOCOL = 1
var JOURNAL_SCHEMA = 1
var JOURNAL_MAX_BYTES = 262144
var JOURNAL_MAX_ENTRIES = 256
var OWNED_WORKSPACE = "special:ohmtabs-minimized"
var LABEL_MAX = 96
var CLASS_MAX = 128
var TOKEN_RE = /^g[0-9]{1,20}-[0-9]{1,12}$/
var REQUEST_RE = /^[A-Za-z][A-Za-z0-9_-]{0,63}$/
var WORKSPACE_RE = /^[A-Za-z0-9_.:+ -]{1,64}$/
var SESSION_RE = /^[A-Za-z0-9_]{1,128}$/
var BOOL_OPTIONS = { "1": true, "0": false, "true": true, "false": false, "on": true, "off": false }
// Control characters, zero-width and bidi-override marks are stripped from labels.
var CONTROL_RE = new RegExp("[\\u0000-\\u001f\\u007f-\\u009f\\u200b-\\u200f\\u2028-\\u202e\\u2066-\\u2069]", "g")

// --------------------------------------------------------------- codec

function encodeField(value) {
  var s = String(value === undefined || value === null ? "" : value)
  var out = ""
  for (var i = 0; i < s.length; i++) {
    var c = s.charCodeAt(i)
    if (c < 0x20 || c === 0x7f || c === 0x25 /* % */ || c === 0x09 || c === 0x0a) {
      out += "%" + (c < 16 ? "0" : "") + c.toString(16).toUpperCase()
    } else {
      out += s[i]
    }
  }
  return out
}

function decodeField(value) {
  var s = String(value || "")
  return s.replace(/%([0-9A-Fa-f]{2})/g, function (_, hex) {
    return String.fromCharCode(parseInt(hex, 16))
  })
}

function buildLine(type, fields) {
  var parts = [String(type)]
  fields = fields || {}
  for (var k in fields) {
    if (fields[k] === undefined || fields[k] === null) continue
    parts.push(k + "=" + encodeField(fields[k]))
  }
  return parts.join("\t") + "\n"
}

function parseLine(line) {
  var text = String(line || "").replace(/\r?\n$/, "")
  var parts = text.split("\t")
  var msg = { type: parts[0] || "" }
  for (var i = 1; i < parts.length; i++) {
    if (!parts[i]) continue
    var eq = parts[i].indexOf("=")
    if (eq < 0) msg[parts[i]] = ""
    else msg[parts[i].slice(0, eq)] = decodeField(parts[i].slice(eq + 1))
  }
  return msg
}

// ---------------------------------------------------------- validation

function isToken(value) {
  return TOKEN_RE.test(String(value || ""))
}

function isRequestId(value) {
  return REQUEST_RE.test(String(value || ""))
}

function normalizeWorkspace(value) {
  var s = String(value || "")
  return WORKSPACE_RE.test(s) ? s : ""
}

function isSpecialWorkspace(name) {
  return String(name || "").indexOf("special:") === 0
}

function sanitizeLabel(value, maxLen) {
  var s = String(value === undefined || value === null ? "" : value)
  s = s.replace(CONTROL_RE, "")
  s = s.replace(/\s+/g, " ").trim()
  var max = maxLen || LABEL_MAX
  if (s.length > max) s = s.slice(0, max - 1) + "…"
  return s
}

function sanitizeClass(value) {
  var s = String(value || "").replace(/[^A-Za-z0-9._-]/g, "")
  return s.slice(0, CLASS_MAX)
}

function clampInt(value, lo, hi, fallback) {
  var n = Math.floor(Number(value))
  if (!isFinite(n)) return fallback
  if (n < lo) return lo
  if (n > hi) return hi
  return n
}

function flag(value) {
  return value === true || value === 1 || value === "1" || value === "true"
}

// ------------------------------------------------------------- windows

// A window snapshot as the backend reports it (one `window` message).
function windowFromMessage(msg) {
  msg = msg || {}
  if (!isToken(msg.token)) return null
  return {
    token: String(msg.token),
    address: String(msg.address || ""),
    stableId: String(msg.stableId || ""),
    pid: clampInt(msg.pid, 0, 4194304, 0),
    class: sanitizeClass(msg["class"]),
    title: sanitizeLabel(msg.title, 256),
    workspace: normalizeWorkspace(msg.workspace),
    workspaceName: normalizeWorkspace(msg.workspaceName),
    monitor: sanitizeClass(msg.monitor),
    floating: flag(msg.floating),
    pinned: flag(msg.pinned),
    maximized: flag(msg.maximized),
    fullscreen: flag(msg.fullscreen),
    hidden: flag(msg.hidden),
    owned: flag(msg.owned),
    alive: msg.alive === undefined ? true : flag(msg.alive),
    modal: flag(msg.modal),
    box: {
      x: clampInt(msg.x, -65536, 65536, 0),
      y: clampInt(msg.y, -65536, 65536, 0),
      w: clampInt(msg.w, 0, 65536, 0),
      h: clampInt(msg.h, 0, 65536, 0)
    },
    origin: msg.owned && flag(msg.owned) ? {
      workspace: normalizeWorkspace(msg.originWorkspace),
      workspaceName: normalizeWorkspace(msg.originWorkspaceName),
      monitor: sanitizeClass(msg.originMonitor),
      floating: flag(msg.originFloating),
      pinned: flag(msg.originPinned),
      maximized: flag(msg.originMaximized)
    } : null,
    request: String(msg.request || "")
  }
}

// --------------------------------------------------------------- state

function createState() {
  return {
    entries: [],      // minimized rows, newest first
    windows: {},      // token -> latest snapshot
    groups: {},       // tab groups: host token -> { host, members[], active }
    sequence: 0,
    backend: { epoch: "", sessionId: "", connected: false, minimizeEnabled: false, suspended: true },
    restoreHost: false
  }
}

function cloneState(state) {
  var next = createState()
  next.entries = (state.entries || []).map(function (e) { return Object.assign({}, e, { origin: Object.assign({}, e.origin || {}) }) })
  next.windows = Object.assign({}, state.windows || {})
  next.groups = cloneGroups(state.groups || {})
  next.sequence = state.sequence || 0
  next.backend = Object.assign({}, state.backend || {})
  next.restoreHost = !!state.restoreHost
  return next
}

function findEntry(state, token) {
  var list = state.entries || []
  for (var i = 0; i < list.length; i++) if (list[i].token === token) return i
  return -1
}

function nextSequence(state) {
  state.sequence = (state.sequence || 0) + 1
  return state.sequence
}

// Transaction step 2: the shell records a `prepared` entry before the backend
// moves anything.
function prepareEntry(state, win, requestId, now) {
  if (!win || !isToken(win.token) || !isRequestId(requestId)) return { state: state, ok: false, reason: "invalid" }
  if (findEntry(state, win.token) !== -1) return { state: state, ok: false, reason: "duplicate" }
  var next = cloneState(state)
  next.entries.unshift({
    token: win.token,
    status: "prepared",
    request: String(requestId),
    address: win.address,
    stableId: win.stableId,
    pid: win.pid,
    class: win.class,
    title: win.title,
    origin: {
      workspace: win.workspace,
      workspaceName: win.workspaceName,
      monitor: win.monitor,
      floating: !!win.floating,
      pinned: !!win.pinned,
      maximized: !!win.maximized,
      box: Object.assign({}, win.box || {})
    },
    sequence: nextSequence(next),
    at: Number(now) || 0
  })
  return { state: next, ok: true }
}

function commitEntry(state, token, requestId) {
  var i = findEntry(state, token)
  if (i === -1) return { state: state, ok: false, reason: "missing" }
  var entry = state.entries[i]
  if (entry.status !== "prepared" || entry.request !== String(requestId)) return { state: state, ok: false, reason: "mismatch" }
  var next = cloneState(state)
  next.entries[i].status = "minimized"
  return { state: next, ok: true }
}

function cancelEntry(state, token) {
  var i = findEntry(state, token)
  if (i === -1) return { state: state, ok: false }
  var next = cloneState(state)
  next.entries.splice(i, 1)
  return { state: next, ok: true }
}

function markRestoring(state, token, requestId) {
  var i = findEntry(state, token)
  if (i === -1) return { state: state, ok: false }
  var next = cloneState(state)
  next.entries[i].status = "restoring"
  next.entries[i].restoreRequest = String(requestId || "")
  return { state: next, ok: true }
}

// Only after the compositor confirmed the window left the owned workspace.
function finishRestore(state, token, ok) {
  var i = findEntry(state, token)
  if (i === -1) return { state: state, ok: false }
  var next = cloneState(state)
  if (ok) next.entries.splice(i, 1)
  else {
    next.entries[i].status = "failed"
    next.entries[i].restoreRequest = ""
  }
  return { state: next, ok: true }
}

// Live titles stay in memory only; refresh a row without reordering.
function updateTitle(state, token, title) {
  var i = findEntry(state, token)
  if (i === -1) return state
  var next = cloneState(state)
  next.entries[i].title = sanitizeLabel(title, 256)
  return next
}

function removeDead(state, token) {
  return cancelEntry(state, token).state
}

// ------------------------------------------------------------- journal

function toJournal(state, session, epoch) {
  var entries = []
  var list = state.entries || []
  for (var i = 0; i < list.length && entries.length < JOURNAL_MAX_ENTRIES; i++) {
    var e = list[i]
    if (e.status !== "prepared" && e.status !== "minimized" && e.status !== "restoring" && e.status !== "failed") continue
    entries.push({
      token: e.token,
      status: e.status === "restoring" ? "minimized" : e.status,
      request: e.request,
      address: e.address,
      stableId: e.stableId,
      pid: e.pid,
      class: e.class,
      // no title: titles are never persisted
      origin: {
        workspace: e.origin.workspace,
        workspaceName: e.origin.workspaceName,
        monitor: e.origin.monitor,
        floating: !!e.origin.floating,
        pinned: !!e.origin.pinned,
        maximized: !!e.origin.maximized,
        box: e.origin.box || null
      },
      sequence: e.sequence,
      at: e.at
    })
  }
  return { schema: JOURNAL_SCHEMA, session: String(session || ""), epoch: String(epoch || ""), sequence: state.sequence || 0, entries: entries }
}

function parseJournal(raw, session) {
  var text = String(raw === undefined || raw === null ? "" : raw)
  if (!text.trim()) return { status: "empty", entries: [], sequence: 0, epoch: "" }
  if (text.length > JOURNAL_MAX_BYTES) return { status: "invalid", reason: "oversized", entries: [], sequence: 0, epoch: "" }
  var data
  try { data = JSON.parse(text) } catch (e) { return { status: "invalid", reason: "json", entries: [], sequence: 0, epoch: "" } }
  if (!data || typeof data !== "object" || data.schema !== JOURNAL_SCHEMA) return { status: "invalid", reason: "schema", entries: [], sequence: 0, epoch: "" }
  if (!Array.isArray(data.entries)) return { status: "invalid", reason: "entries", entries: [], sequence: 0, epoch: "" }
  if (String(data.session || "") !== String(session || "")) return { status: "stale", reason: "session", entries: [], sequence: 0, epoch: String(data.epoch || "") }
  var entries = []
  for (var i = 0; i < data.entries.length && entries.length < JOURNAL_MAX_ENTRIES; i++) {
    var e = data.entries[i]
    if (!e || typeof e !== "object" || !isToken(e.token)) continue
    if (e.status !== "prepared" && e.status !== "minimized" && e.status !== "failed") continue
    var origin = e.origin && typeof e.origin === "object" ? e.origin : {}
    entries.push({
      token: String(e.token),
      status: e.status,
      request: isRequestId(e.request) ? String(e.request) : "",
      address: String(e.address || "").slice(0, 32),
      stableId: String(e.stableId || "").slice(0, 32),
      pid: clampInt(e.pid, 0, 4194304, 0),
      class: sanitizeClass(e.class),
      title: "",
      origin: {
        workspace: normalizeWorkspace(origin.workspace),
        workspaceName: normalizeWorkspace(origin.workspaceName),
        monitor: sanitizeClass(origin.monitor),
        floating: !!origin.floating,
        pinned: !!origin.pinned,
        maximized: !!origin.maximized,
        box: origin.box && typeof origin.box === "object" ? {
          x: clampInt(origin.box.x, -65536, 65536, 0), y: clampInt(origin.box.y, -65536, 65536, 0),
          w: clampInt(origin.box.w, 0, 65536, 0), h: clampInt(origin.box.h, 0, 65536, 0)
        } : null
      },
      sequence: clampInt(e.sequence, 0, 1e12, 0),
      at: clampInt(e.at, 0, 1e15, 0)
    })
  }
  return { status: "ok", entries: entries, sequence: clampInt(data.sequence, 0, 1e12, 0), epoch: String(data.epoch || "") }
}

// -------------------------------------------------------- reconciliation

// Compare journal entries with the live snapshot from the backend (spec §7.4).
// `live` is a map token -> window snapshot from the current backend epoch.
// Journal entries from an older epoch cannot be matched by token; their
// windows are recovered only through verified membership of the owned
// workspace (address + stableId evidence assists, never overrides).
function reconcile(state, journalEntries, live, backendEpoch, journalEpoch) {
  var next = cloneState(state)
  next.entries = []
  var report = { reconstructed: [], completed: [], cancelled: [], cleared: [], removed: [], recovered: [], quarantined: false }
  var sameEpoch = String(journalEpoch || "") === String(backendEpoch || "")
  var claimed = {}

  var list = journalEntries || []
  for (var i = 0; i < list.length; i++) {
    var e = list[i]
    var win = null
    if (sameEpoch) win = live[e.token] || null
    else {
      // Different epoch: tokens are dead. Match only a window that is on the
      // owned workspace AND carries the same address + stableId evidence.
      for (var t in live) {
        var w = live[t]
        if (w.hidden && w.address === e.address && w.stableId === e.stableId && !claimed[t]) { win = w; break }
      }
    }
    if (!win || !win.alive) { report.removed.push(e.token); continue }
    if (claimed[win.token]) continue
    if (win.hidden) {
      claimed[win.token] = true
      var row = Object.assign({}, e, { token: win.token, title: win.title, status: "minimized", sequence: e.sequence || nextSequence(next), at: e.at || 0 })
      if (win.origin && (!row.origin.workspaceName && win.origin.workspaceName)) row.origin = Object.assign({}, row.origin, win.origin)
      next.entries.push(row)
      if (e.status === "prepared") report.completed.push(win.token)
      else report.reconstructed.push(win.token)
    } else {
      if (e.status === "prepared") report.cancelled.push(e.token)
      else report.cleared.push(e.token)
    }
  }

  // Unrecorded live windows on OhmTabs's workspace: expose as Recovered.
  for (var token in live) {
    var lw = live[token]
    if (!lw.alive || !lw.hidden || claimed[token]) continue
    claimed[token] = true
    next.entries.push({
      token: token,
      status: "minimized",
      recovered: true,
      request: lw.request || "",
      address: lw.address,
      stableId: lw.stableId,
      pid: lw.pid,
      class: lw.class,
      title: lw.title,
      origin: lw.origin ? Object.assign({ box: null }, lw.origin) : { workspace: "", workspaceName: "", monitor: "", floating: false, pinned: false, maximized: false, box: null },
      sequence: nextSequence(next),
      at: 0
    })
    report.recovered.push(token)
  }

  next.entries.sort(function (a, b) { return (b.sequence || 0) - (a.sequence || 0) })
  return { state: next, report: report }
}

// ----------------------------------------------------------- destination

// The drawer captures its destination when the action starts (spec §5.2).
function restoreDestination(entry, mode, drawerMonitor) {
  var m = sanitizeClass(drawerMonitor)
  if (mode === "original") {
    if (entry && entry.origin && (entry.origin.workspaceName || entry.origin.workspace)) return { destination: "original", monitor: m, fallback: false }
    return { destination: "current", monitor: m, fallback: true }
  }
  return { destination: "current", monitor: m, fallback: false }
}

// Keep a floating box inside the work area with its strip reachable.
function clampBox(box, area, stripHeight) {
  var strip = clampInt(stripHeight, 0, 200, 34)
  var b = { x: Number(box.x) || 0, y: Number(box.y) || 0, w: Number(box.w) || 0, h: Number(box.h) || 0 }
  var a = { x: Number(area.x) || 0, y: Number(area.y) || 0, w: Number(area.w) || 0, h: Number(area.h) || 0 }
  if (a.w <= 0 || a.h <= 0 || b.w <= 0 || b.h <= 0) return b
  if (b.w > a.w) b.w = a.w
  if (b.h > a.h) b.h = a.h
  if (b.x < a.x) b.x = a.x
  if (b.x + b.w > a.x + a.w) b.x = a.x + a.w - b.w
  if (b.y < a.y + strip) b.y = a.y + strip
  if (b.y + b.h > a.y + a.h) b.y = Math.max(a.y + strip, a.y + a.h - b.h)
  return b
}

// ---------------------------------------------------------------- rows

function originLabel(entry, monitorLabels) {
  var parts = []
  var o = entry && entry.origin ? entry.origin : {}
  var ws = o.workspaceName || o.workspace
  if (ws && !isSpecialWorkspace(ws)) parts.push(/^[0-9]+$/.test(ws) ? "Workspace " + ws : sanitizeLabel(ws, 32))
  var mon = o.monitor
  if (mon) parts.push((monitorLabels && monitorLabels[mon]) || mon)
  if (entry && entry.recovered) parts.push("Recovered")
  return parts.join(" · ")
}

// Duplicate titles get a display-only ordinal.
function rowsWithOrdinals(entries) {
  var seen = {}
  var counts = {}
  var list = entries || []
  for (var i = 0; i < list.length; i++) {
    var key = (list[i].class || "") + "\u0000" + (list[i].title || "")
    counts[key] = (counts[key] || 0) + 1
  }
  return list.map(function (e) {
    var key = (e.class || "") + "\u0000" + (e.title || "")
    seen[key] = (seen[key] || 0) + 1
    var label = e.title || e.class || "Window"
    if (counts[key] > 1) label += " (" + seen[key] + ")"
    return Object.assign({}, e, { label: sanitizeLabel(label, LABEL_MAX) })
  })
}

// ------------------------------------------------------------ settings

// Settings live in the plugin's own bar layout entry (spec §9). Everything is
// validated: unknown keys are dropped, classes are sanitized and bounded.
function normalizeSettings(raw) {
  var r = raw && typeof raw === "object" ? raw : {}
  var classes = []
  var src = Array.isArray(r.excludedClasses) ? r.excludedClasses : []
  for (var i = 0; i < src.length && classes.length < 64; i++) {
    var c = sanitizeClass(src[i])
    if (c && classes.indexOf(c) === -1) classes.push(c)
  }
  return {
    enabled: r.enabled === false ? false : true,
    buttonsLeft: r.buttonsLeft === true || r.buttonsLeft === "left" || r.controlsOn === "left",
    showOnHover: BOOL_OPTIONS[r.showOnHover] || false,
    controlSize: r.controlSize === "large" ? "large" : "standard",
    excludedClasses: classes,
    tabGroups: BOOL_OPTIONS[r.tabGroups] || false,
    // On by default: the side panel is the Windows-style restore UI. Anything
    // other than an explicit off value keeps it enabled.
    sidePanel: (r.sidePanel === false || r.sidePanel === "0" || r.sidePanel === "off" || r.sidePanel === "false") ? false : true,
    panelPosition: (r.panelPosition === "left" || r.panelPosition === "right" || r.panelPosition === "bottom" || r.panelPosition === "top") ? r.panelPosition : "bottom",
    // Auto-hide is opt-in: the reveal is unreliable (see README "Known issues"),
    // so the panel stays visible unless the user explicitly asks for hiding.
    panelAutoHide: (r.panelAutoHide === true || r.panelAutoHide === "1" || r.panelAutoHide === "on" || r.panelAutoHide === "true") ? true : false,
    // Off by default: the Omarchy bar already has window chrome; − □ × on
    // this widget duplicated it. Opt-in from OhmTabs settings.
    barWindowControls: (r.barWindowControls === true || r.barWindowControls === "1" || r.barWindowControls === "on" || r.barWindowControls === "true") ? true : false,
    // Taskbar icons (from animated.dock's TintedIcon / iconSize / tintIcons).
    // Size is clamped so the 46px strip still fits; tint maps artwork to theme ink.
    iconSize: (function() {
      var n = parseInt(r.iconSize, 10)
      if (!(n > 0)) n = 38
      if (n < 16) n = 16
      if (n > 48) n = 48
      return n
    })(),
    tintIcons: (r.tintIcons === true || r.tintIcons === "1" || r.tintIcons === "on" || r.tintIcons === "true") ? true : false,
    showIconName: (r.showIconName === true || r.showIconName === "1" || r.showIconName === "on" || r.showIconName === "true") ? true : false,
    magnify: (r.magnify === false || r.magnify === "0" || r.magnify === "off" || r.magnify === "false") ? false : true,
    iconZoom: (function() {
      var z = parseFloat(r.iconZoom)
      if (!(z >= 0)) z = 0.48
      if (z > 1) z = 1
      return z
    })(),
    panelBorder: (r.panelBorder === false || r.panelBorder === "0" || r.panelBorder === "off" || r.panelBorder === "false") ? false : true,
    panelBorderOpacity: (function() {
      var n = parseFloat(r.panelBorderOpacity)
      if (!(n >= 0)) n = 0.95
      if (n > 1) n = 1
      return n
    })(),
    panelBgOpacity: (function() {
      var n = parseFloat(r.panelBgOpacity)
      if (!(n >= 0)) n = 0.78
      if (n < 0.15) n = 0.15
      if (n > 1) n = 1
      return n
    })(),
    fullLength: (r.fullLength === true || r.fullLength === "1" || r.fullLength === "on" || r.fullLength === "true") ? true : false,
    cornerShape: (r.cornerShape === "square" || r.cornerShape === "rounded") ? r.cornerShape : "pill",
    pinnedApps: normalizePinned(r.pinnedApps),
    showAppsButton: (r.showAppsButton === false || r.showAppsButton === "0" || r.showAppsButton === "off" || r.showAppsButton === "false") ? false : true,
    dockDodge: (r.dockDodge === true || r.dockDodge === "1" || r.dockDodge === "on" || r.dockDodge === "true") ? true : false,
    showRunning: (r.showRunning === false || r.showRunning === "0" || r.showRunning === "off" || r.showRunning === "false") ? false : true,
    showWorkspaces: (r.showWorkspaces === true || r.showWorkspaces === "1" || r.showWorkspaces === "on" || r.showWorkspaces === "true") ? true : false,
    showClock: (r.showClock === true || r.showClock === "1" || r.showClock === "on" || r.showClock === "true") ? true : false,
    showNotifs: (r.showNotifs === true || r.showNotifs === "1" || r.showNotifs === "on" || r.showNotifs === "true") ? true : false,
    showDashboard: (r.showDashboard === true || r.showDashboard === "1" || r.showDashboard === "on" || r.showDashboard === "true") ? true : false,
    showOsd: (r.showOsd === true || r.showOsd === "1" || r.showOsd === "on" || r.showOsd === "true") ? true : false,
    showStatus: (r.showStatus === true || r.showStatus === "1" || r.showStatus === "on" || r.showStatus === "true") ? true : false,
    showActiveWindow: (r.showActiveWindow === true || r.showActiveWindow === "1" || r.showActiveWindow === "on" || r.showActiveWindow === "true") ? true : false,
    workspaceCount: (function() {
      var n = parseInt(r.workspaceCount, 10)
      if (!(n >= 1)) n = 5
      if (n > 10) n = 10
      return n
    })(),
    superMenuRecommended: (r.superMenuRecommended === false || r.superMenuRecommended === "0" || r.superMenuRecommended === "off" || r.superMenuRecommended === "false") ? false : true,
    superMenuWeather: (r.superMenuWeather === true || r.superMenuWeather === "1" || r.superMenuWeather === "on" || r.superMenuWeather === "true") ? true : false,
    superMenuCalendar: (r.superMenuCalendar === true || r.superMenuCalendar === "1" || r.superMenuCalendar === "on" || r.superMenuCalendar === "true") ? true : false,
    superMenuRss: (r.superMenuRss === true || r.superMenuRss === "1" || r.superMenuRss === "on" || r.superMenuRss === "true") ? true : false,
    superMenuNews: (r.superMenuNews === true || r.superMenuNews === "1" || r.superMenuNews === "on" || r.superMenuNews === "true") ? true : false,
    superMenuCrypto: (r.superMenuCrypto === true || r.superMenuCrypto === "1" || r.superMenuCrypto === "on" || r.superMenuCrypto === "true") ? true : false,
    superMenuAlerts: (r.superMenuAlerts === true || r.superMenuAlerts === "1" || r.superMenuAlerts === "on" || r.superMenuAlerts === "true") ? true : false,
    superMenuWorldClock: (r.superMenuWorldClock === true || r.superMenuWorldClock === "1" || r.superMenuWorldClock === "on" || r.superMenuWorldClock === "true") ? true : false,
    superMenuRssUrl: sanitizeHttpUrl(r.superMenuRssUrl, "https://hnrss.org/frontpage"),
    superMenuNewsUrl: sanitizeHttpUrl(r.superMenuNewsUrl, "https://feeds.bbci.co.uk/news/rss.xml"),
    superMenuCryptoIds: sanitizeCsvIds(r.superMenuCryptoIds, "bitcoin,ethereum,solana"),
    superMenuRssFeeds: sanitizeUrlList(r.superMenuRssFeeds != null ? r.superMenuRssFeeds : r.superMenuRssUrl, ["https://hnrss.org/frontpage"], 8),
    superMenuNewsFeeds: sanitizeUrlList(r.superMenuNewsFeeds != null ? r.superMenuNewsFeeds : r.superMenuNewsUrl, ["https://feeds.bbci.co.uk/news/rss.xml"], 8),
    superMenuCurrency: sanitizeCurrency(r.superMenuCurrency),
    superMenuWeekStart: sanitizeWeekStart(r.superMenuWeekStart),
    superMenuCalIcsUrl: sanitizeHttpUrl(r.superMenuCalIcsUrl, ""),
    superMenuHourCycle: sanitizeHourCycle(r.superMenuHourCycle),
    superMenuDateOrder: sanitizeDateOrder(r.superMenuDateOrder),
    superMenuTimeZones: sanitizeTimeZones(r.superMenuTimeZones),
    superMenuFlipClock: (r.superMenuFlipClock === false || r.superMenuFlipClock === "0" || r.superMenuFlipClock === "off" || r.superMenuFlipClock === "false") ? false : true
  }
}

function sanitizeHttpUrl(s, fallback) {
  var u = String(s || "").trim()
  if (u.indexOf("https://") === 0 || u.indexOf("http://") === 0) {
    if (u.length > 300) u = u.slice(0, 300)
    return u
  }
  return fallback || ""
}

function sanitizeCsvIds(s, fallback) {
  var t = String(s || "").toLowerCase().replace(/[^a-z0-9,_-]/g, "")
  while (t.indexOf(",,") >= 0) t = t.replace(",,", ",")
  if (t.charAt(0) === ",") t = t.slice(1)
  if (t.charAt(t.length - 1) === ",") t = t.slice(0, -1)
  if (t.length > 120) t = t.slice(0, 120)
  return t || (fallback || "")
}

function sanitizeUrlList(raw, fallbackList, maxN) {
  var cap = maxN > 0 ? maxN : 8
  var src = []
  if (Object.prototype.toString.call(raw) === "[object Array]") src = raw
  else if (typeof raw === "string" && raw.trim()) src = raw.split(/[\n,]+/)
  var out = []
  for (var i = 0; i < src.length && out.length < cap; i++) {
    var u = sanitizeHttpUrl(src[i], "")
    if (u && out.indexOf(u) < 0) out.push(u)
  }
  if (out.length === 0 && fallbackList && fallbackList.length) {
    var fb = []
    for (var j = 0; j < fallbackList.length && fb.length < cap; j++) {
      var fu = sanitizeHttpUrl(fallbackList[j], "")
      if (fu && fb.indexOf(fu) < 0) fb.push(fu)
    }
    return fb
  }
  return out
}

function sanitizeCurrency(s) {
  var t = String(s || "").toLowerCase()
  if (t === "usd" || t === "eur" || t === "gbp" || t === "aud" || t === "jpy" || t === "cad" || t === "nzd") return t
  return "usd"
}

function sanitizeWeekStart(s) {
  return String(s || "").toLowerCase() === "monday" ? "monday" : "sunday"
}

function listWithout(list, value) {
  var src = Object.prototype.toString.call(list) === "[object Array]" ? list : []
  var v = String(value || "")
  var out = []
  for (var i = 0; i < src.length; i++) if (String(src[i]) !== v) out.push(src[i])
  return out
}

function csvToggleId(csv, id, maxN) {
  var cap = maxN > 0 ? maxN : 8
  var want = sanitizeCsvIds(id, "")
  if (!want || want.indexOf(",") >= 0) return sanitizeCsvIds(csv, "")
  var cur = sanitizeCsvIds(csv, "")
  var parts = cur ? cur.split(",") : []
  var next = []
  var found = false
  for (var i = 0; i < parts.length; i++) {
    if (parts[i] === want) { found = true; continue }
    next.push(parts[i])
  }
  if (!found && next.length < cap) next.push(want)
  return next.join(",")
}

function csvAddId(csv, id, maxN) {
  var cap = maxN > 0 ? maxN : 8
  var want = sanitizeCsvIds(id, "")
  var cur = sanitizeCsvIds(csv, "")
  if (!want || want.indexOf(",") >= 0) return cur
  var parts = cur ? cur.split(",") : []
  if (parts.indexOf(want) >= 0) return cur
  if (parts.length >= cap) return cur
  parts.push(want)
  return parts.join(",")
}

function calendarMonth(nowMs, weekStart, appointments) {
  var now = nowMs ? new Date(nowMs) : new Date()
  if (isNaN(now.getTime())) now = new Date()
  var y = now.getFullYear()
  var m = now.getMonth()
  var months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
  var monday = sanitizeWeekStart(weekStart) === "monday"
  var first = new Date(y, m, 1)
  var start = first.getDay()
  if (monday) start = (start + 6) % 7
  var days = new Date(y, m + 1, 0).getDate()
  var today = now.getDate()
  var cells = []
  var i
  function pad(n) { return (n < 10 ? "0" : "") + n }
  var marks = {}
  var apps = Object.prototype.toString.call(appointments) === "[object Array]" ? appointments : []
  for (var a = 0; a < apps.length; a++) {
    var dt = apps[a] && apps[a].date ? String(apps[a].date) : ""
    if (dt) marks[dt] = true
  }
  for (i = 0; i < start; i++) cells.push({ d: "", on: false, has: false, date: "" })
  for (i = 1; i <= days; i++) {
    var iso = y + "-" + pad(m + 1) + "-" + pad(i)
    cells.push({ d: String(i), on: i === today, has: !!marks[iso], date: iso })
  }
  return {
    title: months[m] + " " + y,
    year: y,
    month: m + 1,
    headers: monday ? ["M", "T", "W", "T", "F", "S", "S"] : ["S", "M", "T", "W", "T", "F", "S"],
    cells: cells
  }
}

function padTime(s) {
  var t = String(s || "").trim()
  var m = t.match(/^(\d{1,2}):(\d{2})$/)
  if (!m) return ""
  var hh = parseInt(m[1], 10)
  var mm = parseInt(m[2], 10)
  if (!(hh >= 0 && hh <= 23 && mm >= 0 && mm <= 59)) return ""
  return (hh < 10 ? "0" : "") + hh + ":" + (mm < 10 ? "0" : "") + mm
}

function normalizeAppointment(raw) {
  var o = raw && typeof raw === "object" ? raw : {}
  var title = String(o.title || "").replace(/[\r\n]/g, " ").trim()
  if (title.length > 80) title = title.slice(0, 80)
  var date = String(o.date || "").trim()
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return null
  var id = String(o.id || "").replace(/[^a-zA-Z0-9_-]/g, "")
  if (!id) id = "a" + date.replace(/-/g, "") + String(title.length)
  return {
    id: id,
    title: title || "Appointment",
    date: date,
    start: padTime(o.start),
    end: padTime(o.end),
    notes: String(o.notes || "").replace(/[\r\n]+/g, " ").trim().slice(0, 200),
    source: o.source === "ics" ? "ics" : "local"
  }
}

function normalizeAppointments(list) {
  var src = Object.prototype.toString.call(list) === "[object Array]" ? list : []
  var out = []
  var seen = {}
  for (var i = 0; i < src.length && out.length < 200; i++) {
    var a = normalizeAppointment(src[i])
    if (!a || seen[a.id]) continue
    seen[a.id] = true
    out.push(a)
  }
  out.sort(function(x, y) {
    if (x.date !== y.date) return x.date < y.date ? -1 : 1
    if (x.start !== y.start) return x.start < y.start ? -1 : 1
    return x.title < y.title ? -1 : 1
  })
  return out
}

function appointmentsOnDate(list, date) {
  var d = String(date || "")
  var src = normalizeAppointments(list)
  var out = []
  for (var i = 0; i < src.length; i++) if (src[i].date === d) out.push(src[i])
  return out
}

function upsertAppointment(list, raw) {
  var a = normalizeAppointment(raw)
  if (!a) return normalizeAppointments(list)
  var src = normalizeAppointments(list)
  var out = []
  var found = false
  for (var i = 0; i < src.length; i++) {
    if (src[i].id === a.id) { out.push(a); found = true }
    else out.push(src[i])
  }
  if (!found) out.push(a)
  return normalizeAppointments(out)
}

function removeAppointment(list, id) {
  var want = String(id || "")
  var src = normalizeAppointments(list)
  var out = []
  for (var i = 0; i < src.length; i++) if (src[i].id !== want) out.push(src[i])
  return out
}

function icsField(block, name) {
  var re = new RegExp("(?:^|\\r?\\n)" + name + "(?:;[^:\\n]*)?:([^\\r\\n]+)", "i")
  var m = String(block || "").match(re)
  return m ? m[1].trim() : ""
}

function icsDate(raw) {
  var s = String(raw || "").replace(/[^0-9T]/g, "")
  if (s.length < 8) return ""
  return s.slice(0, 4) + "-" + s.slice(4, 6) + "-" + s.slice(6, 8)
}

function icsTime(raw) {
  var s = String(raw || "")
  var t = s.indexOf("T")
  if (t < 0) return ""
  return padTime(s.slice(t + 1, t + 3) + ":" + (s.slice(t + 3, t + 5) || "00"))
}

function parseIcsEvents(text, maxN) {
  var cap = maxN > 0 ? maxN : 80
  var parts = String(text || "").split(/BEGIN:VEVENT/i)
  var out = []
  for (var i = 1; i < parts.length && out.length < cap; i++) {
    var b = parts[i].split(/END:VEVENT/i)[0]
    var date = icsDate(icsField(b, "DTSTART"))
    if (!date) continue
    var title = icsField(b, "SUMMARY").replace(/\\,/g, ",").replace(/\\n/gi, " ")
    out.push({
      id: "ics-" + date + "-" + out.length,
      title: title || "Event",
      date: date,
      start: icsTime(icsField(b, "DTSTART")),
      end: icsTime(icsField(b, "DTEND")),
      source: "ics"
    })
  }
  return normalizeAppointments(out)
}

function mergeAppointments(localList, icsList) {
  var local = normalizeAppointments(localList)
  var ics = normalizeAppointments(icsList)
  var out = local.slice()
  var seen = {}
  var i
  for (i = 0; i < local.length; i++) seen[local[i].date + "|" + local[i].title] = true
  for (i = 0; i < ics.length; i++) {
    var k = ics[i].date + "|" + ics[i].title
    if (seen[k]) continue
    seen[k] = true
    out.push(ics[i])
  }
  return normalizeAppointments(out)
}

function sanitizeHourCycle(s) {
  var t = String(s || "").toLowerCase()
  if (t === "12" || t === "12h" || t === "h12") return "12"
  return "24"
}

function sanitizeDateOrder(s) {
  var t = String(s || "").toLowerCase().replace(/[^a-z]/g, "")
  if (t === "mdy" || t === "mmddyy" || t === "mmddyyyy") return "mdy"
  return "dmy"
}

function sanitizeTimeZone(s) {
  var t = String(s || "").trim()
  if (!t) return ""
  if (/^(utc|gmt|etc\/utc)$/i.test(t)) return "UTC"
  if (/^local$/i.test(t)) return "Local"
  if (/^[A-Za-z]+(?:[_-][A-Za-z0-9]+)*(?:\/[A-Za-z0-9]+(?:[_-][A-Za-z0-9]+)*)+$/.test(t)) return t
  return ""
}

function sanitizeTimeZones(raw) {
  var src = []
  if (Object.prototype.toString.call(raw) === "[object Array]") src = raw
  else if (typeof raw === "string" && raw.trim()) src = raw.split(/[\n,]+/)
  var out = []
  for (var i = 0; i < src.length && out.length < 8; i++) {
    var z = sanitizeTimeZone(src[i])
    if (z && out.indexOf(z) < 0) out.push(z)
  }
  if (out.length === 0) return ["Local"]
  return out
}

function clockRow(nowMs, zone, hourCycle, dateOrder) {
  var d = new Date(nowMs || Date.now())
  if (isNaN(d.getTime())) d = new Date()
  var z = sanitizeTimeZone(zone) || "Local"
  var h12 = sanitizeHourCycle(hourCycle) === "12"
  var order = sanitizeDateOrder(dateOrder)
  var hour = 0
  var min = 0
  var year = 1970
  var month = 1
  var day = 1
  function pad(n) { return (n < 10 ? "0" : "") + n }
  if (z === "Local") {
    hour = d.getHours(); min = d.getMinutes()
    year = d.getFullYear(); month = d.getMonth() + 1; day = d.getDate()
  } else if (z === "UTC") {
    hour = d.getUTCHours(); min = d.getUTCMinutes()
    year = d.getUTCFullYear(); month = d.getUTCMonth() + 1; day = d.getUTCDate()
  } else {
    try {
      var fmt = new Intl.DateTimeFormat("en-GB", {
        timeZone: z, hour: "2-digit", minute: "2-digit", hourCycle: "h23",
        year: "numeric", month: "2-digit", day: "2-digit"
      })
      var parts = fmt.formatToParts(d)
      var map = {}
      for (var i = 0; i < parts.length; i++) map[parts[i].type] = parts[i].value
      hour = parseInt(map.hour, 10)
      min = parseInt(map.minute, 10)
      year = parseInt(map.year, 10)
      month = parseInt(map.month, 10)
      day = parseInt(map.day, 10)
      if (isNaN(hour) || isNaN(min)) throw new Error("bad zone")
    } catch (e) {
      return clockRow(nowMs, "Local", hourCycle, dateOrder)
    }
  }
  var ap = ""
  var displayH = hour
  if (h12) {
    ap = hour >= 12 ? "PM" : "AM"
    displayH = hour % 12
    if (displayH === 0) displayH = 12
  }
  var hh = pad(displayH)
  var mm = pad(min)
  var yy = String(year).slice(-2)
  var date = order === "mdy" ? (pad(month) + "/" + pad(day) + "/" + yy) : (pad(day) + "/" + pad(month) + "/" + yy)
  var label = z
  if (z === "Local") label = "Local"
  else if (z === "UTC") label = "UTC"
  else {
    var bits = z.split("/")
    label = bits[bits.length - 1].replace(/_/g, " ")
  }
  return { zone: z, label: label, hh: hh, mm: mm, ap: ap, digits: [hh.charAt(0), hh.charAt(1), mm.charAt(0), mm.charAt(1)], date: date }
}

function currencyPrefix(code) {
  var t = sanitizeCurrency(code)
  if (t === "eur") return "€"
  if (t === "gbp") return "£"
  if (t === "jpy") return "¥"
  if (t === "aud") return "A$"
  if (t === "cad") return "C$"
  if (t === "nzd") return "NZ$"
  return "$"
}

function parseRssItems(xml, maxN) {
  var text = String(xml || "")
  var cap = maxN > 0 ? maxN : 5
  var out = []
  function decode(s) {
    var t = String(s || "")
    t = t.replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
    t = t.replace(/<[^>]+>/g, "")
    t = t.replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"").replace(/&#39;/g, "'").replace(/&apos;/g, "'")
    t = t.replace(/\s+/g, " ").trim()
    if (t.length > 96) t = t.slice(0, 93) + "..."
    return t
  }
  function pull(block, tag) {
    var m = block.match(new RegExp("<" + tag + "\\b[^>]*>([\\s\\S]*?)</" + tag + ">", "i"))
    return m ? decode(m[1]) : ""
  }
  var re = /<item\b[\s\S]*?<\/item>/gi
  var m
  while ((m = re.exec(text)) && out.length < cap) {
    var block = m[0]
    var title = pull(block, "title")
    var link = pull(block, "link")
    if (!link) {
      var al = block.match(/<link\b[^>]*href=["']([^"']+)["']/i)
      if (al) link = al[1]
    }
    if (title) out.push({ title: title, link: link || "" })
  }
  if (out.length === 0) {
    re = /<entry\b[\s\S]*?<\/entry>/gi
    while ((m = re.exec(text)) && out.length < cap) {
      var eblock = m[0]
      var etitle = pull(eblock, "title")
      var elink = ""
      var ea = eblock.match(/<link\b[^>]*href=["']([^"']+)["']/i)
      if (ea) elink = ea[1]
      if (etitle) out.push({ title: etitle, link: elink })
    }
  }
  return out
}

function weatherLabel(code) {
  var n = parseInt(code, 10)
  if (!(n >= 0)) return "—"
  if (n === 0) return "Clear"
  if (n <= 3) return "Cloudy"
  if (n <= 48) return "Fog"
  if (n <= 57) return "Drizzle"
  if (n <= 67) return "Rain"
  if (n <= 77) return "Snow"
  if (n <= 82) return "Showers"
  if (n <= 99) return "Storm"
  return "—"
}

function sanitizeAppId(id) {
  var s = String(id || "").trim()
  if (s.slice(-8).toLowerCase() === ".desktop") s = s.slice(0, -8)
  s = s.replace(/[^A-Za-z0-9._+-]/g, "")
  if (s.length > 80) s = s.slice(0, 80)
  return s
}

function dockAppId(id) {
  var n = sanitizeAppId(id).toLowerCase()
  if (!n) return ""
  if (n === "com.nousresearch.hermes" || n === "hermes-desktop") return "hermes"
  var i = n.lastIndexOf(".")
  if (i >= 0 && i < n.length - 1) n = n.slice(i + 1)
  return n
}

// The .desktop entry that owns a dock id. `dockAppId` normalizes a window class
// to the id a pin is stored under, but the entry's own id can be named quite
// differently from that id: Claude's window class and entry id are both
// com.anthropic.Claude while the pin and the dock tile are the short "claude",
// so neither byId("claude") nor heuristicLookup("claude") matches (that lookup
// only tries the exact id and StartupWMClass). Icon and launch resolution both
// missed, and the tile fell back to a letter. Scan the entries for one whose id
// OR StartupWMClass normalizes to the same dock id, preferring an id match
// (a StartupWMClass can be shared by several entries). NoDisplay entries are
// skipped — they are hidden helpers, not apps.
function desktopEntryIdFor(appId, entries) {
  var want = dockAppId(appId)
  if (!want) return ""
  var list = entries && typeof entries.length === "number" ? entries : []
  var byId = ""
  var byClass = ""
  for (var i = 0; i < list.length; i++) {
    var e = list[i]
    if (!e || e.noDisplay) continue
    var id = String(e.id || "")
    if (!id) continue
    if (!byId && dockAppId(id) === want) byId = id
    if (!byClass) {
      var sc = String(e.startupWMClass || "")
      if (sc && dockAppId(sc) === want) byClass = id
    }
    if (byId && byClass) break
  }
  return byId || byClass
}

function appLetter(name) {
  var c = String(name || "").replace(/^\s+/, "").charAt(0).toUpperCase()
  if (c >= "A" && c <= "Z") return c
  return "#"
}

function decodeFileUrl(href) {
  var s = String(href || "")
  if (s.indexOf("file://") === 0) s = s.slice(7)
  try { s = decodeURIComponent(s) } catch (e) {}
  return s
}

function fileBasename(p) {
  var s = String(p || "").replace(/\/+$/, "")
  var i = s.lastIndexOf("/")
  return i >= 0 ? s.slice(i + 1) : s
}

// Freedesktop icon-name ladder for a filesystem path. Super Menu Recommended
// rows use the same theme the dock already loads (folder, image-*, pdf, …).
function fileIconNames(path) {
  var p = String(path || "")
  var names = []
  function add(n) {
    n = String(n || "")
    if (!n) return
    if (names.indexOf(n) < 0) names.push(n)
  }
  if (!p) {
    add("text-x-generic")
    add("unknown")
    return names
  }
  var trailed = p.charAt(p.length - 1) === "/"
  var base = fileBasename(p)
  var dot = base.lastIndexOf(".")
  var ext = (!trailed && dot > 0) ? base.slice(dot + 1).toLowerCase() : ""
  if (!ext) {
    add("inode-directory")
    add("folder")
    add("system-file-manager")
    add("org.gnome.Nautilus")
    add("folder-documents")
    return names
  }
  var byExt = {
    png: ["image-png", "image-x-generic"],
    jpg: ["image-jpeg", "image-x-generic"],
    jpeg: ["image-jpeg", "image-x-generic"],
    gif: ["image-gif", "image-x-generic"],
    webp: ["image-webp", "image-x-generic"],
    svg: ["image-svg+xml", "image-x-generic"],
    bmp: ["image-bmp", "image-x-generic"],
    ico: ["image-x-ico", "image-x-generic"],
    mp3: ["audio-x-mpeg", "audio-x-generic"],
    wav: ["audio-x-wav", "audio-x-generic"],
    flac: ["audio-x-flac", "audio-x-generic"],
    ogg: ["audio-x-generic"],
    mp4: ["video-mp4", "video-x-generic"],
    mkv: ["video-x-matroska", "video-x-generic"],
    webm: ["video-webm", "video-x-generic"],
    avi: ["video-x-generic"],
    pdf: ["application-pdf", "x-office-document"],
    zip: ["application-zip", "package-x-generic"],
    tar: ["application-x-tar", "package-x-generic"],
    gz: ["application-gzip", "package-x-generic"],
    "7z": ["application-x-7z-compressed", "package-x-generic"],
    html: ["text-html"],
    htm: ["text-html"],
    md: ["text-markdown", "text-x-generic"],
    txt: ["text-x-generic"],
    json: ["application-json", "text-x-generic"],
    xml: ["text-xml", "text-x-generic"],
    js: ["text-javascript", "text-x-generic"],
    ts: ["text-x-generic"],
    py: ["text-x-python", "text-x-generic"],
    qml: ["text-x-qml", "text-x-generic"],
    css: ["text-css", "text-x-generic"],
    sh: ["application-x-shellscript", "text-x-script"],
    desktop: ["application-x-desktop"],
    doc: ["x-office-document"],
    docx: ["x-office-document"],
    odt: ["x-office-document"],
    xls: ["x-office-spreadsheet"],
    xlsx: ["x-office-spreadsheet"],
    ods: ["x-office-spreadsheet"],
    ppt: ["x-office-presentation"],
    pptx: ["x-office-presentation"]
  }
  var list = byExt[ext] || ["text-x-generic"]
  for (var i = 0; i < list.length; i++) add(list[i])
  add("text-x-generic")
  add("unknown")
  return names
}

function parseRecentlyUsed(xml, maxN) {
  var text = String(xml || "")
  var cap = maxN > 0 ? maxN : 8
  var found = []
  var re = /<bookmark\s+href="([^"]+)"([^>]*)>/g
  var m
  while ((m = re.exec(text))) {
    var href = m[1]
    if (href.indexOf("file://") !== 0) continue
    var attrs = m[2] || ""
    var vis = ""
    var vm = attrs.match(/visited="([^"]+)"/)
    if (vm) vis = vm[1]
    var path = decodeFileUrl(href)
    if (!path) continue
    found.push({ href: href, path: path, title: fileBasename(path) || path, visited: vis })
  }
  found.reverse()
  var seen = {}
  var out = []
  for (var i = 0; i < found.length; i++) {
    var item = found[i]
    if (seen[item.path]) continue
    seen[item.path] = true
    out.push(item)
    if (out.length >= cap) break
  }
  return out
}

function relativeTime(iso, nowMs) {
  var t = Date.parse(String(iso || ""))
  if (!(t > 0)) return ""
  var d = Math.max(0, (nowMs || Date.now()) - t)
  if (d < 60000) return "just now"
  if (d < 3600000) return Math.floor(d / 60000) + "m ago"
  if (d < 86400000) return Math.floor(d / 3600000) + "h ago"
  return Math.floor(d / 86400000) + "d ago"
}

function recordLaunch(state, appId, nowMs) {
  var id = sanitizeAppId(appId)
  var next = { launches: {} }
  var src = state && state.launches && typeof state.launches === "object" ? state.launches : {}
  for (var k in src) next.launches[k] = src[k]
  if (!id) return next
  var cur = next.launches[id] || { n: 0, last: 0 }
  next.launches[id] = { n: (Number(cur.n) || 0) + 1, last: nowMs || Date.now() }
  return next
}

function frecencyRank(launches, nowMs, limit) {
  var now = nowMs || Date.now()
  var cap = limit > 0 ? limit : 8
  var src = launches && typeof launches === "object" ? launches : {}
  var items = []
  for (var k in src) {
    var e = src[k]
    if (!e) continue
    var n = Number(e.n) || 0
    var last = Number(e.last) || 0
    var ageDays = last ? (now - last) / 86400000 : 999
    items.push({ appId: k, n: n, last: last, score: n * Math.pow(0.5, ageDays / 14) })
  }
  items.sort(function(a, b) { return b.score - a.score })
  return items.slice(0, cap)
}

function normalizePinned(list) {
  var src = []
  if (list && typeof list === "object" && typeof list.length === "number") {
    for (var i = 0; i < list.length; i++) src.push(list[i])
  }
  var out = []
  var seen = {}
  for (var j = 0; j < src.length; j++) {
    var id = sanitizeAppId(src[j])
    var key = dockAppId(id)
    if (!key || seen[key]) continue
    seen[key] = true
    out.push(id)
    if (out.length >= 24) break
  }
  return out
}

function togglePinned(pinnedIds, appId) {
  var id = sanitizeAppId(appId)
  if (!id) return normalizePinned(pinnedIds)
  var want = dockAppId(id)
  var arr = normalizePinned(pinnedIds)
  var next = []
  var found = false
  for (var i = 0; i < arr.length; i++) {
    if (dockAppId(arr[i]) === want) { found = true; continue }
    next.push(arr[i])
  }
  if (!found) next.push(id)
  return next
}

function isPinned(pinnedIds, appId) {
  var want = dockAppId(appId)
  if (!want) return false
  var arr = normalizePinned(pinnedIds)
  for (var i = 0; i < arr.length; i++) {
    if (dockAppId(arr[i]) === want) return true
  }
  return false
}

// --------------------------------------------------------------- dock items

// Hyprland reports window addresses as "0x5ba374a2efb0"; Quickshell's
// HyprlandToplevel.address drops the prefix ("5ba374a2efb0"). Compare the
// address itself, never the spelling, so a row and its toplevel still match.
function normalizeAddress(value) {
  var s = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
  if (s.slice(0, 2) === "0x") s = s.slice(2)
  s = s.replace(/^0+/, "")
  return s
}

// A window OhmTabs parked on its holding workspace is not an open window: its
// button is its minimized row. The workspace name is the only fact that says
// so, and only the HyprlandToplevel carries it (the WaylandToplevel the dock
// activates has no workspace property at all, and the toplevel's
// lastIpcObject.workspace keeps the OLD workspace after a park).
function isParkedWorkspace(workspaceName) {
  var n = String(workspaceName === undefined || workspaceName === null ? "" : workspaceName)
  if (!n) return false
  if (n === OWNED_WORKSPACE) return true
  return n.indexOf("ohmtabs-minimized") >= 0
}

// The dock's button list: one button per window, in order — apps button, live
// windows, minimized rows, pinned stubs with no window, notifs, dashboard.
//
// `input.live` is the shell's snapshot of the compositor's toplevels as plain
// facts ({ id, title, key, address, workspace, toplevel }) because only QML can
// reach Hyprland; everything that decides what is drawn lives here, where it
// is unit-tested. `input.rows` are the minimized entries.
//
// A live toplevel is dropped when it is parked, and — belt and braces — when
// its address is one a minimized row already claims. Either check alone keeps
// the minimized window off the dock a second time; the address check also
// covers a compositor that reports no workspace for the holding workspace.
function buildDockItems(input) {
  var o = input && typeof input === "object" ? input : {}
  var pins = normalizePinned(o.pinnedApps)
  var rows = o.rows && typeof o.rows.length === "number" ? o.rows : []
  var live = o.live && typeof o.live.length === "number" ? o.live : []
  var out = []

  if (o.showAppsButton)
    out.push({ key: "apps", kind: "apps", members: [], appId: "", pinned: false, liveCount: 0, minCount: 0, toplevel: null })

  var parkedAddress = {}
  for (var a = 0; a < rows.length; a++) {
    var addr = normalizeAddress(rows[a] && rows[a].address)
    if (addr) parkedAddress[addr] = true
  }

  var covered = {}
  if (o.showRunning !== false) {
    for (var i = 0; i < live.length; i++) {
      var L = live[i]
      if (!L) continue
      var id = dockAppId(L.id)
      if (!id || id === "electron" || id === "chromium") continue
      if (isParkedWorkspace(L.workspace)) continue
      var la = normalizeAddress(L.address)
      if (la && parkedAddress[la]) continue
      covered[id] = true
      var ttl = sanitizeLabel(L.title, LABEL_MAX) || id
      out.push({
        key: L.key ? String(L.key) : ("live:" + id + ":" + i),
        kind: "app",
        appId: id,
        pinned: isPinned(pins, id),
        members: [{ class: id, title: ttl, label: ttl, token: "", status: "live" }],
        toplevel: L.toplevel || null,
        liveCount: 1,
        minCount: 0
      })
    }
  }

  for (var m = 0; m < rows.length; m++) {
    var row = rows[m]
    var mid = dockAppId(row && row.class)
    if (!mid) mid = "__min" + m
    covered[mid] = true
    out.push({
      key: String((row && row.token) || ("m" + m)),
      kind: "minimized",
      appId: mid,
      pinned: isPinned(pins, mid),
      members: [row],
      toplevel: null,
      liveCount: 0,
      minCount: 1
    })
  }

  for (var p = 0; p < pins.length; p++) {
    var pid = dockAppId(pins[p])
    if (!pid || covered[pid]) continue
    covered[pid] = true
    out.push({
      key: "pin:" + pid,
      kind: "app",
      appId: pid,
      pinned: true,
      members: [{ class: pid, title: pid, label: pid, token: "", status: "pinned" }],
      toplevel: null,
      liveCount: 0,
      minCount: 0
    })
  }

  if (o.showNotifs)
    out.push({ key: "notifs", kind: "notifs", members: [], appId: "", pinned: false, liveCount: 0, minCount: 0, toplevel: null })
  if (o.showDashboard)
    out.push({ key: "dash", kind: "dashboard", members: [], appId: "", pinned: false, liveCount: 0, minCount: 0, toplevel: null })
  return out
}

// Find this plugin's entry in a shell.json document and return its settings
// (everything but `id`), or null when the entry is absent.
function readOwnEntry(raw, pluginId) {
  var parsed
  try { parsed = JSON.parse(String(raw || "")) } catch (e) { return null }
  if (!parsed || typeof parsed !== "object") return null
  var layout = parsed.bar && parsed.bar.layout ? parsed.bar.layout : null
  if (!layout) return null
  var sections = ["left", "center", "right"]
  for (var s = 0; s < sections.length; s++) {
    var list = Array.isArray(layout[sections[s]]) ? layout[sections[s]] : []
    for (var i = 0; i < list.length; i++) {
      var entry = list[i]
      if (entry && typeof entry === "object" && String(entry.id || "") === String(pluginId)) {
        var copy = {}
        for (var k in entry) if (k !== "id") copy[k] = entry[k]
        return copy
      }
    }
  }
  return null
}

function statusSummary(state) {
  var minimized = 0, prepared = 0, failed = 0, recovered = 0
  var list = state.entries || []
  for (var i = 0; i < list.length; i++) {
    if (list[i].status === "prepared") prepared++
    else if (list[i].status === "failed") failed++
    else minimized++
    if (list[i].recovered) recovered++
  }
  return { minimized: minimized, prepared: prepared, failed: failed, recovered: recovered, total: list.length }
}

// ---------------------------------------------------------- tab groups

// A tab group is a host window plus the windows dropped onto it, rendered as
// a tab strip on the host's bar. The host token is the group's key and is
// always members[0]; `active` indexes the currently shown tab. A group is
// only meaningful while it holds at least two windows (host + one or more
// dropped windows), so it dissolves the moment it drops to a single window —
// and removing the host always dissolves it, because the host owns the strip.

// decision 2: alt-tab cycles inside a group only while the pointer is over the
// host's tab strip; anywhere else the caller falls through to the compositor's
// normal alt-tab. This sentinel can never collide with a real token.
var TAB_CYCLE_FALLTHROUGH = "__fallthrough__"

function cloneGroups(groups) {
  var out = {}
  var src = groups || {}
  for (var k in src) {
    var g = src[k]
    if (!g || !g.host) continue
    var members = Array.isArray(g.members) ? g.members : []
    out[k] = { host: g.host, members: members.slice(), active: clampInt(g.active, 0, members.length - 1, 0) }
  }
  return out
}

function findGroupByHost(state, token) {
  var groups = (state && state.groups) || {}
  return groups[token] || null
}

// The group a token belongs to as either host or member, if any.
function findGroupByMember(state, token) {
  var groups = (state && state.groups) || {}
  for (var k in groups) {
    var g = groups[k]
    if (g && g.members && g.members.indexOf(token) !== -1) return g
  }
  return null
}

function createGroup(state, hostToken) {
  if (!isToken(hostToken)) return { state: state, ok: false, reason: "invalid" }
  if (findGroupByHost(state, hostToken)) return { state: state, ok: false, reason: "duplicate" }
  // A window that is already a tab elsewhere cannot own a strip of its own.
  if (findGroupByMember(state, hostToken)) return { state: state, ok: false, reason: "grouped" }
  var next = cloneState(state)
  next.groups[hostToken] = { host: hostToken, members: [hostToken], active: 0 }
  return { state: next, ok: true }
}

function removeGroup(state, hostToken) {
  if (!isToken(hostToken)) return { state: state, ok: false, reason: "invalid" }
  if (!findGroupByHost(state, hostToken)) return { state: state, ok: false, reason: "missing" }
  var next = cloneState(state)
  delete next.groups[hostToken]
  return { state: next, ok: true }
}

function addMember(state, hostToken, memberToken) {
  if (!isToken(hostToken) || !isToken(memberToken)) return { state: state, ok: false, reason: "invalid" }
  if (hostToken === memberToken) return { state: state, ok: false, reason: "same" }
  var memberGroup = findGroupByMember(state, memberToken)
  // A window already in a strip cannot be dropped again; a host window is its
  // own strip and cannot become someone else's tab.
  if (memberGroup) return { state: state, ok: false, reason: memberGroup.host === memberToken ? "host" : "grouped" }
  var hostGroup = findGroupByMember(state, hostToken)
  if (hostGroup && hostGroup.host !== hostToken) return { state: state, ok: false, reason: "grouped" }

  var next = cloneState(state)
  var group = next.groups[hostToken]
  if (!group) {
    // decision 1: dropping a window onto a host with no group creates one,
    // and the host's bar gains a strip.
    group = { host: hostToken, members: [hostToken], active: 0 }
    next.groups[hostToken] = group
  }
  group.members.push(memberToken)
  return { state: next, ok: true }
}

// Removing the host dissolves the whole group; removing the last dropped
// window dissolves it too, because a lone host is no longer a tab group.
function removeMember(state, token) {
  if (!isToken(token)) return { state: state, ok: false, reason: "invalid" }
  var next = cloneState(state)
  if (next.groups[token]) { delete next.groups[token]; return { state: next, ok: true } }

  var hostToken = null, idx = -1
  for (var k in next.groups) {
    var g = next.groups[k]
    idx = g.members.indexOf(token)
    if (idx !== -1) { hostToken = k; break }
  }
  if (hostToken === null) return { state: state, ok: false, reason: "missing" }
  var group = next.groups[hostToken]
  group.members.splice(idx, 1)
  if (group.members.length < 2) {
    delete next.groups[hostToken]
  } else {
    if (group.active > idx) group.active -= 1
    else if (group.active === idx) group.active = Math.min(idx, group.members.length - 1)
    if (group.active >= group.members.length) group.active = group.members.length - 1
  }
  return { state: next, ok: true }
}

// Drag a tab from one strip to another. The source group may dissolve if the
// tab was its only dropped window; a host window itself is never moved this
// way (that is a remove, which dissolves the group).
function moveMember(state, token, newHostToken) {
  if (!isToken(token) || !isToken(newHostToken)) return { state: state, ok: false, reason: "invalid" }
  if (token === newHostToken) return { state: state, ok: false, reason: "same" }
  if (findGroupByHost(state, token)) return { state: state, ok: false, reason: "host" }
  var source = findGroupByMember(state, token)
  if (!source) return { state: state, ok: false, reason: "missing" }
  if (source.host === newHostToken) return { state: state, ok: false, reason: "same" }
  // A tab can only be dropped onto a host window, never onto another tab.
  var dest = findGroupByMember(state, newHostToken)
  if (dest && dest.host !== newHostToken) return { state: state, ok: false, reason: "grouped" }

  var next = cloneState(state)
  var from = next.groups[source.host]
  var idx = from.members.indexOf(token)
  from.members.splice(idx, 1)
  if (from.members.length < 2) {
    delete next.groups[source.host]
  } else {
    if (from.active > idx) from.active -= 1
    else if (from.active === idx) from.active = Math.min(idx, from.members.length - 1)
    if (from.active >= from.members.length) from.active = from.members.length - 1
  }
  var to = next.groups[newHostToken]
  if (!to) {
    to = { host: newHostToken, members: [newHostToken], active: 0 }
    next.groups[newHostToken] = to
  }
  to.members.push(token)
  return { state: next, ok: true }
}

function getActiveMember(state, hostToken) {
  var group = findGroupByHost(state, hostToken)
  if (!group) return ""
  return group.members[group.active] || ""
}

function setActiveMember(state, hostToken, memberToken) {
  if (!isToken(hostToken) || !isToken(memberToken)) return { state: state, ok: false, reason: "invalid" }
  var group = findGroupByHost(state, hostToken)
  if (!group) return { state: state, ok: false, reason: "missing" }
  var idx = group.members.indexOf(memberToken)
  if (idx === -1) return { state: state, ok: false, reason: "missing" }
  if (group.active === idx) return { state: state, ok: true }
  var next = cloneState(state)
  next.groups[hostToken].active = idx
  return { state: next, ok: true }
}

// decision 2 (pure): the next tab for alt-tab. With the pointer over the
// host's strip, wrap around in the requested direction; with the pointer
// anywhere else, hand control back to the compositor. `direction` is "prev"
// (or -1) for backwards, anything else advances forwards.
function cycleTab(members, activeIndex, direction, pointerInside) {
  var list = Array.isArray(members) ? members : []
  if (list.length < 2 || !pointerInside) return TAB_CYCLE_FALLTHROUGH
  var idx = clampInt(activeIndex, 0, list.length - 1, 0)
  var delta = (direction === "prev" || direction === "up" || direction === -1 || direction === "-1") ? -1 : 1
  idx = (idx + delta + list.length) % list.length
  return list[idx]
}

function isTabCycleFallthrough(value) {
  return value === TAB_CYCLE_FALLTHROUGH
}

// decision 3: closing a group only needs a prompt when it actually holds more
// than one window; a lone host can be closed without asking.
function needsCloseConfirmation(state, hostToken) {
  var group = findGroupByHost(state, hostToken)
  if (!group) return false
  return group.members.length > 1
}

// Future tab-save feature: a JSON-safe snapshot of one group. No caller yet —
// this is the designated hook so the save feature has a stable serialization
// shape to build on.
function tabSaveSnapshot(state, hostToken) {
  var group = findGroupByHost(state, hostToken)
  if (!group) return null
  return { host: group.host, members: group.members.slice(), active: group.active }
}

function listGroups(state) {
  var groups = (state && state.groups) || {}
  var out = []
  for (var k in groups) {
    var g = groups[k]
    if (!g || !g.host) continue
    out.push({ host: g.host, members: g.members.slice(), active: g.active })
  }
  return out
}

function parseBrightness(cur, max) {
  var c = Number(cur)
  var m = Number(max)
  if (!isFinite(c) || !isFinite(m) || m <= 0) return { percent: 0 }
  var pct = Math.round((c / m) * 100)
  if (pct < 0) pct = 0
  if (pct > 100) pct = 100
  return { percent: pct }
}

function parseWpctlVolume(text) {
  var s = String(text === undefined || text === null ? "" : text)
  var m = s.match(/^Volume:\s+([0-9]+(?:\.[0-9]+)?)/m)
  var pct = 0
  if (m && m[1] !== undefined) {
    var v = parseFloat(m[1])
    if (isFinite(v)) pct = Math.round(v * 100)
  }
  if (pct < 0) pct = 0
  if (pct > 100) pct = 100
  var muted = /\[MUTED\]/i.test(s)
  return { percent: pct, muted: muted }
}

function notifMatchesApp(notif, appId) {
  var want = dockAppId(appId)
  if (!want) return false
  var n = notif && typeof notif === "object" ? notif : {}
  var keys = [n.app, n.appName, n.appIcon, n.desktopEntry, n.app_id]
  for (var i = 0; i < keys.length; i++) {
    var got = dockAppId(keys[i])
    if (got && got === want) return true
  }
  return false
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    PLUGIN_ID: PLUGIN_ID, PROTOCOL: PROTOCOL, JOURNAL_SCHEMA: JOURNAL_SCHEMA, JOURNAL_MAX_BYTES: JOURNAL_MAX_BYTES,
    JOURNAL_MAX_ENTRIES: JOURNAL_MAX_ENTRIES, OWNED_WORKSPACE: OWNED_WORKSPACE,
    encodeField: encodeField, decodeField: decodeField, buildLine: buildLine, parseLine: parseLine,
    isToken: isToken, isRequestId: isRequestId, normalizeWorkspace: normalizeWorkspace, isSpecialWorkspace: isSpecialWorkspace,
    sanitizeLabel: sanitizeLabel, sanitizeClass: sanitizeClass, clampInt: clampInt, flag: flag,
    windowFromMessage: windowFromMessage, createState: createState, cloneState: cloneState, findEntry: findEntry,
    prepareEntry: prepareEntry, commitEntry: commitEntry, cancelEntry: cancelEntry, markRestoring: markRestoring,
    finishRestore: finishRestore, updateTitle: updateTitle, removeDead: removeDead,
    toJournal: toJournal, parseJournal: parseJournal, reconcile: reconcile,
    restoreDestination: restoreDestination, clampBox: clampBox, originLabel: originLabel, rowsWithOrdinals: rowsWithOrdinals,
 statusSummary: statusSummary, normalizeSettings: normalizeSettings, readOwnEntry: readOwnEntry,
 sanitizeAppId: sanitizeAppId, dockAppId: dockAppId, normalizePinned: normalizePinned, togglePinned: togglePinned, isPinned: isPinned,
 desktopEntryIdFor: desktopEntryIdFor,
 appLetter: appLetter, decodeFileUrl: decodeFileUrl, fileBasename: fileBasename, fileIconNames: fileIconNames,
 parseRecentlyUsed: parseRecentlyUsed, relativeTime: relativeTime,
 parseRssItems: parseRssItems, weatherLabel: weatherLabel, sanitizeHttpUrl: sanitizeHttpUrl, sanitizeCsvIds: sanitizeCsvIds,
 sanitizeUrlList: sanitizeUrlList, sanitizeCurrency: sanitizeCurrency, sanitizeWeekStart: sanitizeWeekStart,
 listWithout: listWithout, csvToggleId: csvToggleId, csvAddId: csvAddId, calendarMonth: calendarMonth, currencyPrefix: currencyPrefix,
 sanitizeHourCycle: sanitizeHourCycle, sanitizeDateOrder: sanitizeDateOrder, sanitizeTimeZone: sanitizeTimeZone,
 sanitizeTimeZones: sanitizeTimeZones, clockRow: clockRow,
 normalizeAppointment: normalizeAppointment, normalizeAppointments: normalizeAppointments, appointmentsOnDate: appointmentsOnDate,
 upsertAppointment: upsertAppointment, removeAppointment: removeAppointment, parseIcsEvents: parseIcsEvents, mergeAppointments: mergeAppointments,
 recordLaunch: recordLaunch, frecencyRank: frecencyRank,
 normalizeAddress: normalizeAddress, isParkedWorkspace: isParkedWorkspace, buildDockItems: buildDockItems,
 parseWpctlVolume: parseWpctlVolume, parseBrightness: parseBrightness, notifMatchesApp: notifMatchesApp,
    TAB_CYCLE_FALLTHROUGH: TAB_CYCLE_FALLTHROUGH,
    createGroup: createGroup, removeGroup: removeGroup, addMember: addMember, removeMember: removeMember,
    moveMember: moveMember, getActiveMember: getActiveMember, setActiveMember: setActiveMember,
    cycleTab: cycleTab, isTabCycleFallthrough: isTabCycleFallthrough, needsCloseConfirmation: needsCloseConfirmation,
    tabSaveSnapshot: tabSaveSnapshot, listGroups: listGroups, findGroupByHost: findGroupByHost, findGroupByMember: findGroupByMember
  }
}
