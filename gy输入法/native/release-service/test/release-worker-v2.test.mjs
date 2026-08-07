import assert from "node:assert/strict";
import test from "node:test";
import worker from "../src/release-worker-v2.js";

const release = {
  schemaVersion: 2,
  releaseId: "legacy-windows-0.9.29",
  channel: "candidate",
  publishedAtUtc: "2026-08-04T00:00:00Z",
  windows: {
    version: "0.9.29",
    coreVersion: "0.9.29",
    hostVersion: "0.9.29",
    architecture: "x64",
    setupFile: "GYInputSetup-0.9.29.exe",
    zipFile: "GYInput-0.9.29.zip",
    sha256: "F9FE27114105F02DE4484BB7B0F05071A08E2B0EC76A097832FEC9A4E78D7BF1",
    bytes: 3,
    state: "candidate"
  },
  macos: {
    version: "0.9.29",
    architecture: "arm64",
    packageFile: "GYInput-0.9.29-arm64.pkg",
    sha256: "A9FE27114105F02DE4484BB7B0F05071A08E2B0EC76A097832FEC9A4E78D7BF2",
    bytes: 4,
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
        if (key === "releases/0.9.29/windows/GYInput-0.9.29.zip") return object(new Uint8Array([8, 9, 10]));
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
  const payload = await response.json();
  assert.equal(payload.platforms.windows.version, "0.9.29");
  assert.equal(payload.platforms.macos.version, "0.9.29");
  assert.equal(payload.platforms.windows.available, true);
  assert.equal(payload.platforms.macos.available, true);
});

test("Windows and macOS latest downloads resolve only immutable platform objects", async () => {
  const windows = await worker.fetch(new Request("https://example.test/download/windows/latest"), env());
  assert.equal(windows.status, 200);
  assert.equal(windows.headers.get("content-disposition"), 'attachment; filename="GYInputSetup-0.9.29.exe"');
  const macos = await worker.fetch(new Request("https://example.test/download/macos/latest"), env());
  assert.equal(macos.status, 200);
  assert.equal(macos.headers.get("content-disposition"), 'attachment; filename="GYInput-0.9.29-arm64.pkg"');
});

test("Windows ZIP download resolves the same immutable release version", async () => {
  const response = await worker.fetch(new Request("https://example.test/download/latest.zip"), env());
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("content-type"), "application/zip");
  assert.equal(response.headers.get("content-disposition"), 'attachment; filename="GYInput-0.9.29.zip"');
  assert.equal(response.headers.get("x-gy-release-version"), "0.9.29");
});

test("Mac bytes mismatch blocks latest instead of exposing a mixed release", async () => {
  const response = await worker.fetch(new Request("https://example.test/download/macos/latest"), env({ macosSize: 5 }));
  assert.equal(response.status, 503);
  assert.equal((await response.json()).error, "invalid_release_manifest");
});

test("unverified Mac assets do not block Windows delivery from latest metadata", async () => {
  const incomplete = structuredClone(release);
  incomplete.macos.state = "verification-required";
  const response = await worker.fetch(new Request("https://example.test/api/releases/latest"), env({ release: incomplete }));
  assert.equal(response.status, 200);
  const payload = await response.json();
  assert.equal(payload.platforms.windows.version, "0.9.29");
  assert.equal(payload.platforms.windows.available, true);
  assert.equal(payload.platforms.macos.version, "0.9.29");
  assert.equal(payload.platforms.macos.available, false);
});
