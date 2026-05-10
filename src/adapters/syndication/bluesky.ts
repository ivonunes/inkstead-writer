import { BskyAgent } from "@atproto/api";
import type { SyndicationProvider } from "../../core/adapters/types.js";
import { prepareImageForSyndication } from "../../core/syndication/media.js";
import { textForSyndication } from "../../core/syndication/text.js";

export const blueskyProvider: SyndicationProvider = {
  name: "Bluesky",
  requirements: () => [
    { name: "Bluesky identifier", type: "secret", required: true, description: "Handle or DID for your account.", environmentVariable: "BLUESKY_IDENTIFIER", githubSecretName: "BLUESKY_IDENTIFIER" },
    { name: "Bluesky app password", type: "secret", required: true, description: "App password for publishing.", environmentVariable: "BLUESKY_APP_PASSWORD", githubSecretName: "BLUESKY_APP_PASSWORD" }
  ],
  canSyndicate: () => true,
  publish: async (post, { env }) => {
    if (!env.BLUESKY_IDENTIFIER || !env.BLUESKY_APP_PASSWORD) return { status: "failed", error: "Missing Bluesky credentials." };
    const agent = new BskyAgent({ service: "https://bsky.social" });
    await agent.login({ identifier: env.BLUESKY_IDENTIFIER, password: env.BLUESKY_APP_PASSWORD });
    const images = [];
    for (const photoPath of post.sourcePhotos.slice(0, 4)) {
      const media = await prepareImageForSyndication(photoPath, { maxBytes: 1_000_000, maxDimension: 2000 });
      const uploaded = await agent.uploadBlob(media.bytes, { encoding: media.mimeType });
      images.push({ alt: post.alt ?? "", image: uploaded.data.blob });
    }
    const result = await agent.post({
      text: textForSyndication(post).slice(0, 300),
      embed: images.length ? { $type: "app.bsky.embed.images", images } : undefined
    });
    return { status: "published", uri: result.uri, cid: result.cid, url: `https://bsky.app/profile/${env.BLUESKY_IDENTIFIER}/post/${result.uri.split("/").pop()}`, publishedAt: new Date().toISOString() };
  },
  doctor: async ({ env }) => blueskyProvider.requirements().map((requirement) => ({
    status: env[requirement.environmentVariable ?? ""] ? "pass" : "fail",
    label: `${requirement.environmentVariable} is ${env[requirement.environmentVariable ?? ""] ? "set" : "missing"}`
  }))
};
