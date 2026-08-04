interface R2ObjectLike {
  size: number;
  httpEtag: string;
  body: ReadableStream;
  writeHttpMetadata(headers: Headers): void;
  text(): Promise<string>;
}
interface R2Bucket {
  get(key: string): Promise<R2ObjectLike | null>;
}
interface Env {
  RELEASES: R2Bucket;
}

type Artifact = { key: string; name: string; type: string; sha256?: string };
type ReleaseManifest = { version: string; channel?: string; artifacts: Record<string, Artifact> };

async function readManifest(env: Env, key: string): Promise<ReleaseManifest | null> {
  const object = await env.RELEASES.get(key);
  if (!object) return null;
  try {
    const manifest = JSON.parse(await object.text()) as ReleaseManifest;
    if (!manifest.version || !manifest.artifacts) return null;
    return manifest;
  } catch {
    return null;
  }
}

function artifactResponse(request: Request, file: Artifact, object: R2ObjectLike): Response {
  const headers = new Headers();
  headers.set("Content-Type", file.type);
  headers.set("Content-Length", String(object.size));
  headers.set("Content-Disposition", `attachment; filename="${file.name}"`);
  headers.set("X-Content-Type-Options", "nosniff");
  object.writeHttpMetadata(headers);
  headers.set("Cache-Control", "no-store");
  headers.set("ETag", object.httpEtag);
  return new Response(request.method === "HEAD" ? null : object.body, { headers });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method Not Allowed", { status: 405, headers: { Allow: "GET, HEAD" } });
    }
    const url = new URL(request.url);
    const candidate = url.pathname.match(/^\/download\/candidate\/(\d+\.\d+\.\d+)\/(.+)$/);
    if (candidate) {
      const [, version] = candidate;
      const manifest = await readManifest(env, `releases/${version}/release.json`);
      if (!manifest || manifest.version !== version || manifest.channel !== "candidate") {
        return new Response("Candidate release unavailable", { status: 404 });
      }
      const file = manifest.artifacts[url.pathname];
      if (!file) return new Response("Not Found", { status: 404 });
      const object = await env.RELEASES.get(file.key);
      if (!object) return new Response("Release unavailable", { status: 404 });
      return artifactResponse(request, file, object);
    }

    const manifest = await readManifest(env, "releases/latest.json");
    if (!manifest) return new Response("Release manifest unavailable", { status: 503 });
    const file = manifest.artifacts[url.pathname];
    if (!file) return new Response("Not Found", { status: 404 });

    const object = await env.RELEASES.get(file.key);
    if (!object) return new Response("Release unavailable", { status: 404 });
    return artifactResponse(request, file, object);
  },
};
