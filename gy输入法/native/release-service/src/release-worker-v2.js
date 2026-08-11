const LATEST_KEY = "releases/latest.json";
const VERSION = /^\d+\.\d+\.\d+$/;
const SHA256 = /^[A-Fa-f0-9]{64}$/;
const CACHE_CONTROL_LATEST = "no-store";
const CACHE_CONTROL_VERSIONED = "public, max-age=31536000, immutable";
const BETA_MACOS_KEY = "beta/macos/latest.json";
const OFFICIAL_DOWNLOAD_ORIGIN = "https://www.shurufa.wang";
const WINDOWS_ZIP_CONTENT_TYPE = "application/zip";
const PLATFORM = {
  windows: { extension: "exe", contentType: "application/vnd.microsoft.portable-executable", architecture: "x64", file: (v) => `GYInputSetup-${v}.exe`, key: (v, f) => `releases/${v}/windows/${f}` },
  macos: { extension: "pkg", contentType: "application/vnd.apple.installer+xml", architecture: "arm64", file: (v) => `GYInput-${v}-arm64.pkg`, key: (v, f) => `releases/${v}/macos/${f}` }
};
const json = (body, status = 200) => new Response(JSON.stringify(body, null, 2), { status, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", "x-content-type-options": "nosniff" } });
const invalidRelease = (message) => ({ error: "invalid_release_manifest", message });
const publishedStates = new Set(["candidate", "signed", "notarized", "stable"]);

function validateAsset(release, platform, required) {
  const spec = PLATFORM[platform];
  const asset = release[platform];
  if (!asset || typeof asset !== "object") { if (required) throw new Error(`${platform} release is missing`); return null; }
  if (!VERSION.test(asset.version || "")) throw new Error(`${platform} version is invalid`);
  if (asset.architecture !== spec.architecture) throw new Error(`${platform} architecture is invalid`);
  if (!publishedStates.has(asset.state)) { if (required) throw new Error(`${platform} release is not verified for publication`); return { ...asset, available: false }; }
  const file = asset.setupFile || asset.packageFile;
  if (file !== spec.file(asset.version)) throw new Error(`${platform} filename does not match its version`);
  if (!SHA256.test(asset.sha256 || "") || !Number.isSafeInteger(asset.bytes) || asset.bytes <= 0) throw new Error(`${platform} hash/bytes are invalid`);
  if (asset.objectKey && asset.objectKey !== spec.key(asset.version, file)) throw new Error(`${platform}.objectKey does not match immutable versioned path`);
  if (platform === "macos" && release.channel === "stable" && (!asset.signed || !asset.notarized || asset.state !== "notarized")) throw new Error("stable macOS release requires signed and notarized PKG");
  return { ...asset, file, objectKey: spec.key(asset.version, file), available: true };
}

function normalizeLegacyRelease(release) {
  if (release?.schemaVersion !== 1) return release;
  const legacyVersion = release.version;
  const legacyMacFile = release.macos?.packageFile;
  const legacyMacVersion = legacyMacFile?.match(/^GYInput-(\d+\.\d+\.\d+)-arm64\.pkg$/)?.[1] || legacyVersion;
  return {
    schemaVersion: 2,
    releaseId: `legacy-windows-${legacyVersion}`,
    channel: release.channel,
    publishedAtUtc: release.publishedAtUtc || null,
    windows: {
      version: legacyVersion,
      coreVersion: release.coreVersion,
      hostVersion: release.hostVersion,
      architecture: "x64",
      setupFile: release.windows?.setupFile,
      zipFile: release.windows?.zipFile,
      sha256: release.windows?.sha256,
      bytes: release.windows?.bytes,
      state: release.windows?.state === "verified" ? "candidate" : release.windows?.state
    },
    macos: {
      version: legacyMacVersion,
      architecture: "arm64",
      state: release.macos?.state,
      packageFile: legacyMacFile,
      sha256: release.macos?.sha256,
      bytes: release.macos?.bytes,
      signed: release.macos?.signed,
      notarized: release.macos?.notarized
    }
  };
}
function validateRelease(rawRelease) {
  const release = normalizeLegacyRelease(rawRelease);
  if (!release || typeof release !== "object" || release.schemaVersion !== 2) throw new Error("unsupported release schema; expected 1 or 2");
  if (!release.releaseId || !["candidate", "beta", "stable"].includes(release.channel)) throw new Error("release identity or channel is invalid");
  const windows = validateAsset(release, "windows", true);
  if (windows.coreVersion !== windows.version || windows.hostVersion !== windows.version) throw new Error("Windows package, core, and Host versions must be identical");
  const macos = validateAsset(release, "macos", false);
  return { ...release, windows, macos };
}
async function loadLatest(env) { const key = env.RELEASE_MANIFEST_KEY || LATEST_KEY; const obj = await env.RELEASES.get(key); if (!obj) throw new Error("release manifest is missing from R2"); return validateRelease(await obj.json()); }
function validateBetaMac(raw) {
  if (!raw || typeof raw !== "object" || raw.schemaVersion !== 1 || raw.channel !== "beta") throw new Error("beta macOS manifest is invalid");
  if (!VERSION.test(raw.version || "") || !Number.isSafeInteger(raw.build) || raw.build <= 0) throw new Error("beta macOS version/build is invalid");
  if (raw.architecture !== "arm64" || raw.packageFile !== PLATFORM.macos.file(raw.version)) throw new Error("beta macOS package identity is invalid");
  if (!SHA256.test(raw.sha256 || "") || !Number.isSafeInteger(raw.bytes) || raw.bytes <= 0) throw new Error("beta macOS hash/bytes are invalid");
  return raw;
}
async function loadBetaMac(env) { const obj = await env.RELEASES.get(BETA_MACOS_KEY); if (!obj) throw new Error("beta macOS manifest is missing"); return validateBetaMac(await obj.json()); }
function betaMacFeed(beta) { return { version: beta.version, build: beta.build, packageURL: `${OFFICIAL_DOWNLOAD_ORIGIN}/download/beta/macos/${beta.version}/download`, sha256: beta.sha256.toUpperCase() }; }
function betaMacHeaders(beta, object, cacheControl) {
  const h = new Headers({ "content-type": PLATFORM.macos.contentType, "content-disposition": `attachment; filename="${beta.packageFile}"`, "content-length": String(object.size), "cache-control": cacheControl, "x-content-type-options": "nosniff", "x-gy-release-version": beta.version, "x-gy-release-channel": "beta", "x-gy-platform": "macos" });
  if (object.httpEtag) h.set("etag", object.httpEtag);
  return h;
}
async function downloadBetaMac(beta, env, method, cacheControl) {
  const key = `beta/macos/${beta.version}/${beta.packageFile}`;
  const object = await env.RELEASES.get(key);
  if (!object) return json({ error: "beta_release_not_found", platform: "macos" }, 404);
  if (object.size !== beta.bytes) return json(invalidRelease("R2 beta macOS object byte size does not match manifest"), 503);
  return new Response(method === "HEAD" ? null : object.body, { headers: betaMacHeaders(beta, object, cacheControl) });
}
async function betaMacRoute(path, env, method) {
  let beta;
  try { beta = await loadBetaMac(env); } catch (error) { return json({ error: "beta_release_unavailable", message: error.message }, 404); }
  if (path === "/download/macos-beta.json") return json(betaMacFeed(beta));
  const versionPath = `/download/beta/macos/${beta.version}`;
  if (path === "/download/beta/macos/latest" || path === "/download/beta/macos/latest/download") return downloadBetaMac(beta, env, method, CACHE_CONTROL_LATEST);
  if (path === versionPath || path === `${versionPath}/download`) return downloadBetaMac(beta, env, method, CACHE_CONTROL_VERSIONED);
  if (path === "/download/beta/macos/latest/sha256" || path === `${versionPath}/sha256`) return new Response(`${beta.sha256.toUpperCase()}  ${beta.packageFile}\n`, { headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store", "x-content-type-options": "nosniff" } });
  return null;
}
function assetInfo(asset, platform) {
  const spec = PLATFORM[platform];
  if (!asset) return { platform, state: "unavailable", available: false };
  return { version: asset.version, platform, architecture: asset.architecture || spec.architecture, filename: asset.file || asset.packageFile || asset.setupFile || null, bytes: asset.bytes || 0, sha256: asset.sha256 ? asset.sha256.toUpperCase() : null, state: asset.state, signed: platform === "macos" ? Boolean(asset.signed) : undefined, notarized: platform === "macos" ? Boolean(asset.notarized) : undefined, available: Boolean(asset.available), downloadUrl: asset.available ? `/download/${platform}/${asset.version}` : null, sha256Url: asset.available ? `/${platform}/latest/sha256` : null };
}
function releaseInfo(release, env) { return { releaseId: release.releaseId, channel: release.channel, publishedAtUtc: release.publishedAtUtc, releaseStatus: env.RELEASE_STATUS || release.channel, platforms: { windows: assetInfo(release.windows, "windows"), macos: assetInfo(release.macos, "macos") } }; }
function headers(release, platform, object, cacheControl) { const asset = release[platform]; const h = new Headers({ "content-type": PLATFORM[platform].contentType, "content-disposition": `attachment; filename="${asset.file}"`, "content-length": String(object.size), "cache-control": cacheControl, "x-content-type-options": "nosniff", "x-gy-release-version": asset.version, "x-gy-release-channel": release.channel, "x-gy-platform": platform }); if (object.httpEtag) h.set("etag", object.httpEtag); return h; }
async function download(release, platform, env, method, cacheControl) { const asset = release[platform]; if (!asset || !asset.available) return json({ error: "platform_not_verified", platform }, 409); const object = await env.RELEASES.get(asset.objectKey); if (!object) return json({ error: "release_not_found", platform }, 404); if (object.size !== asset.bytes) return json(invalidRelease(`R2 ${platform} object byte size does not match latest.json`), 503); return new Response(method === "HEAD" ? null : object.body, { headers: headers(release, platform, object, cacheControl) }); }
function windowsZipHeaders(release, object, cacheControl) { const asset = release.windows; const h = new Headers({ "content-type": WINDOWS_ZIP_CONTENT_TYPE, "content-disposition": `attachment; filename="${asset.zipFile}"`, "content-length": String(object.size), "cache-control": cacheControl, "x-content-type-options": "nosniff", "x-gy-release-version": asset.version, "x-gy-release-channel": release.channel, "x-gy-platform": "windows" }); if (object.httpEtag) h.set("etag", object.httpEtag); return h; }
async function downloadWindowsZip(release, env, method, cacheControl) {
  const asset = release.windows;
  const expectedFile = `GYInput-${asset.version}.zip`;
  if (!asset?.available) return json({ error: "platform_not_verified", platform: "windows" }, 409);
  if (asset.zipFile !== expectedFile) return json(invalidRelease("Windows ZIP filename does not match its release version"), 503);
  const object = await env.RELEASES.get(`releases/${asset.version}/windows/${asset.zipFile}`);
  if (!object) return json({ error: "release_not_found", platform: "windows", artifact: "zip" }, 404);
  return new Response(method === "HEAD" ? null : object.body, { headers: windowsZipHeaders(release, object, cacheControl) });
}
function route(path, release) {
  const version = release.windows?.version;
  if (path === "/latest.zip" || path === "/download/latest.zip" || path === "/download/windows/latest.zip") return ["windows-zip", "download", CACHE_CONTROL_LATEST];
  if (version && (path === `/download/windows/${version}.zip` || path === `/download/windows/${version}/zip`)) return ["windows-zip", "download", CACHE_CONTROL_VERSIONED];
  for (const p of Object.keys(PLATFORM)) {
    const a = release[p];
    const v = a?.version;

    if (path === `/${p}/latest` || (v && path === `/${p}/${v}`)) return [p, "info"];

    if (path === `/download/${p}/latest` || path === `/download/${p}/latest/download`) return [p, "download", CACHE_CONTROL_LATEST];
    if (v && (path === `/download/${p}/${v}` || path === `/download/${p}/${v}/download`)) return [p, "download", CACHE_CONTROL_VERSIONED];

    if (path === `/${p}/latest/sha256` || (v && path === `/${p}/${v}/sha256`) || path === `/download/${p}/latest/sha256` || (v && path === `/download/${p}/${v}/sha256`)) return [p, "sha256"];
  }
  if (path === "/latest.exe" || path === "/download/latest.exe") return ["windows", "download", CACHE_CONTROL_LATEST];
  if (path === "/latest.pkg" || path === "/download/latest.pkg") return ["macos", "download", CACHE_CONTROL_LATEST];
  return null;
}
export default { async fetch(request, env) { if (!["GET", "HEAD"].includes(request.method)) return json({ error: "method_not_allowed" }, 405); const path = new URL(request.url).pathname.replace(/\/+$/, "") || "/"; if (path === "/download/macos-beta.json" || path.startsWith("/download/beta/macos/")) { const betaResponse = await betaMacRoute(path, env, request.method); if (betaResponse) return betaResponse; } let release; try { release = await loadLatest(env); } catch (error) { return json(invalidRelease(error.message), 503); } if (["/", "/health", "/api/releases/latest"].includes(path)) return json({ service: "GY Input Method release service", ...releaseInfo(release, env) }); const r = route(path, release); if (!r) return json({ error: "not_found" }, 404); const [platform, action, downloadCacheControl] = r; if (platform === "windows-zip") return downloadWindowsZip(release, env, request.method, downloadCacheControl); if (action === "info") return json(assetInfo(release[platform], platform)); if (action === "sha256") { const asset = release[platform]; if (!asset?.available) return json({ error: "platform_not_verified", platform }, 409); return new Response(`${asset.sha256.toUpperCase()}  ${asset.file}\n`, { headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store", "x-content-type-options": "nosniff" } }); } return download(release, platform, env, request.method, downloadCacheControl); } };
