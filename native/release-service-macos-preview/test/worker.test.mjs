import test from "node:test";
import assert from "node:assert/strict";
import worker from "../src/index.js";

const manifest = {
  schemaVersion: 1, platform: "macos", channel: "preview", version: "2.0.0", architecture: "arm64",
  packageFile: "GYInputPreview-2.0.0-arm64.pkg", objectKey: "previews/macos/2.0.0/GYInputPreview-2.0.0-arm64.pkg",
  sha256: "A".repeat(64), bytes: 3, state: "candidate", appSigned: "Apple Development (local)", pkgSigned: false, notarized: false
};
const env = () => ({ RELEASES: { get: async (key) => {
  if (key === "previews/macos/latest.json") return { json: async () => manifest };
  if (key === manifest.objectKey) return { size: 3, body: "pkg", httpEtag: "\"test\"" };
  return null;
} } });

test("preview info is explicitly macOS-only and candidate", async () => {
  const response = await worker.fetch(new Request("https://mac-preview.shurufa.wang/"), env());
  const body = await response.json();
  assert.equal(response.status, 200); assert.equal(body.platform, "macos"); assert.equal(body.pkgSigned, false);
});

test("latest download avoids stale browser caching", async () => {
  const response = await worker.fetch(new Request("https://mac-preview.shurufa.wang/download"), env());
  assert.equal(response.status, 200); assert.equal(response.headers.get("x-gy-release-channel"), "preview");
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.equal(await response.text(), "pkg");
});

test("versioned download can be cached forever", async () => {
  const response = await worker.fetch(new Request("https://mac-preview.shurufa.wang/download/macos/preview/2.0.0"), env());
  assert.equal(response.headers.get("cache-control"), "public, max-age=31536000, immutable");
});
