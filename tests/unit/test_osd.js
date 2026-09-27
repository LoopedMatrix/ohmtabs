#!/usr/bin/env node
"use strict"

// OSD helper tests: parseWpctlVolume (wpctl output parsing) and
// parseBrightness (cur/max -> percent). Pure logic, no I/O.

const assert = require("assert")
const path = require("path")
const M = require(path.join(__dirname, "..", "..", "OhmTabsModel.js"))

let passed = 0
function test(name, fn) {
  try { fn(); passed++ } catch (e) { console.error("FAIL:", name); throw e }
}

// ------------------------------------------------------------- volume

test("parseWpctlVolume: normal volume", () => {
  assert.deepStrictEqual(M.parseWpctlVolume("Volume: 0.40\n"), { percent: 40, muted: false })
})

test("parseWpctlVolume: muted at zero", () => {
  assert.deepStrictEqual(M.parseWpctlVolume("Volume: 0.00 [MUTED]\n"), { percent: 0, muted: true })
})

test("parseWpctlVolume: full volume, no trailing newline", () => {
  assert.deepStrictEqual(M.parseWpctlVolume("Volume: 1.00"), { percent: 100, muted: false })
})

test("parseWpctlVolume: empty string", () => {
  assert.deepStrictEqual(M.parseWpctlVolume(""), { percent: 0, muted: false })
})

test("parseWpctlVolume: null/undefined", () => {
  assert.deepStrictEqual(M.parseWpctlVolume(null), { percent: 0, muted: false })
  assert.deepStrictEqual(M.parseWpctlVolume(undefined), { percent: 0, muted: false })
})

test("parseWpctlVolume: garbage input", () => {
  assert.deepStrictEqual(M.parseWpctlVolume("garbage"), { percent: 0, muted: false })
  assert.deepStrictEqual(M.parseWpctlVolume("foo bar"), { percent: 0, muted: false })
})

test("parseWpctlVolume: muted flag case-insensitive", () => {
  assert.deepStrictEqual(M.parseWpctlVolume("Volume: 0.50 [muted]"), { percent: 50, muted: true })
  assert.deepStrictEqual(M.parseWpctlVolume("Volume: 0.50 [Muted]\n"), { percent: 50, muted: true })
})

test("parseWpctlVolume: volume clamped to 100", () => {
  assert.deepStrictEqual(M.parseWpctlVolume("Volume: 1.50\n"), { percent: 100, muted: false })
})

test("parseWpctlVolume: negative volume clamped to 0", () => {
  assert.deepStrictEqual(M.parseWpctlVolume("Volume: -0.20\n"), { percent: 0, muted: false })
})

test("parseWpctlVolume: muted with non-zero volume", () => {
  assert.deepStrictEqual(M.parseWpctlVolume("Volume: 0.65 [MUTED]\n"), { percent: 65, muted: true })
})

// ------------------------------------------------------------- brightness

test("parseBrightness: standard 0-255 mapping", () => {
  assert.deepStrictEqual(M.parseBrightness(120, 255), { percent: 47 })
})

test("parseBrightness: zero brightness", () => {
  assert.deepStrictEqual(M.parseBrightness(0, 255), { percent: 0 })
})

test("parseBrightness: full brightness", () => {
  assert.deepStrictEqual(M.parseBrightness(255, 255), { percent: 100 })
})

test("parseBrightness: string inputs", () => {
  assert.deepStrictEqual(M.parseBrightness("120", "255"), { percent: 47 })
})

test("parseBrightness: max <= 0 returns 0", () => {
  assert.deepStrictEqual(M.parseBrightness(100, 0), { percent: 0 })
  assert.deepStrictEqual(M.parseBrightness(100, -1), { percent: 0 })
  assert.deepStrictEqual(M.parseBrightness(100, "0"), { percent: 0 })
})

test("parseBrightness: non-numeric inputs return 0", () => {
  assert.deepStrictEqual(M.parseBrightness(null, 255), { percent: 0 })
  assert.deepStrictEqual(M.parseBrightness(undefined, 255), { percent: 0 })
  assert.deepStrictEqual(M.parseBrightness("abc", 255), { percent: 0 })
  assert.deepStrictEqual(M.parseBrightness(100, "xyz"), { percent: 0 })
})

test("parseBrightness: clamped above 100", () => {
  assert.deepStrictEqual(M.parseBrightness(300, 255), { percent: 100 })
})

test("parseBrightness: clamped below 0", () => {
  assert.deepStrictEqual(M.parseBrightness(-50, 255), { percent: 0 })
})

test("parseBrightness: 100-percent mark at exactly max", () => {
  assert.deepStrictEqual(M.parseBrightness(1, 1), { percent: 100 })
  assert.deepStrictEqual(M.parseBrightness(100, 100), { percent: 100 })
})

console.log("test_osd: " + passed + " passed")
