interface Env {
  RELEASES: R2Bucket;
}

const files: Record<string, { key: string; name: string; type: string }> = {
  "/latest.exe": {
    key: "releases/0.9.13/GYInputSetup-0.9.13.exe",
    name: "GYInputSetup-0.9.13.exe",
    type: "application/vnd.microsoft.portable-executable",
  },
  "/latest.zip": {
    key: "releases/0.9.13/GYInput-0.9.13.zip",
    name: "GYInput-0.9.13.zip",
    type: "application/zip",
  },
};

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method Not Allowed", { status: 405, headers: { Allow: "GET, HEAD" } });
    }
    const url = new URL(request.url);
    const file = files[url.pathname];
    if (!file) return new Response("Not Found", { status: 404 });

    const object = await env.RELEASES.get(file.key);
    if (!object) return new Response("Release unavailable", { status: 404 });

    const headers = new Headers();
    headers.set("Content-Type", file.type);
    headers.set("Content-Length", String(object.size));
    headers.set("Content-Disposition", `attachment; filename="${file.name}"`);
    // "latest" must never continue serving a previous installer after a release switch.
    headers.set("X-Content-Type-Options", "nosniff");
    object.writeHttpMetadata(headers);
    headers.set("Cache-Control", "no-store");
    headers.set("ETag", object.httpEtag);
    return new Response(request.method === "HEAD" ? null : object.body, { headers });
  },
};
