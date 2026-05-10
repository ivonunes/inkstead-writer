import { createHmac, randomBytes } from "node:crypto";
import { promises as fs } from "node:fs";
import path from "node:path";
import type { SyndicationProvider } from "../../core/adapters/types.js";
import { mimeFromPath } from "../../utils/mime.js";

function encode(value: string): string {
  return encodeURIComponent(value).replace(/[!*()']/g, (char) => `%${char.charCodeAt(0).toString(16).toUpperCase()}`);
}

function sign(method: string, url: string, params: Record<string, string>, apiSecret: string, accessSecret: string): string {
  const base = `${method.toUpperCase()}&${encode(url)}&${encode(Object.entries(params).sort(([a], [b]) => a.localeCompare(b)).map(([key, value]) => `${encode(key)}=${encode(value)}`).join("&"))}`;
  return createHmac("sha1", `${encode(apiSecret)}&${encode(accessSecret)}`).update(base).digest("base64");
}

function photoIdFromResponse(xml: string): string | undefined {
  return xml.match(/<photoid>([^<]+)<\/photoid>/)?.[1];
}

export const flickrProvider: SyndicationProvider = {
  name: "Flickr",
  requirements: () => [
    { name: "Flickr API key", type: "secret", required: true, description: "Flickr API key.", environmentVariable: "FLICKR_API_KEY", githubSecretName: "FLICKR_API_KEY" },
    { name: "Flickr API secret", type: "secret", required: true, description: "Flickr API secret.", environmentVariable: "FLICKR_API_SECRET", githubSecretName: "FLICKR_API_SECRET" },
    { name: "Flickr access token", type: "secret", required: true, description: "OAuth access token.", environmentVariable: "FLICKR_ACCESS_TOKEN", githubSecretName: "FLICKR_ACCESS_TOKEN" },
    { name: "Flickr access secret", type: "secret", required: true, description: "OAuth access token secret.", environmentVariable: "FLICKR_ACCESS_SECRET", githubSecretName: "FLICKR_ACCESS_SECRET" }
  ],
  canSyndicate: (post) => post.kind === "photo-note",
  publish: async (post, { env }) => {
    const [photoPath] = post.sourcePhotos;
    if (!photoPath) return { status: "failed", error: "Flickr syndication requires a photo." };
    const apiKey = env.FLICKR_API_KEY;
    const apiSecret = env.FLICKR_API_SECRET;
    const accessToken = env.FLICKR_ACCESS_TOKEN;
    const accessSecret = env.FLICKR_ACCESS_SECRET;
    if (!apiKey || !apiSecret || !accessToken || !accessSecret) return { status: "failed", error: "Missing Flickr credentials." };
    const uploadUrl = "https://up.flickr.com/services/upload/";
    const oauth = {
      oauth_consumer_key: apiKey,
      oauth_nonce: randomBytes(16).toString("hex"),
      oauth_signature_method: "HMAC-SHA1",
      oauth_timestamp: Math.floor(Date.now() / 1000).toString(),
      oauth_token: accessToken,
      oauth_version: "1.0"
    };
    const params = {
      ...oauth,
      title: post.title ?? (post.body.trim().slice(0, 80) || path.basename(photoPath)),
      description: post.body.trim()
    };
    const signature = sign("POST", uploadUrl, params, apiSecret, accessSecret);
    const bytes = await fs.readFile(photoPath);
    const form = new FormData();
    for (const [key, value] of Object.entries(params)) form.set(key, value);
    form.set("oauth_signature", signature);
    form.set("photo", new Blob([bytes], { type: mimeFromPath(photoPath) }), path.basename(photoPath));
    const response = await fetch(uploadUrl, { method: "POST", body: form });
    const xml = await response.text();
    if (!response.ok || !xml.includes("stat=\"ok\"")) return { status: "failed", error: `Flickr upload failed: ${xml.slice(0, 200)}` };
    const id = photoIdFromResponse(xml);
    return { status: "published", id, url: id ? `https://www.flickr.com/photo.gne?id=${id}` : undefined, publishedAt: new Date().toISOString() };
  },
  doctor: async ({ env }) => flickrProvider.requirements().map((requirement) => ({
    status: env[requirement.environmentVariable ?? ""] ? "pass" : "fail",
    label: `${requirement.environmentVariable} is ${env[requirement.environmentVariable ?? ""] ? "set" : "missing"}`
  }))
};
