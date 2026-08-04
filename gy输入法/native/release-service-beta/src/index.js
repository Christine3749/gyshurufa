const LATEST_KEY = "releases/latest.json";
const VERSION = /^\d+\.\d+\.\d+$/;
const SHA256 = /^[A-Fa-f0-9]{64}$/;

const json = (body, status = 200) => new Response(JSON.stringify(body, null, 2), {
  status,
  headers: {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
    "x-content-type-options": "nosniff"
  }
});

function invalidRelease(message) {
  return { error: "invalid_release_manifest", message };
}

function releaseObjectKey(release) {
  const configured = release.windows.objectKey;
  const expected = `releases/${release.version}/${release.windows.setupFile}`;
  if (configured && configured !== expected) throw new Error("windows.objectKey does not match the immutable versioned path");
  return expected;
}

function validateRelease(release) {
  if (!release || typeof release !== "object") throw new Error("latest.json is not an object");
  if (release.schemaVersion !== 1) throw new Error("unsupported release schema");
  if (!VERSION.test(release.version) || release.coreVersion !== release.version || release.hostVersion !== release.version) {
    throw new Error("package, core, and Host versions must be identical");
  }
  if (!release.windows || typeof release.windows !== "object") throw new Error("windows release is missing");
  if (release.windows.setupFile !== `GYInputSetup-${release.version}.exe`) throw new Error("setupFile does not match version");
  if (!SHA256.test(release.windows.sha256 || "")) throw new Error("SHA-256 is missing or invalid");
  if (!Number.isSafeInteger(release.windows.bytes) || release.windows.bytes <= 0) throw new Error("installer byte size is missing or invalid");
  releaseObjectKey(release);
  return release;
}

async function loadLatest(env) {
  const object = await env.RELEASES.get(LATEST_KEY);
  if (!object) throw new Error("latest.json is missing from R2");
  return validateRelease(await object.json());
}

function releaseInfo(release, env) {
  return {
    version: release.version,
    coreVersion: release.coreVersion,
    hostVersion: release.hostVersion,
    channel: release.channel,
    platform: "windows",
    architecture: "x64",
    filename: release.windows.setupFile,
    bytes: release.windows.bytes,
    sha256: release.windows.sha256.toUpperCase(),
    releaseStatus: env.RELEASE_STATUS || release.windows.state,
    downloadUrl: "/latest.exe",
    sha256Url: "/windows/latest/sha256"
  };
}

function downloadHeaders(release, object) {
  const headers = new Headers({
    "content-type": "application/vnd.microsoft.portable-executable",
    "content-disposition": `attachment; filename="${release.windows.setupFile}"`,
    "content-length": String(object.size),
    "cache-control": "public, max-age=31536000, immutable",
    "x-content-type-options": "nosniff",
    "x-gy-release-version": release.version,
    "x-gy-release-channel": release.channel || "candidate"
  });
  if (object.httpEtag) headers.set("etag", object.httpEtag);
  return headers;
}

async function download(release, env, method) {
  const object = await env.RELEASES.get(releaseObjectKey(release));
  if (!object) return json({ error: "release_not_found" }, 404);
  if (object.size !== release.windows.bytes) {
    return json(invalidRelease("R2 object byte size does not match latest.json"), 503);
  }
  return new Response(method === "HEAD" ? null : object.body, { headers: downloadHeaders(release, object) });
}

export default {
  async fetch(request, env) {
    if (request.method !== "GET" && request.method !== "HEAD") return json({ error: "method_not_allowed" }, 405);
    const path = new URL(request.url).pathname.replace(/\/+$/, "") || "/";
    if (path === "/" || path === "/health") {
      try {
        const release = await loadLatest(env);
        return json({ service: "GY Input Method release service", status: env.RELEASE_STATUS, latest: releaseInfo(release, env) });
      } catch (error) {
        return json(invalidRelease(error.message), 503);
      }
    }

    let release;
    try { release = await loadLatest(env); }
    catch (error) { return json(invalidRelease(error.message), 503); }

    const versionPath = `/windows/${release.version}`;
    if (path === "/windows/latest" || path === versionPath) return json(releaseInfo(release, env));
    if (path === "/windows/latest/sha256" || path === `${versionPath}/sha256`) {
      return new Response(`${release.windows.sha256.toUpperCase()}  ${release.windows.setupFile}\n`, {
        headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store", "x-content-type-options": "nosniff" }
      });
    }
    if (path === "/latest.exe" || path === "/download/latest.exe" || path === `${versionPath}/download`) {
      return download(release, env, request.method);
    }
    return json({ error: "not_found" }, 404);
  }
};
