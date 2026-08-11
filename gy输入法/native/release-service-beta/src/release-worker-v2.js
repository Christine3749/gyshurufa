const DEFAULT_MANIFEST_KEY = "candidates/windows/0.10.90/release.json";
const VERSION = /^\d+\.\d+\.\d+$/;
const SHA256 = /^[A-Fa-f0-9]{64}$/;
const CONTENT_TYPE = "application/vnd.microsoft.portable-executable";

const json = (body, status = 200) => new Response(JSON.stringify(body, null, 2), {
  status,
  headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", "x-content-type-options": "nosniff" }
});

function readWindowsCandidate(raw) {
  const asset = raw?.windows;
  if (!raw || raw.schemaVersion !== 2 || raw.channel !== "candidate" || !asset) throw new Error("candidate manifest is invalid");
  if (!VERSION.test(asset.version || "") || asset.coreVersion !== asset.version || asset.hostVersion !== asset.version) throw new Error("candidate versions are inconsistent");
  if (asset.architecture !== "x64" || asset.setupFile !== `GYInputSetup-${asset.version}.exe`) throw new Error("candidate installer identity is invalid");
  if (!SHA256.test(asset.sha256 || "") || !Number.isSafeInteger(asset.bytes) || asset.bytes <= 0) throw new Error("candidate hash or size is invalid");
  if (asset.state !== "candidate") throw new Error("candidate state is invalid");
  return { ...asset, objectKey: `releases/${asset.version}/windows/${asset.setupFile}` };
}

async function loadCandidate(env) {
  const key = env.RELEASE_MANIFEST_KEY || DEFAULT_MANIFEST_KEY;
  const object = await env.RELEASES.get(key);
  if (!object) throw new Error("candidate manifest is missing");
  return readWindowsCandidate(await object.json());
}

function info(asset) {
  return {
    version: asset.version,
    platform: "windows",
    architecture: "x64",
    filename: asset.setupFile,
    bytes: asset.bytes,
    sha256: asset.sha256.toUpperCase(),
    state: "candidate",
    available: true,
    downloadUrl: `/download/windows/${asset.version}`,
    sha256Url: `/download/windows/${asset.version}/sha256`
  };
}

function matches(path, asset) {
  const base = `/download/windows/${asset.version}`;
  return path === "/download/windows/latest" || path === "/download/latest.exe" || path === "/latest.exe" ||
    path === base || path === `${base}/download`;
}

function matchesSha(path, asset) {
  const base = `/download/windows/${asset.version}/sha256`;
  return path === "/download/windows/latest/sha256" || path === base;
}

async function download(asset, env, method) {
  const object = await env.RELEASES.get(asset.objectKey);
  if (!object) return json({ error: "candidate_release_not_found", platform: "windows" }, 404);
  if (object.size !== asset.bytes) return json({ error: "candidate_size_mismatch" }, 503);
  const headers = new Headers({
    "content-type": CONTENT_TYPE,
    "content-disposition": `attachment; filename="${asset.setupFile}"`,
    "content-length": String(object.size),
    "cache-control": "public, max-age=31536000, immutable",
    "x-content-type-options": "nosniff",
    "x-gy-release-version": asset.version,
    "x-gy-release-channel": "candidate",
    "x-gy-platform": "windows"
  });
  if (object.httpEtag) headers.set("etag", object.httpEtag);
  return new Response(method === "HEAD" ? null : object.body, { headers });
}

export default {
  async fetch(request, env) {
    if (!["GET", "HEAD"].includes(request.method)) return json({ error: "method_not_allowed" }, 405);
    const path = new URL(request.url).pathname.replace(/\/+$/, "") || "/";
    let asset;
    try { asset = await loadCandidate(env); } catch (error) { return json({ error: "candidate_release_unavailable", message: error.message }, 503); }
    if (["/", "/health", "/api/releases/latest"].includes(path)) {
      return json({ service: "GY Input Method candidate release service", channel: "candidate", platforms: { windows: info(asset) } });
    }
    if (path === `/windows/${asset.version}` || path === "/windows/latest") return json(info(asset));
    if (matchesSha(path, asset)) return new Response(`${asset.sha256.toUpperCase()}  ${asset.setupFile}\n`, { headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store", "x-content-type-options": "nosniff" } });
    if (matches(path, asset)) return download(asset, env, request.method);
    return json({ error: "not_found" }, 404);
  }
};
