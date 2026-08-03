#!/usr/bin/env node
// Dependency-free cross-platform release gate. Run unchanged on Windows and macOS.
import { createHash } from "node:crypto";
import { existsSync, readFileSync, statSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(fileURLToPath(new URL("..", import.meta.url)));
const manifestPath = resolve(root, "release", "release.json");
const argv = process.argv.slice(2);
const requiredPublic = argv.includes("--require-public");
const platformIndex = argv.indexOf("--platform");
const platform = platformIndex === -1 ? null : argv[platformIndex + 1];
const errors = [];
const notes = [];
const versionPattern = /^\d+\.\d+\.\d+$/;
const shaPattern = /^[A-Fa-f0-9]{64}$/;
const fail = (message) => errors.push(message);

function hash(file) {
  return createHash("sha256").update(readFileSync(file)).digest("hex").toUpperCase();
}

function verifyFile(file, bytes, expectedHash, label) {
  if (!existsSync(file)) return fail(`${label} is missing: ${file}`);
  if (statSync(file).size !== Number(bytes)) fail(`${label} byte size differs from release.json`);
  if (hash(file) !== String(expectedHash).toUpperCase()) fail(`${label} SHA-256 differs from release.json`);
}

let release;
try {
  release = JSON.parse(readFileSync(manifestPath, "utf8"));
} catch (error) {
  console.error(JSON.stringify({ ok: false, errors: [`Unable to read canonical manifest: ${error.message}`] }, null, 2));
  process.exit(1);
}

if (release.schemaVersion !== 1) fail("schemaVersion must be 1");
if (!versionPattern.test(release.version || "")) fail("version must be semantic x.y.z");
if (release.coreVersion !== release.version || release.hostVersion !== release.version) fail("version, coreVersion, and hostVersion must be identical");
if (!["candidate", "beta", "stable"].includes(release.channel)) fail("channel must be candidate, beta, or stable");

const version = release.version || "<invalid-version>";
const windows = release.windows || {};
const macos = release.macos || {};
const windowsFile = `GYInputSetup-${version}.exe`;
const macosFile = `GYInput-${version}-arm64.pkg`;
const windowsFinal = ["candidate", "verified", "stable"].includes(windows.state);
const macosFinal = ["notarized", "stable"].includes(macos.state);

if (windows.setupFile !== windowsFile) fail(`windows.setupFile must be ${windowsFile}`);
if (!["draft", "candidate", "verified", "stable"].includes(windows.state)) fail("windows.state is invalid");
if (windowsFinal) {
  if (!shaPattern.test(windows.sha256 || "")) fail("verified Windows release needs a SHA-256");
  if (!Number.isSafeInteger(windows.bytes) || windows.bytes <= 0) fail("verified Windows release needs a positive byte size");
} else if (windows.sha256 !== "PENDING-PACKAGE-VERIFICATION" || windows.bytes !== 0) {
  fail("draft Windows release must use PENDING-PACKAGE-VERIFICATION and bytes=0");
}

if (!["verification-required", "candidate", "verified", "notarized", "stable"].includes(macos.state)) fail("macos.state is invalid");
if (macosFinal) {
  if (macos.packageFile !== macosFile) fail(`macos.packageFile must be ${macosFile}`);
  if (!shaPattern.test(macos.sha256 || "")) fail("notarized Mac release needs a SHA-256");
  if (!Number.isSafeInteger(macos.bytes) || macos.bytes <= 0) fail("notarized Mac release needs a positive byte size");
  if (macos.signed !== true || macos.notarized !== true) fail("notarized Mac release must declare signed=true and notarized=true");
}

if (platform === "windows") {
  if (!windowsFinal) fail("Windows artifact is not finalized");
  else verifyFile(resolve(root, "gy输入法", "native", "release", windowsFile), windows.bytes, windows.sha256, "Windows installer");
} else if (platform === "macos") {
  if (!macosFinal) fail("macOS package is not signed and notarized yet");
  else verifyFile(resolve(root, "release", "macos", version, macosFile), macos.bytes, macos.sha256, "macOS installer");
} else if (platform) fail("--platform accepts only windows or macos");

const publicReady = errors.length === 0 && windowsFinal && macosFinal;
if (!windowsFinal) notes.push("Windows artifact remains draft; it cannot be published.");
if (!macosFinal) notes.push("macOS package is not signed/notarized; latest must not advance.");
if (requiredPublic && !publicReady) fail("Public release requires verified Windows and signed/notarized macOS artifacts.");

console.log(JSON.stringify({
  ok: errors.length === 0,
  publicReady,
  version,
  channel: release.channel,
  platforms: {
    windows: { state: windows.state, file: windows.setupFile, verified: windowsFinal },
    macos: { state: macos.state, file: macos.packageFile ?? null, verified: macosFinal }
  },
  notes,
  errors
}, null, 2));
process.exit(errors.length === 0 ? 0 : 1);
