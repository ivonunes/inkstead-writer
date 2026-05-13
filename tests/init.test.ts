import { promises as fs } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { initSite } from "../src/index.js";
import { useSiteFixture } from "./helpers/site.js";

const fixture = useSiteFixture();

describe("init", () => {
  it("creates the expected generated site structure", async () => {
    const site = await fixture.makeSite();
    await expect(fs.stat(path.join(site, "site.config.ts"))).resolves.toBeTruthy();
    await expect(fs.stat(path.join(site, "content/posts/hello.md"))).resolves.toBeTruthy();
    await expect(fs.stat(path.join(site, "content/pages/about.md"))).resolves.toBeTruthy();
    await expect(fs.stat(path.join(site, ".github/workflows/publish.yml"))).resolves.toBeTruthy();
    const pkg = JSON.parse(await fs.readFile(path.join(site, "package.json"), "utf8"));
    expect(pkg.dependencies).toEqual({ inkstead: "^1.0.0" });
  });

  it("scaffolds selected adapters instead of always using defaults", async () => {
    const site = path.join(fixture.tempRoot, "site");
    await initSite(site, { ci: "none", deploy: "none", syndication: ["flickr"] });
    const config = await fs.readFile(path.join(site, "site.config.ts"), "utf8");
    const envExample = await fs.readFile(path.join(site, ".env.example"), "utf8");
    const post = await fs.readFile(path.join(site, "content/posts/hello.md"), "utf8");
    await expect(fs.stat(path.join(site, ".github/workflows/publish.yml"))).rejects.toThrow();
    expect(config).not.toContain('"deploy"');
    expect(config).toContain('"providers": [\n      "flickr"');
    expect(envExample).toContain("FLICKR_API_KEY=");
    expect(envExample).not.toContain("CLOUDFLARE_API_TOKEN=");
    expect(post).not.toContain("syndicate:");
  });

  it("omits the workflow env block when selected adapters do not need secrets", async () => {
    const site = path.join(fixture.tempRoot, "site");
    await initSite(site, { ci: "github-actions", deploy: "github-pages", syndication: [] });
    const workflow = await fs.readFile(path.join(site, ".github/workflows/publish.yml"), "utf8");
    expect(workflow).toContain("deploy-pages:");
    expect(workflow).toContain("actions/upload-pages-artifact@v4");
    expect(workflow).toContain("actions/deploy-pages@v4");
    expect(workflow).not.toContain("env:");
  });

  it("scaffolds a native GitHub Pages workflow with syndication when GitHub Pages is selected", async () => {
    const site = path.join(fixture.tempRoot, "site");
    await initSite(site, { ci: "none", deploy: "github-pages", syndication: ["mastodon"] });
    const config = await fs.readFile(path.join(site, "site.config.ts"), "utf8");
    const workflow = await fs.readFile(path.join(site, ".github/workflows/publish.yml"), "utf8");
    expect(config).toContain('"provider": "github-pages"');
    expect(config).toContain('"provider": "github-actions"');
    expect(workflow).toContain("deploy-pages:");
    expect(workflow).toContain("syndicate-pages:");
    expect(workflow).toContain("redeploy-pages:");
    expect(workflow).toContain("MASTODON_ACCESS_TOKEN: ${{ secrets.MASTODON_ACCESS_TOKEN }}");
  });

  it("can scaffold GitLab CI instead of GitHub Actions", async () => {
    const site = path.join(fixture.tempRoot, "site");
    await initSite(site, { ci: "gitlab-ci", deploy: "cloudflare-workers", deployProjectName: "my-site", syndication: [] });
    const config = await fs.readFile(path.join(site, "site.config.ts"), "utf8");
    const workflow = await fs.readFile(path.join(site, ".gitlab-ci.yml"), "utf8");
    await expect(fs.stat(path.join(site, ".github/workflows/publish.yml"))).rejects.toThrow();
    expect(config).toContain('"provider": "gitlab-ci"');
    expect(workflow).toContain("image: node:22");
    expect(workflow).toContain("npm run publish");
  });

  it("scaffolds a GitLab Pages pipeline when GitLab Pages is selected", async () => {
    const site = path.join(fixture.tempRoot, "site");
    await initSite(site, { ci: "github-actions", deploy: "gitlab-pages", syndication: ["mastodon"] });
    const config = await fs.readFile(path.join(site, "site.config.ts"), "utf8");
    const workflow = await fs.readFile(path.join(site, ".gitlab-ci.yml"), "utf8");
    await expect(fs.stat(path.join(site, ".github/workflows/publish.yml"))).rejects.toThrow();
    expect(config).toContain('"provider": "gitlab-pages"');
    expect(config).toContain('"provider": "gitlab-ci"');
    expect(workflow).toContain("deploy-pages:");
    expect(workflow).toContain("pages:");
    expect(workflow).toContain("publish: dist");
    expect(workflow).toContain("syndicate:");
    expect(workflow).toContain("redeploy-pages:");
  });

  it("scaffolds Writer repository settings when enabled", async () => {
    const site = path.join(fixture.tempRoot, "site");
    await initSite(site, {
      ci: "github-actions",
      deploy: "github-pages",
      syndication: [],
      writer: {
        enabled: true,
        provider: "github",
        owner: "ivonunes",
        repo: "my-site",
        branch: "main"
      }
    });
    const config = await fs.readFile(path.join(site, "site.config.ts"), "utf8");
    expect(config).toContain('"writer": {');
    expect(config).toContain('"provider": "github"');
    expect(config).toContain('"owner": "ivonunes"');
    expect(config).toContain('"repo": "my-site"');
    expect(config).toContain('"branch": "main"');
    expect(config).not.toContain('"postsPath": "content/posts"');
    expect(config).not.toContain('"mediaPath": "content/media"');
    expect(config).not.toContain('"path": "/writer"');
  });
});

