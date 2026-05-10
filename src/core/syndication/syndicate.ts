import { promises as fs } from "node:fs";
import dotenv from "dotenv";
import path from "node:path";
import type { InksteadConfig } from "../config/types.js";
import { syndicationProviders } from "../adapters/registry.js";
import type { SyndicationResult } from "../adapters/types.js";
import { loadPosts } from "../content/load-content.js";
import { updateSyndicationFrontmatter } from "./frontmatter.js";

function failedResult(error: unknown): SyndicationResult {
  return {
    status: "failed",
    error: error instanceof Error ? error.message : "Syndication failed."
  };
}

export async function syndicateSite(root: string, config: InksteadConfig): Promise<{ changed: boolean; published: number; failed: number }> {
  dotenv.config({ path: path.join(root, ".env") });
  const posts = await loadPosts(root, config);
  let changed = false;
  let published = 0;
  let failed = 0;
  for (const post of posts) {
    for (const providerName of post.syndicate) {
      if (post.syndication[providerName]?.status === "published") continue;
      const provider = syndicationProviders[providerName];
      if (!provider?.canSyndicate(post)) continue;
      let result: SyndicationResult;
      try {
        result = await provider.publish(post, { root, env: process.env });
      } catch (error) {
        result = failedResult(error);
      }
      const raw = await fs.readFile(post.path, "utf8");
      await fs.writeFile(post.path, updateSyndicationFrontmatter(raw, providerName, { ...result }));
      changed = true;
      if (result.status === "published") published += 1;
      if (result.status === "failed") failed += 1;
    }
  }
  return { changed, published, failed };
}
