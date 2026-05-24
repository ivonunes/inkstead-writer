import { promises as fs } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { loadConfig } from "../src/index.js";
import { publicWriterConfig, resolveWriterConfig } from "../src/core/writer/config.js";
import { useSiteFixture } from "./helpers/site.js";

const fixture = useSiteFixture();

describe("writer config", () => {
  it("generates public Writer config without secrets", () => {
    expect(publicWriterConfig({
      site: { title: "My Website", url: "https://example.com", author: "Your Name" },
      content: { posts: "content/posts", pages: "content/pages", media: "content/media" },
      syndication: { providers: ["mastodon", "bluesky"] },
      writer: {
        enabled: true,
        path: "/writer",
        provider: "github",
        owner: "me",
        repo: "site",
        branch: "main",
        categories: ["Photography", "Essays"]
      }
    })).toEqual({
      provider: "github",
      owner: "me",
      repo: "site",
      branch: "main",
      postsPath: "content/posts",
      mediaPath: "content/media",
      syndicationProviders: ["mastodon", "bluesky"],
      categories: ["Photography", "Essays"]
    });
  });

  it("generates public Forgejo Writer config with the instance URL", () => {
    expect(publicWriterConfig({
      site: { title: "My Website", url: "https://example.com", author: "Your Name" },
      content: { posts: "content/posts", pages: "content/pages", media: "content/media" },
      writer: {
        enabled: true,
        provider: "forgejo",
        instanceUrl: "https://codeberg.org",
        owner: "me",
        repo: "site",
        branch: "main"
      }
    })).toMatchObject({
      provider: "forgejo",
      instanceUrl: "https://codeberg.org",
      owner: "me",
      repo: "site",
      branch: "main"
    });
  });

  it("defaults the Writer path to /writer when omitted", () => {
    expect(resolveWriterConfig({
      site: { title: "My Website", url: "https://example.com", author: "Your Name" },
      content: { posts: "content/posts", pages: "content/pages", media: "content/media" },
      writer: {
        enabled: true,
        provider: "github",
        owner: "me",
        repo: "site",
        branch: "main"
      }
    })?.path).toBe("/writer");
  });

  it("rejects invalid Writer category configuration", async () => {
    const site = await fixture.makeSite();
    await fs.writeFile(path.join(site, "site.config.ts"), `import { defineConfig } from "inkstead";
export default defineConfig({
  site: { title: "My Website", url: "https://example.com", author: "Your Name" },
  content: { posts: "content/posts", pages: "content/pages", media: "content/media" },
  writer: {
    enabled: true,
    provider: "github",
    owner: "me",
    repo: "site",
    branch: "main",
    categories: ["Photography", ""]
  }
});`);
    await expect(loadConfig(site)).rejects.toThrow();
  });

  it("rejects duplicate Writer categories", async () => {
    const site = await fixture.makeSite();
    await fs.writeFile(path.join(site, "site.config.ts"), `import { defineConfig } from "inkstead";
export default defineConfig({
  site: { title: "My Website", url: "https://example.com", author: "Your Name" },
  content: { posts: "content/posts", pages: "content/pages", media: "content/media" },
  writer: {
    enabled: true,
    provider: "github",
    owner: "me",
    repo: "site",
    branch: "main",
    categories: ["Photography", "Photography"]
  }
});`);
    await expect(loadConfig(site)).rejects.toThrow();
  });

  it("rejects enabled remote Writer config without repository coordinates", async () => {
    const site = await fixture.makeSite();
    await fs.writeFile(path.join(site, "site.config.ts"), `import { defineConfig } from "inkstead";
export default defineConfig({
  site: { title: "My Website", url: "https://example.com", author: "Your Name" },
  content: { posts: "content/posts", pages: "content/pages", media: "content/media" },
  writer: {
    enabled: true,
    provider: "github"
  }
});`);
    await expect(loadConfig(site)).rejects.toThrow();
  });

  it("allows local Writer config without remote repository coordinates", async () => {
    const site = await fixture.makeSite();
    await fs.writeFile(path.join(site, "site.config.ts"), `import { defineConfig } from "inkstead";
export default defineConfig({
  site: { title: "My Website", url: "https://example.com", author: "Your Name" },
  content: { posts: "content/posts", pages: "content/pages", media: "content/media" },
  writer: {
    enabled: true,
    provider: "local"
  }
});`);
    expect((await loadConfig(site)).writer?.provider).toBe("local");
  });

  it("rejects Forgejo Writer config without an instance URL", async () => {
    const site = await fixture.makeSite();
    await fs.writeFile(path.join(site, "site.config.ts"), `import { defineConfig } from "inkstead";
export default defineConfig({
  site: { title: "My Website", url: "https://example.com", author: "Your Name" },
  content: { posts: "content/posts", pages: "content/pages", media: "content/media" },
  writer: {
    enabled: true,
    provider: "forgejo",
    owner: "me",
    repo: "site",
    branch: "main"
  }
});`);
    await expect(loadConfig(site)).rejects.toThrow("Forgejo Writer provider requires instanceUrl.");
  });
});
