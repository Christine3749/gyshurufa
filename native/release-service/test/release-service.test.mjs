import assert from "node:assert/strict";
import test from "node:test";
import worker from "../src/index.js";

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
  }
};

function env(overrides = {}) {
  const binary = new Uint8Array([1, 2, 3]);
  return {
    RELEASE_STATUS: "candidate",
    RELEASES: {
      async get(key) {
        if (key === "releases/latest.json") return { async json() { return overrides.release ?? release; } };
        if (key === "releases/0.9.29/GYInputSetup-0.9.29.exe") return { size: overrides.size ?? binary.byteLength, body: new ReadableStream({ start(controller) { controller.enqueue(binary); controller.close(); } }), httpEtag: '"test"' };
        return null;
      }
    }
  };
}

test("latest endpoint is driven by R2 latest.json, not a hard-coded version", async () => {
  const response = await worker.fetch(new Request("https://example.test/windows/latest"), env());
  assert.equal(response.status, 200);
  assert.equal((await response.json()).version, "0.9.29");
});

test("latest.exe streams only the immutable versioned R2 object", async () => {
  const response = await worker.fetch(new Request("https://example.test/latest.exe"), env());
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("content-disposition"), 'attachment; filename="GYInputSetup-0.9.29.exe"');
  assert.equal(response.headers.get("x-gy-release-version"), "0.9.29");
  assert.deepEqual([...new Uint8Array(await response.arrayBuffer())], [1, 2, 3]);
});

test("size mismatch refuses a broken latest pointer", async () => {
  const response = await worker.fetch(new Request("https://example.test/latest.exe"), env({ size: 4 }));
  assert.equal(response.status, 503);
  assert.equal((await response.json()).error, "invalid_release_manifest");
});
