const LATEST_KEY = "releases/latest.json";
const VERSION = /^\d+\.\d+\.\d+$/;
const SHA256 = /^[A-Fa-f0-9]{64}$/;

const PLATFORM = {
  windows: {
    extension: "exe",
    contentType: "application/vnd.microsoft.portable-executable",
    expectedFile: (version) => `GYInputSetup-${version}.exe`,
    expectedKey: (version, file) => `releases/${version}/windows/${file}`,
    architecture: "x64"
  },
  macos: {
    extension: "pkg",
    contentType: "application/vnd.apple.installer+xml",
    expectedFile: (version) => `GYInput-${version}-arm64.pkg`,
    expectedKey: (version, file) => `releases/${version}/macos/${file}`,
    architecture: "arm64"
  }
};

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

function isPublishedAsset(asset) {
  return asset && ["candidate", "signed", "notarized", "stable"].includes(asset.state);
}

function validateAsset(release, platform, required = true) {
  const spec = PLATFORM[platform];
  const asset = release[platform];
  if (!asset || typeof asset !== "object") {
    if (required) throw new Error(`${platform} release is missing`);
    return null;
  }
  if (!isPublishedAsset(asset)) {
    if (required) throw new Error(`${platform} release is not verified for publication`);
    return null;
  }
  if (asset.version && asset.version !== release.version) throw new Error(`${platform} version does not match release version`);
  if (asset.architecture && asset.architecture !== spec.architecture) throw new Error(`${platform} architecture is invalid`);
  const file = asset.setupFile || asset.packageFile;
  if (file !== spec.expectedFile(release.version)) throw new Error(`${platform} filename does not match version`);
  if (!SHA256.test(asset.sha256 || "")) throw new Error(`${platform} SHA-256 is missing or invalid`);
  if (!Number.isSafeInteger(asset.bytes) || asset.bytes <= 0) throw new Error(`${platform} byte size is missing or invalid`);
  const expectedKey = spec.expectedKey(release.version, file);
  if (asset.objectKey && asset.objectKey !== expectedKey) throw new Error(`${platform}.objectKey does not match the immutable versioned path`);
  if (platform === "macos" && release.channel === "stable" && (!asset.signed || !asset.notarized || asset.state !== "notarized")) {
    throw new Error("stable macOS release requires a signed and notarized PKG");
  }
  return { ...asset, file, objectKey: expectedKey };
}

function validateRelease(release) {
  if (!release || typeof release !== "object") throw new Error("latest.json is not an object");
  if (release.schemaVersion !== 1) throw new Error("unsupported release schema");
  if (!VERSION.test(release.version) || release.coreVersion !== release.version || release.hostVersion !== release.version) {
    throw new Error("package, core, and Host versions must be identical");
  }
  if (!["candidate", "beta", "stable"].includes(release.channel)) throw new Error("release channel is invalid");
  return {
    ...release,
    windows: validateAsset(release, "windows"),
    macos: validateAsset(release, "macos")
  };
}

async function loadLatest(env) {
  const object = await env.RELEASES.get(LATEST_KEY);
  if (!object) throw new Error("latest.json is missing from R2");
  return validateRelease(await object.json());
}

function assetInfo(release, platform) {
  const asset = release[platform];
  const spec = PLATFORM[platform];
  return {
    version: release.version,
    platform,
    architecture: asset.architecture || spec.architecture,
    filename: asset.file,
    bytes: asset.bytes,
    sha256: asset.sha256.toUpperCase(),
    state: asset.state,
    signed: platform === "macos" ? Boolean(asset.signed) : undefined,
    notarized: platform === "macos" ? Boolean(asset.notarized) : undefined,
    downloadUrl: `/download/${platform}/latest`,
    sha256Url: `/${platform}/latest/sha256`
  };
}

function releaseInfo(release, env) {
  return {
    version: release.version,
    coreVersion: release.coreVersion,
    hostVersion: release.hostVersion,
    channel: release.channel,
    publishedAtUtc: release.publishedAtUtc,
    releaseStatus: env.RELEASE_STATUS || release.channel,
    platforms: {
      windows: assetInfo(release, "windows"),
      macos: assetInfo(release, "macos")
    }
  };
}

function downloadHeaders(release, platform, object) {
  const asset = release[platform];
  const spec = PLATFORM[platform];
  const headers = new Headers({
    "content-type": spec.contentType,
    "content-disposition": `attachment; filename="${asset.file}"`,
    "content-length": String(object.size),
    "cache-control": "public, max-age=31536000, immutable",
    "x-content-type-options": "nosniff",
    "x-gy-release-version": release.version,
    "x-gy-release-channel": release.channel,
    "x-gy-platform": platform
  });
  if (object.httpEtag) headers.set("etag", object.httpEtag);
  return headers;
}

async function download(release, platform, env, method) {
  const asset = release[platform];
  const object = await env.RELEASES.get(asset.objectKey);
  if (!object) return json({ error: "release_not_found", platform }, 404);
  if (object.size !== asset.bytes) return json(invalidRelease(`R2 ${platform} object byte size does not match latest.json`), 503);
  return new Response(method === "HEAD" ? null : object.body, { headers: downloadHeaders(release, platform, object) });
}

function platformFromPath(path, release) {
  for (const platform of Object.keys(PLATFORM)) {
    const versionPath = `/${platform}/${release.version}`;
    if (path === `/${platform}/latest` || path === versionPath) return { platform, action: "info" };
    if (path === `/${platform}/latest/sha256` || path === `${versionPath}/sha256`) return { platform, action: "sha256" };
    if (path === `/download/${platform}/latest` || path === `${versionPath}/download`) return { platform, action: "download" };
  }
  if (path === "/latest.exe" || path === "/download/latest.exe") return { platform: "windows", action: "download" };
  if (path === "/latest.pkg" || path === "/download/latest.pkg") return { platform: "macos", action: "download" };
  return null;
}

export default {
  async fetch(request, env) {
    if (request.method !== "GET" && request.method !== "HEAD") return json({ error: "method_not_allowed" }, 405);
    const path = new URL(request.url).pathname.replace(/\/+$/, "") || "/";
    let release;
    try {
      release = await loadLatest(env);
    } catch (error) {
      return json(invalidRelease(error.message), 503);
    }
    if (path === "/" || path === "/health" || path === "/api/releases/latest") {
      return json({ service: "GY Input Method release service", ...releaseInfo(release, env) });
    }
    const route = platformFromPath(path, release);
    if (!route) return json({ error: "not_found" }, 404);
    if (route.action === "info") return json(assetInfo(release, route.platform));
    if (route.action === "sha256") {
      const asset = release[route.platform];
      return new Response(`${asset.sha256.toUpperCase()}  ${asset.file}\n`, {
        headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store", "x-content-type-options": "nosniff" }
      });
    }
    return download(release, route.platform, env, request.method);
  }
};
