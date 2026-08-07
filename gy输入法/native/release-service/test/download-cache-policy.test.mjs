import assert from "node:assert/strict";
import test from "node:test";
import worker from "../src/release-worker-v2.js";

const release = {
  schemaVersion: 2,
  releaseId: "windows-0.9.29",
  channel: "candidate",
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
  }
};

function env() {
  const bytes = new Uint8Array([1, 2, 3]);
  return {
    RELEASES: {
      async get(key) {
        if (key === "releases/latest.json") return { async json() { return release; } };
        if (key === "releases/0.9.29/windows/GYInputSetup-0.9.29.exe") return object(bytes);
        return null;
      }
    }
  };
}

function object(bytes) {
  return {
    size: bytes.byteLength,
    body: new ReadableStream({ start(controller) { controller.enqueue(bytes); controller.close(); } }),
    httpEtag: '"test"'
  };
}

test("latest aliases cannot cache a prior installer", async () => {
  const info = await worker.fetch(new Request("https://example.test/api/releases/latest"), env());
  const payload = await info.json();
  assert.equal(payload.platforms.windows.downloadUrl, "/download/windows/0.9.29");

  const latest = await worker.fetch(new Request("https://example.test/download/windows/latest"), env());
  assert.equal(latest.headers.get("cache-control"), "no-store");

  const versioned = await worker.fetch(new Request("https://example.test/download/windows/0.9.29"), env());
  assert.equal(versioned.headers.get("cache-control"), "public, max-age=31536000, immutable");

  const legacy = await worker.fetch(new Request("https://example.test/download/latest.exe"), env());
  assert.equal(legacy.headers.get("cache-control"), "no-store");
});
