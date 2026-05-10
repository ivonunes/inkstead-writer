import type { SyndicationProvider } from "../../core/adapters/types.js";
import { prepareImageForSyndication, type MediaLimit } from "../../core/syndication/media.js";
import { textForSyndication } from "../../core/syndication/text.js";

async function mastodonMediaLimit(instance: string): Promise<MediaLimit> {
  const fallback = { maxBytes: 10 * 1024 * 1024, maxDimension: 4096 };
  const response = await fetch(`${instance}/api/v2/instance`).catch(() => undefined);
  if (!response?.ok) return fallback;
  const json = await response.json().catch(() => undefined) as { configuration?: { media_attachments?: { image_size_limit?: number; image_matrix_limit?: number } } } | undefined;
  const media = json?.configuration?.media_attachments;
  const maxBytes = media?.image_size_limit ?? fallback.maxBytes;
  const matrix = media?.image_matrix_limit;
  return { maxBytes, maxDimension: matrix ? Math.floor(Math.sqrt(matrix)) : fallback.maxDimension };
}

function arrayBufferFromBuffer(buffer: Buffer): ArrayBuffer {
  const copy = new Uint8Array(buffer.byteLength);
  copy.set(buffer);
  return copy.buffer;
}

export const mastodonProvider: SyndicationProvider = {
  name: "Mastodon",
  requirements: () => [
    { name: "Mastodon instance URL", type: "secret", required: true, description: "Base URL of your Mastodon instance.", environmentVariable: "MASTODON_INSTANCE_URL", githubSecretName: "MASTODON_INSTANCE_URL" },
    { name: "Mastodon access token", type: "secret", required: true, description: "Access token with write:statuses permission.", environmentVariable: "MASTODON_ACCESS_TOKEN", githubSecretName: "MASTODON_ACCESS_TOKEN" }
  ],
  canSyndicate: () => true,
  publish: async (post, { env }) => {
    const instance = env.MASTODON_INSTANCE_URL?.replace(/\/$/, "");
    const token = env.MASTODON_ACCESS_TOKEN;
    if (!instance || !token) return { status: "failed", error: "Missing Mastodon credentials." };
    const media_ids: string[] = [];
    const limit = await mastodonMediaLimit(instance);
    for (const photoPath of post.sourcePhotos) {
      const prepared = await prepareImageForSyndication(photoPath, limit);
      const form = new FormData();
      form.set("file", new Blob([arrayBufferFromBuffer(prepared.bytes)], { type: prepared.mimeType }), prepared.filename);
      if (post.alt) form.set("description", post.alt);
      const upload = await fetch(`${instance}/api/v2/media`, {
        method: "POST",
        headers: { Authorization: `Bearer ${token}` },
        body: form
      });
      if (!upload.ok) return { status: "failed", error: `Mastodon media upload returned ${upload.status}.` };
      const uploadResult = await upload.json() as { id?: string };
      if (uploadResult.id) media_ids.push(uploadResult.id);
    }
    const response = await fetch(`${instance}/api/v1/statuses`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({ status: textForSyndication(post), media_ids })
    });
    if (!response.ok) return { status: "failed", error: `Mastodon returned ${response.status}.` };
    const json = await response.json() as { id?: string; url?: string };
    return { status: "published", id: json.id, url: json.url, publishedAt: new Date().toISOString() };
  },
  doctor: async ({ env }) => mastodonProvider.requirements().map((requirement) => ({
    status: env[requirement.environmentVariable ?? ""] ? "pass" : "fail",
    label: `${requirement.environmentVariable} is ${env[requirement.environmentVariable ?? ""] ? "set" : "missing"}`
  }))
};
