import { createHash } from "node:crypto";
import { readFileSync, statSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const manifest = JSON.parse(readFileSync(resolve(root, "release/macos-preview.json")));
const file = process.argv[2];
const fail = (message) => { console.error(`FAIL: ${message}`); process.exit(1); };

if (manifest.schemaVersion !== 1 || manifest.platform !== "macos" || manifest.channel !== "preview") fail("invalid preview identity");
if (!/^\d+\.\d+\.\d+$/.test(manifest.version)) fail("invalid preview version");
if (manifest.packageFile !== `GYInputPreview-${manifest.version}-arm64.pkg`) fail("unexpected package name");
if (manifest.objectKey !== `previews/macos/${manifest.version}/${manifest.packageFile}`) fail("unexpected immutable object key");
if (!/^[A-F0-9]{64}$/.test(manifest.sha256) || !Number.isSafeInteger(manifest.bytes) || manifest.bytes <= 0) fail("invalid checksum metadata");
if (!file) { console.log("PASS: macOS preview manifest structure is valid."); process.exit(0); }
const payload = resolve(file);
const hash = createHash("sha256").update(readFileSync(payload)).digest("hex").toUpperCase();
if (statSync(payload).size !== manifest.bytes || hash !== manifest.sha256) fail("package does not match manifest");
console.log(`PASS: ${manifest.packageFile} matches its immutable macOS preview manifest.`);
