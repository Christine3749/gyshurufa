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
  const lexicon = new TextEncoder().encode("about\naccount\nagent\n");
  const lexiconManifest = {
    schemaVersion: 1,
    id: "gy-ime-english-mixed",
    format: "gy-ime-english-v1",
    version: "2026.08.13.1",
    sha256: "A6AA4780DE766E97875456D7AB1D5E95B7AADB601133387C76F4D9BE840F94D8",
    bytes: lexicon.byteLength,
    entryCount: 3,
    downloadUrl: "/api/ciku/ime/lexicon/2026.08.13.1"
  };
  const selected = overrides.release ?? release;
  const candidate = overrides.candidate ?? release;
  return {
    RELEASE_STATUS: "candidate",
    RELEASES: {
      async head(key) {
        if (key === "releases/0.9.29/windows/GYInput-0.9.29.zip") return { size: 3, httpEtag: '"test"' };
        return null;
      },
      async get(key, options) {
        if (key === "releases/latest.json") return { async json() { return selected; } };
        if (key === "lexicons/english-mixed/manifest.json") return { async json() { return overrides.lexiconManifest ?? lexiconManifest; } };
        if (key === "lexicons/english-mixed/2026.08.13.1/english.tsv") return object(lexicon, overrides.lexiconSize);
        if (key === "candidates/windows/latest.json") return { async json() { return candidate; } };
        if (key === "candidates/windows/0.9.29/release.json") return { async json() { return candidate; } };
        if (key === "releases/0.9.29/windows/GYInputSetup-0.9.29.exe") return object(windows, overrides.windowsSize, options?.range);
        if (key === "releases/0.9.29/windows/GYInput-0.9.29.zip") return object(new Uint8Array([8, 9, 10]), undefined, options?.range);
        if (key === "releases/0.9.29/macos/GYInput-0.9.29-arm64.pkg") return object(macos, overrides.macosSize, options?.range);
        return null;
      }
    }
  };
}

function object(bytes, overrideSize, range) {
  const bodyBytes = range ? bytes.slice(range.offset, range.offset + range.length) : bytes;
  return {
    size: overrideSize ?? bytes.byteLength,
    body: new ReadableStream({ start(controller) { controller.enqueue(bodyBytes); controller.close(); } }),
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

test("candidate Windows download is version-pinned and never reads latest.json", async () => {
  const response = await worker.fetch(new Request("https://example.test/download/candidate/windows/0.9.29"), env());
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("content-disposition"), 'attachment; filename="GYInputSetup-0.9.29.exe"');
  assert.equal(response.headers.get("cache-control"), "public, max-age=31536000, immutable");

  const info = await worker.fetch(new Request("https://example.test/api/releases/candidate/windows/0.9.29"), env());
  assert.equal(info.status, 200);
  assert.equal((await info.json()).downloadUrl, "/download/candidate/windows/0.9.29");
});

test("versioned R2 downloads honor byte ranges without streaming the full installer", async () => {
  const response = await worker.fetch(new Request("https://example.test/download/candidate/windows/0.9.29", {
    headers: { range: "bytes=1-2" }
  }), env());
  assert.equal(response.status, 206);
  assert.equal(response.headers.get("accept-ranges"), "bytes");
  assert.equal(response.headers.get("content-range"), "bytes 1-2/3");
  assert.equal(response.headers.get("content-length"), "2");
  assert.deepEqual(new Uint8Array(await response.arrayBuffer()), new Uint8Array([2, 3]));
});

test("invalid and multiple byte ranges fail closed", async () => {
  const response = await worker.fetch(new Request("https://example.test/download/candidate/windows/0.9.29", {
    headers: { range: "bytes=99-100" }
  }), env());
  assert.equal(response.status, 416);
  assert.equal(response.headers.get("content-range"), "bytes */3");
});

test("ZIP ranges use R2 object metadata instead of installer byte size", async () => {
  const response = await worker.fetch(new Request("https://example.test/download/candidate/windows/0.9.29/zip", {
    headers: { range: "bytes=2-" }
  }), env());
  assert.equal(response.status, 206);
  assert.equal(response.headers.get("content-range"), "bytes 2-2/3");
  assert.deepEqual(new Uint8Array(await response.arrayBuffer()), new Uint8Array([10]));
});

test("latest candidate is a mutable pointer to an immutable versioned release", async () => {
  const info = await worker.fetch(new Request("https://example.test/api/releases/candidate/windows/latest"), env());
  assert.equal(info.status, 200);
  const payload = await info.json();
  assert.equal(payload.version, "0.9.29");
  assert.equal(payload.downloadUrl, "/download/candidate/windows/0.9.29");
  assert.equal(payload.zipDownloadUrl, "/download/candidate/windows/0.9.29/zip");
  assert.equal(payload.sha256Url, "/download/candidate/windows/0.9.29/sha256");

  const download = await worker.fetch(new Request("https://example.test/download/candidate/windows/latest"), env());
  assert.equal(download.status, 200);
  assert.equal(download.headers.get("content-disposition"), 'attachment; filename="GYInputSetup-0.9.29.exe"');
  assert.equal(download.headers.get("cache-control"), "no-store");
});

test("English lexicon manifest and immutable TSV share one validated R2 contract", async () => {
  const manifestResponse = await worker.fetch(new Request("https://example.test/api/ciku/ime/manifest"), env());
  assert.equal(manifestResponse.status, 200);
  const manifest = await manifestResponse.json();
  assert.equal(manifest.version, "2026.08.13.1");
  assert.equal(manifest.downloadUrl, "/api/ciku/ime/lexicon/2026.08.13.1");

  const lexicon = await worker.fetch(new Request("https://example.test/api/ciku/ime/lexicon/2026.08.13.1"), env());
  assert.equal(lexicon.status, 200);
  assert.equal(lexicon.headers.get("cache-control"), "public, max-age=31536000, immutable");
  assert.equal(await lexicon.text(), "about\naccount\nagent\n");
});

test("English lexicon download fails closed when R2 bytes differ from the manifest", async () => {
  const response = await worker.fetch(
    new Request("https://example.test/api/ciku/ime/lexicon/2026.08.13.1"),
    env({ lexiconSize: 99 })
  );
  assert.equal(response.status, 503);
  assert.equal((await response.json()).error, "invalid_english_lexicon");
});
