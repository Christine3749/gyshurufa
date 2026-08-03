import assert from "node:assert/strict";
import test from "node:test";
import worker from "../src/release-worker-v2.js";

const release = {
  schemaVersion: 1,
  channel: "candidate",
  version: "0.9.29",
  coreVersion: "0.9.29",
  hostVersion: "0.9.29",
  windows: {
    setupFile: "GYInputSetup-0.9.29.exe",
    sha256: "F9FE27114105F02DE4484BB7B0F05071A08E2B0EC76A097832FEC9A4E78D7BF1",
    bytes: 3,
    state: "candidate"
  },
  macos: {
    packageFile: "GYInput-0.9.29-arm64.pkg",
    sha256: "A9FE27114105F02DE4484BB7B0F05071A08E2B0EC76A097832FEC9A4E78D7BF2",
    bytes: 4,
    architecture: "arm64",
    signed: true,
    notarized: true,
    state: "notarized"
  }
};

function env(overrides = {}) {
  const windows = new Uint8Array([1, 2, 3]);
  const macos = new Uint8Array([4, 5, 6, 7]);
  const selected = overrides.release ?? release;
  return {
    RELEASE_STATUS: "candidate",
    RELEASES: {
      async get(key) {
        if (key === "releases/latest.json") return { async json() { return selected; } };
        if (key === "releases/0.9.29/windows/GYInputSetup-0.9.29.exe") return object(windows, overrides.windowsSize);
        if (key === "releases/0.9.29/macos/GYInput-0.9.29-arm64.pkg") return object(macos, overrides.macosSize);
        return null;
      }
    }
  };
}

function object(bytes, overrideSize) {
  return {
    size: overrideSize ?? bytes.byteLength,
    body: new ReadableStream({ start(controller) { controller.enqueue(bytes); controller.close(); } }),
    httpEtag: '"test"'
  };
}

test("latest release requires both Windows and notarized Mac assets", async () => {
  const response = await worker.fetch(new Request("https://example.test/api/releases/latest"), env());
  assert.equal(response.status, 200);
  assert.equal((await response.json()).version, "0.9.29");
});

test("Windows and macOS latest downloads resolve only immutable platform objects", async () => {
  const windows = await worker.fetch(new Request("https://example.test/download/windows/latest"), env());
  assert.equal(windows.status, 200);
  assert.equal(windows.headers.get("content-disposition"), 'attachment; filename="GYInputSetup-0.9.29.exe"');
  const macos = await worker.fetch(new Request("https://example.test/download/macos/latest"), env());
  assert.equal(macos.status, 200);
  assert.equal(macos.headers.get("content-disposition"), 'attachment; filename="GYInput-0.9.29-arm64.pkg"');
});

test("Mac bytes mismatch blocks latest instead of exposing a mixed release", async () => {
  const response = await worker.fetch(new Request("https://example.test/download/macos/latest"), env({ macosSize: 5 }));
  assert.equal(response.status, 503);
  assert.equal((await response.json()).error, "invalid_release_manifest");
});

test("unverified Mac assets block the public latest pointer", async () => {
  const incomplete = structuredClone(release);
  incomplete.macos.state = "verification-required";
  const response = await worker.fetch(new Request("https://example.test/api/releases/latest"), env({ release: incomplete }));
  assert.equal(response.status, 503);
});
