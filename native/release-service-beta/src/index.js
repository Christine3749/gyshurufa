const RELEASE = {
  version: "0.4.2",
  channel: "Windows beta",
  platform: "windows",
  architecture: "x64",
  filename: "GYInputSetup-0.4.2.exe",
  objectKey: "windows/0.4.2/GYInputSetup-0.4.2.exe",
  size: 10016122,
  sha256: "A63831CC45D16ED611AE08C77CA3F8200DBFCD7CBE2B4E330B052456AA3D42D1",
  codeSigning: "not signed"
};

const responseJson = (body, status = 200) => new Response(JSON.stringify(body, null, 2), {
  status,
  headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", "x-content-type-options": "nosniff" }
});

export default {
  async fetch(request, env) {
    if (request.method !== "GET" && request.method !== "HEAD") return responseJson({ error: "method_not_allowed" }, 405);
    const path = new URL(request.url).pathname.replace(/\/+$/, "") || "/";
    if (path === "/" || path === "/health") return responseJson({ service: "GY Input Method beta release service", status: env.RELEASE_STATUS });
    if (path === "/windows/latest" || path === "/windows/0.4.2") return responseJson({
      ...RELEASE,
      releaseStatus: "beta",
      downloadUrl: "/windows/0.4.2/download",
      warning: "This Windows beta installer is not code signed. Install only if you choose to test it; verify SHA-256 before installation."
    });
    if (path === "/windows/0.4.2/sha256") return new Response(`${RELEASE.sha256}  ${RELEASE.filename}\n`, { headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" } });
    if (path === "/windows/0.4.2/download") {
      const object = await env.RELEASES.get(RELEASE.objectKey);
      if (!object) return responseJson({ error: "release_not_found" }, 404);
      return new Response(object.body, {
        headers: {
          "content-type": "application/vnd.microsoft.portable-executable",
          "content-disposition": `attachment; filename="${RELEASE.filename}"`,
          "content-length": String(RELEASE.size),
          "cache-control": "public, max-age=31536000, immutable",
          "x-content-type-options": "nosniff"
        }
      });
    }
    return responseJson({ error: "not_found" }, 404);
  }
};
