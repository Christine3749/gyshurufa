const LATEST_KEY = "previews/macos/latest.json";
const VERSION = /^\d+\.\d+\.\d+$/;
const SHA256 = /^[A-F0-9]{64}$/;

const json = (body, status = 200) => new Response(JSON.stringify(body, null, 2), {
  status, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", "x-content-type-options": "nosniff" }
});

function validate(manifest) {
  if (!manifest || manifest.schemaVersion !== 1 || manifest.platform !== "macos" || manifest.channel !== "preview") throw new Error("invalid preview manifest");
  if (!VERSION.test(manifest.version) || manifest.architecture !== "arm64") throw new Error("invalid preview version or architecture");
  const file = `GYInputPreview-${manifest.version}-arm64.pkg`;
  if (manifest.packageFile !== file || manifest.objectKey !== `previews/macos/${manifest.version}/${file}`) throw new Error("preview file path is invalid");
  if (!SHA256.test(manifest.sha256) || !Number.isSafeInteger(manifest.bytes) || manifest.bytes <= 0) throw new Error("preview hash metadata is invalid");
  if (manifest.state !== "candidate" || manifest.pkgSigned || manifest.notarized) throw new Error("preview state is invalid");
  return manifest;
}

async function latest(env) {
  const object = await env.RELEASES.get(LATEST_KEY);
  if (!object) throw new Error("macOS preview is not published");
  return validate(await object.json());
}

function info(manifest) {
  return {
    platform: manifest.platform, channel: manifest.channel, version: manifest.version, architecture: manifest.architecture,
    packageFile: manifest.packageFile, sha256: manifest.sha256, bytes: manifest.bytes, state: manifest.state,
    appSigned: manifest.appSigned, pkgSigned: manifest.pkgSigned, notarized: manifest.notarized,
    warning: "Candidate preview: separate input source; not a notarized stable release.", downloadUrl: "/download/macos/preview/latest"
  };
}

function headers(manifest, object) {
  const value = new Headers({
    "content-type": "application/vnd.apple.installer+xml", "content-disposition": `attachment; filename="${manifest.packageFile}"`,
    "content-length": String(object.size), "cache-control": "public, max-age=31536000, immutable", "x-content-type-options": "nosniff",
    "x-gy-release-platform": "macos", "x-gy-release-channel": "preview", "x-gy-release-version": manifest.version
  });
  if (object.httpEtag) value.set("etag", object.httpEtag);
  return value;
}

export default {
  async fetch(request, env) {
    if (!["GET", "HEAD"].includes(request.method)) return json({ error: "method_not_allowed" }, 405);
    let manifest;
    try { manifest = await latest(env); } catch (error) { return json({ error: "invalid_preview", message: error.message }, 503); }
    const path = new URL(request.url).pathname.replace(/\/+$/, "");
    if (["/api/releases/macos/preview/latest", "/api/releases/macos/preview/health", "/health"].includes(path)) return json(info(manifest));
    if (!["/download/macos/preview/latest", `/download/macos/preview/${manifest.version}`].includes(path)) return json({ error: "not_found" }, 404);
    const object = await env.RELEASES.get(manifest.objectKey);
    if (!object) return json({ error: "release_not_found" }, 404);
    if (object.size !== manifest.bytes) return json({ error: "invalid_preview", message: "R2 byte size does not match manifest" }, 503);
    return new Response(request.method === "HEAD" ? null : object.body, { headers: headers(manifest, object) });
  }
};
