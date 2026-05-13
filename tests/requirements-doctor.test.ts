import { promises as fs } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { loadConfig, renderRequirements, runDoctor } from "../src/index.js";
import { cloudflareWorkersProvider } from "../src/adapters/deploy/cloudflare-workers.js";
import { useSiteFixture } from "./helpers/site.js";

const fixture = useSiteFixture();

describe("requirements and doctor", () => {
  it("generates a starter Wrangler config for Cloudflare Workers", async () => {
    const files = await cloudflareWorkersProvider.prepare?.({
      root: "/site",
      distDir: "/site/build",
      projectName: "my-worker",
      env: {}
    });
    const wrangler = files?.find((file) => file.path === "wrangler.toml");
    expect(wrangler?.content).toContain('name = "my-worker"');
    expect(wrangler?.content).toContain('directory = "./build"');
  });

  it("reports adapter-driven requirements and setup checks", async () => {
    const site = await fixture.makeSite();
    await fs.writeFile(path.join(site, "site.config.ts"), `import { defineConfig } from "inkstead";
export default defineConfig({
  site: { title: "My Website", url: "https://example.com", author: "Your Name" },
  content: { posts: "content/posts", pages: "content/pages", media: "content/media" },
  ci: { provider: "github-actions" },
  deploy: { provider: "cloudflare-workers", projectName: "my-website" },
  syndication: { providers: ["mastodon"] }
});`);
    const config = await loadConfig(site);
    const requirements = renderRequirements(config);
    expect(requirements).toContain("CLOUDFLARE_API_TOKEN");
    expect(requirements).toContain("MASTODON_ACCESS_TOKEN");
    const doctor = await runDoctor(site, config);
    expect(doctor.output).toContain("site.config.ts found");
    expect(doctor.issues).toBeGreaterThan(0);
  });

  it("supports GitHub Pages as a deployment provider without Cloudflare secrets", async () => {
    const site = await fixture.makeSite();
    await fs.writeFile(path.join(site, "site.config.ts"), `import { defineConfig } from "inkstead";
export default defineConfig({
  site: { title: "My Website", url: "https://example.com", author: "Your Name" },
  content: { posts: "content/posts", pages: "content/pages", media: "content/media" },
  ci: { provider: "github-actions" },
  deploy: { provider: "github-pages" }
});`);
    const config = await loadConfig(site);
    expect(config.deploy?.provider).toBe("github-pages");
    expect(renderRequirements(config)).not.toContain("CLOUDFLARE_API_TOKEN");
  });

  it("rejects Pages deployments paired with incompatible CI providers", async () => {
    const site = await fixture.makeSite();
    await fs.writeFile(path.join(site, "site.config.ts"), `import { defineConfig } from "inkstead";
export default defineConfig({
  site: { title: "My Website", url: "https://example.com", author: "Your Name" },
  content: { posts: "content/posts", pages: "content/pages", media: "content/media" },
  ci: { provider: "gitlab-ci" },
  deploy: { provider: "github-pages" }
});`);
    await expect(loadConfig(site)).rejects.toThrow("GitHub Pages deployment requires GitHub Actions CI");

    await fs.writeFile(path.join(site, "site.config.ts"), `import { defineConfig } from "inkstead";
export default defineConfig({
  site: { title: "My Website", url: "https://example.com", author: "Your Name" },
  content: { posts: "content/posts", pages: "content/pages", media: "content/media" },
  ci: { provider: "github-actions" },
  deploy: { provider: "gitlab-pages" }
});`);
    await expect(loadConfig(site)).rejects.toThrow("GitLab Pages deployment requires GitLab CI");
  });
});

