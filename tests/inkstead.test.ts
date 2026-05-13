import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import { Readable } from "node:stream";
import { beforeEach, describe, expect, it } from "vitest";
import { buildSite, createPost, ejectTheme, initSite, loadConfig, renderRequirements, runDoctor, updateSyndicationFrontmatter } from "../src/index.js";
import { loadPosts } from "../src/core/content/load-content.js";
import { textForSyndication } from "../src/core/syndication/text.js";
import { cloudflareWorkersProvider } from "../src/adapters/deploy/cloudflare-workers.js";
import sharp from "sharp";
import { prepareImageForSyndication } from "../src/core/syndication/media.js";
import { parsePostMarkdown, serializePostMarkdown } from "../src/writer/app/core/frontmatter.js";
import { buildPostMarkdown, formatPostDate, postDateSortValue, postExcerpt, postListLabel, postStatusLabel, slugForNewPost, slugifyTitle, summarizePost } from "../src/writer/app/core/posts.js";
import { extractMarkdownImageReferences } from "../src/writer/app/core/markdown.js";
import { markdownMediaReference, mediaAssetPath, referencedMediaPaths, uniqueAssetFilename } from "../src/writer/app/core/assets.js";
import { copyWriterApp } from "../src/core/writer/build.js";
import { publicWriterConfig, resolveWriterConfig } from "../src/core/writer/config.js";
import { GitHubRepositoryAdapter } from "../src/writer/app/adapters/github.js";
import { GitLabRepositoryAdapter } from "../src/writer/app/adapters/gitlab.js";
import { contentType, localWriterConfig, staticFilePath } from "../src/core/dev.js";
import { handleWriterLocalApi } from "../src/core/writer/local-api.js";
import { syndicationProviders } from "../src/core/adapters/registry.js";
import { syndicateSite } from "../src/core/syndication/syndicate.js";
import { previewTitle } from "../src/writer/app/routes/Preview.js";

let tempRoot: string;

async function makeSite(): Promise<string> {
  tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), "inkstead-test-"));
  const cwd = process.cwd();
  process.chdir(tempRoot);
  try {
    await initSite("site");
  } finally {
    process.chdir(cwd);
  }
  return path.join(tempRoot, "site");
}

beforeEach(async () => {
  tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), "inkstead-test-"));
});

describe("init", () => {
  it("creates the expected generated site structure", async () => {
    const site = await makeSite();
    await expect(fs.stat(path.join(site, "site.config.ts"))).resolves.toBeTruthy();
    await expect(fs.stat(path.join(site, "content/posts/hello.md"))).resolves.toBeTruthy();
    await expect(fs.stat(path.join(site, "content/pages/about.md"))).resolves.toBeTruthy();
    await expect(fs.stat(path.join(site, ".github/workflows/publish.yml"))).resolves.toBeTruthy();
    const pkg = JSON.parse(await fs.readFile(path.join(site, "package.json"), "utf8"));
    expect(pkg.dependencies).toEqual({ inkstead: "^1.0.0" });
  });

  it("scaffolds selected adapters instead of always using defaults", async () => {
    const site = path.join(tempRoot, "site");
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
    const site = path.join(tempRoot, "site");
    await initSite(site, { ci: "github-actions", deploy: "github-pages", syndication: [] });
    const workflow = await fs.readFile(path.join(site, ".github/workflows/publish.yml"), "utf8");
    expect(workflow).toContain("deploy-pages:");
    expect(workflow).toContain("actions/upload-pages-artifact@v4");
    expect(workflow).toContain("actions/deploy-pages@v4");
    expect(workflow).not.toContain("env:");
  });

  it("scaffolds a native GitHub Pages workflow with syndication when GitHub Pages is selected", async () => {
    const site = path.join(tempRoot, "site");
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
    const site = path.join(tempRoot, "site");
    await initSite(site, { ci: "gitlab-ci", deploy: "cloudflare-workers", deployProjectName: "my-site", syndication: [] });
    const config = await fs.readFile(path.join(site, "site.config.ts"), "utf8");
    const workflow = await fs.readFile(path.join(site, ".gitlab-ci.yml"), "utf8");
    await expect(fs.stat(path.join(site, ".github/workflows/publish.yml"))).rejects.toThrow();
    expect(config).toContain('"provider": "gitlab-ci"');
    expect(workflow).toContain("image: node:22");
    expect(workflow).toContain("npm run publish");
  });

  it("scaffolds a GitLab Pages pipeline when GitLab Pages is selected", async () => {
    const site = path.join(tempRoot, "site");
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
    const site = path.join(tempRoot, "site");
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

describe("content and build", () => {
  it("can copy default templates into a site theme without overwriting existing files", async () => {
    const site = await makeSite();
    await fs.mkdir(path.join(site, "theme"), { recursive: true });
    await fs.writeFile(path.join(site, "theme/home.liquid"), "Custom home");

    const result = await ejectTheme(site);
    expect(result.copied).toContain("theme/layout.liquid");
    expect(result.copied).toContain("theme/post.liquid");
    expect(result.skipped).toContain("theme/home.liquid");
    expect(await fs.readFile(path.join(site, "theme/home.liquid"), "utf8")).toBe("Custom home");

    const forced = await ejectTheme(site, { force: true });
    expect(forced.copied).toContain("theme/home.liquid");
    expect(await fs.readFile(path.join(site, "theme/home.liquid"), "utf8")).toContain("post-list");
  });

  it("loads config, infers post kinds, and builds static output", async () => {
    const site = await makeSite();
    await fs.mkdir(path.join(site, "content/media/2026"), { recursive: true });
    await fs.writeFile(path.join(site, "content/media/2026/coffee.jpg"), "fake");
    await fs.writeFile(path.join(site, "content/posts/2026-05-10-photo.md"), "---\ndate: 2026-05-10T18:30:00+01:00\nlastmod: 2026-05-11T18:30:00+01:00\nsyndication:\n  - https://bsky.app/example\n---\n\nMorning coffee.  \n![](/uploads/coffee.jpg)\n");
    const config = await loadConfig(site);
    const posts = await loadPosts(site, config);
    expect(posts.map((post) => post.kind).sort()).toEqual(["article", "note", "photo-note"]);
    expect(posts[0].canonicalUrl).toContain("/2026/05/10/");
    expect(posts[0].firstImage).toBe("/uploads/coffee.jpg");
    expect(posts[0].html).toContain('class="u-photo"');
    expect(posts[0].syndicationUrls).toContain("https://bsky.app/example");
    expect(posts[0].lastmod?.toISOString()).toBe("2026-05-11T17:30:00.000Z");
    await buildSite(site, config);
    await expect(fs.stat(path.join(site, "dist/index.html"))).resolves.toBeTruthy();
    const home = await fs.readFile(path.join(site, "dist/index.html"), "utf8");
    expect(home).toContain("Thinking about notes…");
    expect(home).toContain('<a class="post-meta u-url" href="/2026/05/10/hello/">');
    expect(home).not.toContain('class="post-title u-url p-name" href="/2026/05/10/hello/">Note</a>');
    expect(home).toContain(`&copy; ${new Date().getFullYear()} Your Name`);
    expect(home).toContain('<link rel="alternate" type="application/rss+xml" title="My Website RSS" href="/feed.xml">');
    expect(home).toContain('<link rel="alternate" type="application/feed+json" title="My Website JSON Feed" href="/feed.json">');
    expect(home).toContain('<a href="/feed.xml">RSS feed</a>');
    expect(home).toContain('Powered by <a href="https://inkstead.dev" target="_blank" rel="noopener noreferrer">Inkstead</a>');
    await expect(fs.stat(path.join(site, "dist/feed.xml"))).resolves.toBeTruthy();
    await expect(fs.stat(path.join(site, "dist/feed.json"))).resolves.toBeTruthy();
    await expect(fs.stat(path.join(site, "dist/sitemap.xml"))).resolves.toBeTruthy();
  });

  it("uses inferred body images as syndication photos", async () => {
    const site = await makeSite();
    await fs.mkdir(path.join(site, "content/media"), { recursive: true });
    await fs.writeFile(path.join(site, "content/media/sample.jpg"), "fake");
    await fs.writeFile(path.join(site, "content/posts/2026-05-12-photo-note.md"), "---\ndate: 2026-05-12T18:30:00+01:00\nsyndicate:\n  - mastodon\n  - bluesky\n---\n\nThinking about notes with photos...\n\n![](/media/sample.jpg)\n");
    const config = await loadConfig(site);
    const post = (await loadPosts(site, config)).find((item) => item.slug === "2026-05-12-photo-note");
    expect(post?.kind).toBe("photo-note");
    expect(post?.firstImage).toBe("/media/sample.jpg");
    expect(post?.photos).toEqual([]);
    expect(post?.sourcePhotos).toEqual([path.join(site, "content/media/sample.jpg")]);
    expect(post ? textForSyndication(post) : "").toBe("Thinking about notes with photos...");
  });

  it("renders markdown notes as social-friendly syndication text", async () => {
    const site = await makeSite();
    await fs.writeFile(path.join(site, "content/posts/2026-05-13-markdown-note.md"), "---\ndate: 2026-05-13T18:30:00+01:00\nsyndicate:\n  - mastodon\n---\n\nThinking about **bold** and _italic_ notes with a [link](https://example.com/post).\n\n`code` is okay.\n\n![](/media/sample.jpg)\n");
    const config = await loadConfig(site);
    const post = (await loadPosts(site, config)).find((item) => item.slug === "2026-05-13-markdown-note");
    expect(post ? textForSyndication(post) : "").toBe("Thinking about bold and italic notes with a link (https://example.com/post).\n\ncode is okay.");
  });

  it("creates a new article with title, date, and enabled text syndication", async () => {
    const site = await makeSite();
    await fs.writeFile(path.join(site, "site.config.ts"), `import { defineConfig } from "inkstead";
export default defineConfig({
  site: { title: "My Website", url: "https://example.com", author: "Your Name" },
  content: { posts: "content/posts", pages: "content/pages", media: "content/media" },
  syndication: { providers: ["mastodon", "bluesky", "flickr"] }
});`);
    const result = await createPost(site, await loadConfig(site), {
      kind: "article",
      title: "A New Local Article",
      date: new Date(2026, 4, 10, 12, 30)
    });
    const post = await fs.readFile(result.path, "utf8");
    expect(result.relativePath).toBe("content/posts/2026-05-10-a-new-local-article.md");
    expect(post).toContain('title: "A New Local Article"');
    expect(post).toContain("date: 2026-05-10T12:30:00");
    expect(post).toContain("syndicate:\n  - mastodon\n  - bluesky");
    expect(post).not.toContain("flickr");
  });

  it("creates a new note from text and avoids overwriting an existing slug", async () => {
    const site = await makeSite();
    const config = await loadConfig(site);
    const date = new Date(2026, 4, 10, 12, 30);
    const first = await createPost(site, config, { kind: "note", text: "Small local note for today.", date });
    const second = await createPost(site, config, { kind: "note", text: "Small local note for today.", date });
    const post = await fs.readFile(first.path, "utf8");
    expect(first.relativePath).toBe("content/posts/2026-05-10-small-local-note-for-today.md");
    expect(second.relativePath).toBe("content/posts/2026-05-10-small-local-note-for-today-2.md");
    expect(post).toContain("date: 2026-05-10T12:30:00");
    expect(post).toContain("\n\nSmall local note for today.\n");
    expect(post).not.toContain("title:");
  });

  it("uses the Writer slug rules for CLI note filenames", async () => {
    const site = await makeSite();
    const config = await loadConfig(site);
    const date = new Date(2026, 4, 10, 12, 30);
    const note = await createPost(site, config, { kind: "note", text: "📍 Tokyo, Japan\n\nLess **duct tape**, more <em>website</em>.", date });
    const emojiOnly = await createPost(site, config, { kind: "note", text: "✨📷", date });
    expect(note.relativePath).toBe("content/posts/2026-05-10-tokyo-japan-less-duct-tape-more-website.md");
    expect(emojiOnly.relativePath).toBe("content/posts/2026-05-10-untitled-1230.md");
  });

  it("supports output paths, asset passthrough, raw HTML, hard breaks, and pagination", async () => {
    const site = await makeSite();
    await fs.mkdir(path.join(site, "public/assets"), { recursive: true });
    await fs.writeFile(path.join(site, "public/assets/theme.css"), "body{}");
    for (let index = 0; index < 3; index += 1) {
      await fs.writeFile(path.join(site, `content/posts/2026-05-1${index}-extra-${index}.md`), `---\ndate: 2026-05-1${index}T18:30:00+01:00\n---\n\n<p>Raw ${index}</p>\n\nLine one  \nLine two\n`);
    }
    await fs.writeFile(path.join(site, "site.config.ts"), `import { defineConfig } from "inkstead";
export default defineConfig({
  site: { title: "My Website", url: "https://example.com", author: "Your Name", description: "Desc", social: [{ name: "Me", url: "https://bsky.app/profile/example.com" }] },
  content: { posts: "content/posts", pages: "content/pages", media: "content/media" },
  build: { output: "build" },
  markdown: { html: true, breaks: true },
  assets: { passthrough: [{ from: "public", to: "." }] },
  pagination: { postsPerPage: 2 },
  feeds: { limit: 2 }
});`);
    const config = await loadConfig(site);
    await buildSite(site, config);
    const html = await fs.readFile(path.join(site, "build/index.html"), "utf8");
    const page2 = await fs.readFile(path.join(site, "build/page/2/index.html"), "utf8");
    const feed = await fs.readFile(path.join(site, "build/feed.json"), "utf8");
    await expect(fs.stat(path.join(site, "build/assets/theme.css"))).resolves.toBeTruthy();
    expect(html).toContain("h-entry");
    expect(html).toContain('rel="me"');
    expect(page2).toContain("h-entry");
    expect(feed.match(/content_html/g)?.length).toBe(2);
    const postHtml = await fs.readFile(path.join(site, "build/2026/05/12/extra-2/index.html"), "utf8");
    expect(postHtml).toContain("<p>Raw 2</p>");
    expect(postHtml).toContain("<br>");
    expect(postHtml).toContain('<meta name="description" content="Raw 2 Line one Line two">');
    expect(postHtml).not.toContain('<meta name="description" content="Desc">');
    const aboutHtml = await fs.readFile(path.join(site, "build/about/index.html"), "utf8");
    expect(aboutHtml).toContain('<meta name="description" content="This is my website.">');
    expect(aboutHtml).not.toContain('<meta name="description" content="Desc">');
  });

  it("copies the Writer app and public config when enabled", async () => {
    const site = await makeSite();
    const writerDist = path.join(tempRoot, "writer-dist");
    const dist = path.join(site, "dist");
    await fs.mkdir(path.join(writerDist, "assets"), { recursive: true });
    await fs.writeFile(path.join(writerDist, "index.html"), "<div id=\"root\"></div>");
    await fs.writeFile(path.join(writerDist, "assets/app.js"), "console.log('writer')");
    const config = await loadConfig(site);
    config.writer = {
      enabled: true,
      path: "/writer",
      provider: "github",
      owner: "example",
      repo: "site",
      branch: "main"
    };

    await copyWriterApp(dist, config, { writerDist });

    await expect(fs.stat(path.join(dist, "writer/index.html"))).resolves.toBeTruthy();
    await expect(fs.stat(path.join(dist, "writer/assets/app.js"))).resolves.toBeTruthy();
    const publicConfig = JSON.parse(await fs.readFile(path.join(dist, "writer/inkstead-writer.config.json"), "utf8"));
    expect(publicConfig).toEqual({
      provider: "github",
      owner: "example",
      repo: "site",
      branch: "main",
      postsPath: "content/posts",
      mediaPath: "content/media",
      syndicationProviders: [],
      categories: []
    });
    expect(JSON.stringify(publicConfig)).not.toContain("token");
  });

  it("does not copy Writer output when Writer is disabled", async () => {
    const site = await makeSite();
    const config = await loadConfig(site);
    await copyWriterApp(path.join(site, "dist"), config, { writerDist: path.join(tempRoot, "missing") });
    await expect(fs.stat(path.join(site, "dist/writer"))).rejects.toThrow();
  });

  it("can hide the default powered-by footer link", async () => {
    const site = await makeSite();
    await fs.writeFile(path.join(site, "site.config.ts"), `import { defineConfig } from "inkstead";
export default defineConfig({
  site: { title: "My Website", url: "https://example.com", author: "Your Name" },
  content: { posts: "content/posts", pages: "content/pages", media: "content/media" },
  theme: { showPoweredBy: false }
});`);
    await buildSite(site, await loadConfig(site));
    const home = await fs.readFile(path.join(site, "dist/index.html"), "utf8");
    expect(home).not.toContain("Powered by");
  });

  it("optimizes content photos during site builds by default", async () => {
    const site = await makeSite();
    await fs.mkdir(path.join(site, "content/media"), { recursive: true });
    await fs.writeFile(path.join(site, "content/media/large.jpg"), await sharp({
      create: {
        width: 1600,
        height: 1200,
        channels: 3,
        background: "#5fc9b5"
      }
    }).jpeg().withMetadata({ exif: { IFD0: { Copyright: "Keep private" } } }).toBuffer());
    await fs.writeFile(path.join(site, "site.config.ts"), `import { defineConfig } from "inkstead";
export default defineConfig({
  site: { title: "My Website", url: "https://example.com", author: "Your Name" },
  content: { posts: "content/posts", pages: "content/pages", media: "content/media" },
  photos: { maxWidth: 500, maxHeight: 500, quality: 76 }
});`);

    await buildSite(site, await loadConfig(site));
    const metadata = await sharp(path.join(site, "dist/media/large.jpg")).metadata();
    expect(metadata.width).toBe(500);
    expect(metadata.height).toBe(375);
    expect(metadata.exif).toBeUndefined();
  });

  it("can disable built image optimization", async () => {
    const site = await makeSite();
    await fs.mkdir(path.join(site, "content/media"), { recursive: true });
    await fs.writeFile(path.join(site, "content/media/large.jpg"), await sharp({
      create: {
        width: 1600,
        height: 1200,
        channels: 3,
        background: "#f7b733"
      }
    }).jpeg().toBuffer());
    await fs.writeFile(path.join(site, "site.config.ts"), `import { defineConfig } from "inkstead";
export default defineConfig({
  site: { title: "My Website", url: "https://example.com", author: "Your Name" },
  content: { posts: "content/posts", pages: "content/pages", media: "content/media" },
  photos: { optimize: false, maxWidth: 500, maxHeight: 500 }
});`);

    await buildSite(site, await loadConfig(site));
    const metadata = await sharp(path.join(site, "dist/media/large.jpg")).metadata();
    expect(metadata.width).toBe(1600);
    expect(metadata.height).toBe(1200);
  });

  it("leaves passthrough images unchanged", async () => {
    const site = await makeSite();
    await fs.mkdir(path.join(site, "public/assets"), { recursive: true });
    await fs.writeFile(path.join(site, "public/assets/large.jpg"), await sharp({
      create: {
        width: 1600,
        height: 1200,
        channels: 3,
        background: "#1b2a49"
      }
    }).jpeg().toBuffer());
    await fs.writeFile(path.join(site, "site.config.ts"), `import { defineConfig } from "inkstead";
export default defineConfig({
  site: { title: "My Website", url: "https://example.com", author: "Your Name" },
  content: { posts: "content/posts", pages: "content/pages", media: "content/media" },
  assets: {
    passthrough: [{ from: "public", to: "." }]
  },
  photos: { maxWidth: 500, maxHeight: 500 }
});`);

    await buildSite(site, await loadConfig(site));
    const metadata = await sharp(path.join(site, "dist/assets/large.jpg")).metadata();
    expect(metadata.width).toBe(1600);
    expect(metadata.height).toBe(1200);
  });

  it("runs beforeBuild hooks before asset passthrough", async () => {
    const site = await makeSite();
    await fs.writeFile(path.join(site, "site.config.ts"), `import { defineConfig } from "inkstead";
export default defineConfig({
  site: { title: "My Website", url: "https://example.com", author: "Your Name" },
  content: { posts: "content/posts", pages: "content/pages", media: "content/media" },
  hooks: { beforeBuild: ["node ./write-asset.mjs"] },
  assets: { passthrough: [{ from: "public", to: "." }] }
});`);
    await fs.writeFile(path.join(site, "write-asset.mjs"), `import { mkdir, writeFile } from "node:fs/promises";
await mkdir("public/assets/scripts", { recursive: true });
await writeFile("public/assets/scripts/application.js", "window.inksteadHook = true;");`);
    await buildSite(site, await loadConfig(site));
    expect(await fs.readFile(path.join(site, "dist/assets/scripts/application.js"), "utf8")).toContain("inksteadHook");
  });

  it("generates paginated category index pages and category RSS feeds when posts have categories", async () => {
    const site = await makeSite();
    for (let index = 0; index < 3; index += 1) {
      await fs.writeFile(path.join(site, `content/posts/2026-06-1${index}-cat-${index}.md`), `---\ntitle: Cat ${index}\ndate: 2026-06-1${index}T18:30:00+01:00\ncategories:\n  - Photography\n---\n\nPost ${index}\n`);
    }
    await fs.writeFile(path.join(site, "site.config.ts"), `import { defineConfig } from "inkstead";
export default defineConfig({
  site: { title: "My Website", url: "https://example.com", author: "Your Name" },
  content: { posts: "content/posts", pages: "content/pages", media: "content/media" },
  pagination: { postsPerPage: 2 }
});`);
    const config = await loadConfig(site);
    await buildSite(site, config);
    const categoryIndex = await fs.readFile(path.join(site, "dist/categories/photography/index.html"), "utf8");
    const categoryPage2 = await fs.readFile(path.join(site, "dist/categories/photography/page/2/index.html"), "utf8");
    const categoryFeed = await fs.readFile(path.join(site, "dist/categories/photography/feed.xml"), "utf8");
    expect(categoryIndex).toContain("#Photography");
    expect(categoryPage2).toContain("h-entry");
    expect(categoryFeed).toContain("My Website - Photography");
    expect(categoryFeed).toContain("Cat 2");
  });

  it("assigns categories from nested post directories", async () => {
    const site = await makeSite();
    await fs.mkdir(path.join(site, "content/posts/essays"), { recursive: true });
    await fs.writeFile(path.join(site, "content/posts/essays/2026-08-10-directory-category.md"), "---\ntitle: Directory Category\ndate: 2026-08-10T18:30:00+01:00\n---\n\nFrom a folder.\n");
    const config = await loadConfig(site);
    const posts = await loadPosts(site, config);
    const post = posts.find((item) => item.slug === "2026-08-10-directory-category");
    expect(post?.categories).toContain("Essays");
    await buildSite(site, config);
    const categoryIndex = await fs.readFile(path.join(site, "dist/categories/essays/index.html"), "utf8");
    expect(categoryIndex).toContain("Directory Category");
  });

  it("dedupes matching directory and frontmatter categories", async () => {
    const site = await makeSite();
    await fs.mkdir(path.join(site, "content/posts/essays"), { recursive: true });
    await fs.writeFile(path.join(site, "content/posts/essays/2026-08-11-dedupe.md"), "---\ntitle: Dedupe\ndate: 2026-08-11T18:30:00+01:00\ncategories:\n  - essays\n---\n\nOne category.\n");
    const config = await loadConfig(site);
    const post = (await loadPosts(site, config)).find((item) => item.slug === "2026-08-11-dedupe");
    expect(post?.categories).toHaveLength(1);
  });

  it("uses summary and more comments for index excerpts", async () => {
    const site = await makeSite();
    await fs.writeFile(path.join(site, "content/posts/2026-09-10-summary.md"), "---\ntitle: Summary Post\ndate: 2026-09-10T18:30:00+01:00\nsummary: Custom summary wins.\n---\n\nBody should not be the excerpt.\n");
    await fs.writeFile(path.join(site, "content/posts/2026-09-11-more.md"), "---\ntitle: More Post\ndate: 2026-09-11T18:30:00+01:00\n---\n\nIntro [paragraph](https://example.com).\n\n<!--more-->\n\nRest of the article.\n");
    await fs.writeFile(path.join(site, "content/posts/2026-09-12-auto.md"), `---\ntitle: Auto Post\ndate: 2026-09-12T18:30:00+01:00\n---\n\nA little [shared](https://example.com/shared) ${"word ".repeat(80)}\n`);
    const config = await loadConfig(site);
    const posts = await loadPosts(site, config);
    const summaryPost = posts.find((post) => post.title === "Summary Post");
    const morePost = posts.find((post) => post.title === "More Post");
    const autoPost = posts.find((post) => post.title === "Auto Post");
    expect(summaryPost?.excerpt).toBe("<p>Custom summary wins.</p>\n");
    expect(summaryPost?.hasMore).toBe(true);
    expect(morePost?.excerpt).toBe("<p>Intro <a href=\"https://example.com\">paragraph</a>.</p>\n");
    expect(morePost?.hasMore).toBe(true);
    expect(autoPost?.excerpt).toContain("<a href=\"https://example.com/shared\">shared</a>");
    expect(autoPost?.excerpt).toContain("…");
    await buildSite(site, config);
    const home = await fs.readFile(path.join(site, "dist/index.html"), "utf8");
    expect(home).toContain("Custom summary wins.");
    expect(home).toContain("<a href=\"https://example.com\">paragraph</a>");
    expect(home).toContain("<a href=\"https://example.com/shared\">shared</a>");
    expect(home).toContain("Continue reading");
  });

  it("excludes draft posts from content, site output, feeds, sitemap, and syndication", async () => {
    const site = await makeSite();
    await fs.writeFile(path.join(site, "site.config.ts"), `import { defineConfig } from "inkstead";
export default defineConfig({
  site: { title: "My Website", url: "https://example.com", author: "Your Name" },
  content: { posts: "content/posts", pages: "content/pages", media: "content/media" },
  syndication: { providers: ["mastodon"] }
});`);
    await fs.writeFile(path.join(site, "content/posts/2026-09-20-published.md"), "---\ntitle: Public Post\ndate: 2026-09-20T18:30:00+01:00\n---\n\nVisible.\n");
    await fs.writeFile(path.join(site, "content/posts/2026-09-21-draft.md"), "---\ntitle: Hidden Draft\ndate: 2026-09-21T18:30:00+01:00\nstatus: draft\nsyndicate:\n  - mastodon\n---\n\nShould stay private.\n");

    const config = await loadConfig(site);
    const posts = await loadPosts(site, config);
    expect(posts.map((post) => post.title)).toContain("Public Post");
    expect(posts.map((post) => post.title)).not.toContain("Hidden Draft");

    await buildSite(site, config);
    const home = await fs.readFile(path.join(site, "dist/index.html"), "utf8");
    const feed = await fs.readFile(path.join(site, "dist/feed.xml"), "utf8");
    const sitemap = await fs.readFile(path.join(site, "dist/sitemap.xml"), "utf8");
    expect(home).not.toContain("Hidden Draft");
    expect(feed).not.toContain("Hidden Draft");
    expect(sitemap).not.toContain("draft");
    await expect(fs.stat(path.join(site, "dist/2026/09/21/draft/index.html"))).rejects.toThrow();

    let published = false;
    const originalPublish = syndicationProviders.mastodon.publish;
    syndicationProviders.mastodon.publish = async () => {
      published = true;
      return { status: "published" };
    };
    try {
      const result = await syndicateSite(site, config);
      expect(result.published).toBe(0);
      expect(result.changed).toBe(false);
      expect(published).toBe(false);
    } finally {
      syndicationProviders.mastodon.publish = originalPublish;
    }
  });

  it("allows a theme to override the homepage with category links instead of posts", async () => {
    const site = await makeSite();
    await fs.mkdir(path.join(site, "theme"), { recursive: true });
    await fs.writeFile(path.join(site, "theme/home.liquid"), `<h1>Start Here</h1>
<ul>{% for category in categories %}<li><a href="{{ category.urlPath }}">{{ category.name }}</a></li>{% endfor %}</ul>`);
    await fs.writeFile(path.join(site, "content/posts/2026-07-10-themed.md"), "---\ntitle: Themed\ndate: 2026-07-10T18:30:00+01:00\ncategories:\n  - Photography\n---\n\nHidden from custom home.\n");
    const config = await loadConfig(site);
    await buildSite(site, config);
    const home = await fs.readFile(path.join(site, "dist/index.html"), "utf8");
    expect(home).toContain("Start Here");
    expect(home).toContain("/categories/photography/");
    expect(home).not.toContain("Themed");
    expect(await fs.readFile(path.join(site, "dist/2026/07/10/themed/index.html"), "utf8")).toContain("Themed");
  });

  it("excludes PNG photo notes from the photoPosts theme collection", async () => {
    const site = await makeSite();
    await fs.writeFile(path.join(site, "content/posts/2026-10-01-photo.md"), "---\ndate: 2026-10-01T18:30:00+01:00\n---\n\n![](/media/camera.jpg)\n");
    await fs.writeFile(path.join(site, "content/posts/2026-10-02-screenshot.md"), "---\ndate: 2026-10-02T18:30:00+01:00\n---\n\n![](/media/screenshot.png)\n");
    await fs.mkdir(path.join(site, "theme"), { recursive: true });
    await fs.writeFile(path.join(site, "theme/home.liquid"), `<ul>{% for post in photoPosts %}<li>{{ post.firstImage }}</li>{% endfor %}</ul>`);

    await buildSite(site, await loadConfig(site));
    const home = await fs.readFile(path.join(site, "dist/index.html"), "utf8");
    expect(home).toContain("/media/camera.jpg");
    expect(home).not.toContain("/media/screenshot.png");
  });

  it("uses a page-specific theme template when one matches the page slug", async () => {
    const site = await makeSite();
    await fs.writeFile(path.join(site, "content/pages/photos.md"), "---\ntitle: Photos\n---\n\nGallery intro.\n");
    await fs.writeFile(path.join(site, "content/posts/2026-10-01-photo.md"), "---\ndate: 2026-10-01T18:30:00+01:00\n---\n\n![](/media/camera.jpg)\n");
    await fs.mkdir(path.join(site, "theme"), { recursive: true });
    await fs.writeFile(path.join(site, "theme/photos.liquid"), `<h1>{{ page.title }}</h1>
<p>{{ page.html }}</p>
<ul>{% for post in photoPosts %}<li>{{ post.firstImage }}</li>{% endfor %}</ul>`);

    await buildSite(site, await loadConfig(site));
    const photos = await fs.readFile(path.join(site, "dist/photos/index.html"), "utf8");
    const about = await fs.readFile(path.join(site, "dist/about/index.html"), "utf8");
    expect(photos).toContain("/media/camera.jpg");
    expect(photos).toContain("Gallery intro.");
    expect(about).not.toContain("/media/camera.jpg");
  });
});

describe("writer core", () => {
  it("parses and serializes Writer frontmatter", () => {
    const parsed = parsePostMarkdown("---\ntitle: \"A Post\"\nstatus: draft\nsyndicate:\n  - mastodon\n  - bluesky\ncategories:\n  - Photography\nupdated_at: 2026-05-11T10:00:00.000Z\n---\n\nBody");
    expect(parsed.frontmatter.title).toBe("A Post");
    expect(parsed.frontmatter.status).toBe("draft");
    expect(parsed.frontmatter.syndicate).toEqual(["mastodon", "bluesky"]);
    expect(parsed.frontmatter.categories).toEqual(["Photography"]);
    expect(parsed.body).toBe("Body");
    const serialized = serializePostMarkdown(parsed.frontmatter, parsed.body);
    expect(serialized).toContain("title: \"A Post\"");
    expect(serialized).toContain("syndicate:\n  - mastodon\n  - bluesky");
    expect(serialized).toContain("categories:\n  - Photography");
    expect(parsePostMarkdown("---\nsyndicate: []\n---\n\nBody").frontmatter.syndicate).toEqual([]);
    expect(serializePostMarkdown({ syndicate: [] }, "Body")).toContain("syndicate: []");
  });

  it("generates dated slugs from titles and untitled post content", () => {
    expect(slugifyTitle("Café & Notes!")).toBe("cafe-and-notes");
    expect(slugForNewPost("Less Duct Tape, More Website", "", new Date("2026-05-11T09:04:00"))).toBe("2026-05-11-less-duct-tape-more-website");
    expect(slugForNewPost("", "Less **duct tape**, more <em>website</em>.", new Date("2026-05-11T09:04:00"))).toBe("2026-05-11-less-duct-tape-more-website");
    expect(slugForNewPost("", "📍 Tokyo, Japan 📷 Nikon F2", new Date("2026-05-11T09:04:00"))).toBe("2026-05-11-tokyo-japan-nikon-f2");
    expect(slugForNewPost("", "✨📷", new Date("2026-05-11T09:04:00"))).toBe("2026-05-11-untitled-0904");
    expect(slugForNewPost("", "", new Date("2026-05-11T09:04:00"))).toBe("2026-05-11-untitled-0904");
  });

  it("uses note content as the Writer post list label when there is no title", () => {
    expect(postExcerpt("A small note with a [link](https://example.com).\n\n![](/media/a.jpg)")).toBe("A small note with a link.");
    expect(postExcerpt("First line\nSecond line")).toBe("First line Second line");
    expect(postExcerpt("📍 New York, USA 📷 iPhone 16 Pro <img src=\"/media/img0931.jpeg\"")).toBe("📍 New York, USA 📷 iPhone 16 Pro");
    expect(postListLabel({ excerpt: "A small note." })).toBe("A small note.");
    expect(postListLabel({ title: "Named", excerpt: "Body" })).toBe("Named");
    expect(postListLabel({})).toBe("Untitled");
  });

  it("treats posts without status as published for backwards compatibility", () => {
    expect(summarizePost("content/posts/post.md", "---\ndate: 2026-05-11T10:00:00.000Z\n---\n\nBody").status).toBe("published");
    expect(summarizePost("content/posts/post.md", "---\nstatus: draft\n---\n\nBody").status).toBe("draft");
  });

  it("formats Writer post statuses for display", () => {
    expect(postStatusLabel("draft")).toBe("Draft");
    expect(postStatusLabel("published")).toBe("Published");
  });

  it("formats Writer post dates with browser locale settings", () => {
    expect(formatPostDate("2026-05-11T10:00:00.000Z", "en-US")).toBe("May 11, 2026");
    expect(formatPostDate("not-a-date", "en-US")).toBe("not-a-date");
    expect(formatPostDate(undefined, "en-US")).toBeUndefined();
  });

  it("sets the post date and removes status when publishing", () => {
    const markdown = buildPostMarkdown({
      title: "Publish Me",
      slug: "publish-me",
      status: "published",
      body: "Body",
      existingMarkdown: "---\ntitle: Publish Me\nslug: publish-me\nstatus: draft\ndate: 2026-05-01T10:00:00.000Z\n---\n\nBody",
      updateDate: true,
      now: new Date("2026-05-11T10:00:00.000Z")
    });
    expect(markdown).toContain("date: 2026-05-11T10:00:00.000Z");
    expect(markdown).not.toContain("status:");
    expect(markdown).not.toContain("slug:");
  });

  it("writes draft status when saving a draft", () => {
    const markdown = buildPostMarkdown({
      title: "Draft Me",
      slug: "draft-me",
      status: "draft",
      body: "Body",
      existingMarkdown: "---\ntitle: Draft Me\nslug: draft-me\ndate: 2026-05-01T10:00:00.000Z\n---\n\nBody",
      now: new Date("2026-05-11T10:00:00.000Z")
    });
    expect(markdown).toContain("status: draft");
    expect(markdown).toContain("date: 2026-05-01T10:00:00.000Z");
    expect(markdown).not.toContain("slug:");
  });

  it("writes selected syndication targets for new Writer posts", () => {
    const markdown = buildPostMarkdown({
      title: "",
      slug: "note",
      status: "draft",
      body: "Body",
      syndicationTargets: ["mastodon", "bluesky"],
      now: new Date("2026-05-11T10:00:00.000Z")
    });
    expect(markdown).toContain("syndicate:\n  - mastodon\n  - bluesky");
  });

  it("preserves existing syndication targets when editing Writer posts", () => {
    const markdown = buildPostMarkdown({
      title: "Published",
      slug: "published",
      status: "published",
      body: "Updated",
      existingMarkdown: "---\ntitle: Published\ndate: 2026-05-01T10:00:00.000Z\nsyndicate:\n  - mastodon\n---\n\nBody",
      now: new Date("2026-05-11T10:00:00.000Z")
    });
    expect(markdown).toContain("syndicate:\n  - mastodon");
  });

  it("updates syndication targets when editing Writer drafts", () => {
    const markdown = buildPostMarkdown({
      title: "Draft",
      slug: "draft",
      status: "draft",
      body: "Updated",
      existingMarkdown: "---\ntitle: Draft\nstatus: draft\nsyndicate:\n  - mastodon\n  - bluesky\n---\n\nBody",
      syndicationTargets: ["bluesky"],
      now: new Date("2026-05-11T10:00:00.000Z")
    });
    expect(markdown).toContain("syndicate:\n  - bluesky");
    expect(markdown).not.toContain("  - mastodon");
  });

  it("records an empty syndication list when all draft targets are disabled", () => {
    const markdown = buildPostMarkdown({
      title: "Draft",
      slug: "draft",
      status: "draft",
      body: "Updated",
      existingMarkdown: "---\ntitle: Draft\nstatus: draft\nsyndicate:\n  - mastodon\n---\n\nBody",
      syndicationTargets: [],
      now: new Date("2026-05-11T10:00:00.000Z")
    });
    expect(markdown).toContain("syndicate: []");
  });

  it("writes selected Writer categories", () => {
    const markdown = buildPostMarkdown({
      title: "Categorized",
      slug: "categorized",
      status: "published",
      body: "Body",
      existingMarkdown: "---\ntitle: Categorized\ndate: 2026-05-01T10:00:00.000Z\ncategories:\n  - Essays\n---\n\nBody",
      categoryTargets: ["Photography"],
      now: new Date("2026-05-11T10:00:00.000Z")
    });
    expect(markdown).toContain("categories:\n  - Photography");
    expect(markdown).not.toContain("  - Essays");
  });

  it("records an empty category list when all configured categories are disabled", () => {
    const markdown = buildPostMarkdown({
      title: "Categorized",
      slug: "categorized",
      status: "published",
      body: "Body",
      existingMarkdown: "---\ntitle: Categorized\ndate: 2026-05-01T10:00:00.000Z\ncategories:\n  - Essays\n---\n\nBody",
      categoryTargets: [],
      now: new Date("2026-05-11T10:00:00.000Z")
    });
    expect(markdown).toContain("categories: []");
  });

  it("preserves the post date when saving an already published post", () => {
    const markdown = buildPostMarkdown({
      title: "Published",
      slug: "published",
      status: "published",
      body: "Edited body",
      existingMarkdown: "---\ntitle: Published\nslug: published\ndate: 2026-05-01T10:00:00.000Z\n---\n\nBody",
      now: new Date("2026-05-11T10:00:00.000Z")
    });
    expect(markdown).toContain("date: 2026-05-01T10:00:00.000Z");
    expect(markdown).toContain("updated_at: 2026-05-11T10:00:00.000Z");
    expect(markdown).not.toContain("status:");
  });

  it("sorts Writer posts by post date before edit timestamps", () => {
    const posts = [
      { title: "Recently edited older post", date: "2026-05-09T10:00:00.000Z", updatedAt: "2026-05-12T10:00:00.000Z" },
      { title: "Newest dated post", date: "2026-05-11T10:00:00.000Z" },
      { title: "Middle dated post", date: "2026-05-10T10:00:00.000Z" }
    ].sort((a, b) => postDateSortValue(b).localeCompare(postDateSortValue(a)));
    expect(posts.map((post) => post.title)).toEqual(["Newest dated post", "Middle dated post", "Recently edited older post"]);
  });

  it("extracts Markdown and HTML image references", () => {
    expect(extractMarkdownImageReferences("![](a.jpg)\n<img src=\"/images/b.png\">")).toEqual(["a.jpg", "/images/b.png"]);
  });

  it("keeps Writer media flat and chooses unique filenames", () => {
    expect(mediaAssetPath("content/media", "keep.jpg")).toBe("content/media/keep.jpg");
    expect(markdownMediaReference("content/media", "keep.jpg")).toBe("/media/keep.jpg");
    expect(mediaAssetPath("content/photos", "IMG_2841.jpeg")).toBe("content/photos/IMG_2841.jpeg");
    expect(markdownMediaReference("content/photos", "IMG_2841.jpeg")).toBe("/photos/IMG_2841.jpeg");
    expect(uniqueAssetFilename("My Photo.JPG", [])).toBe("my-photo.jpg");
    expect(uniqueAssetFilename("My Photo.JPG", ["my-photo.jpg", "my-photo-2.jpg"])).toBe("my-photo-3.jpg");
    expect(referencedMediaPaths("![](/media/keep.jpg)\n<img src=\"/media/other.jpg\">", "content/media")).toEqual(["content/media/keep.jpg", "content/media/other.jpg"]);
    expect(referencedMediaPaths("![](/photos/IMG_2841.jpeg)", "content/photos")).toEqual(["content/photos/IMG_2841.jpeg"]);
  });

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

  it("supports GitLab Writer config and validates through the GitLab API", async () => {
    const requests: Array<{ url: string; token: string | null }> = [];
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async (input, init) => {
      const url = String(input);
      requests.push({ url, token: new Headers(init?.headers).get("PRIVATE-TOKEN") });
      if (url.includes("/repository/tree?")) return new Response("[]", { status: 200, headers: { "content-type": "application/json" } });
      return new Response("{}", { status: 404, headers: { "content-type": "application/json" } });
    };

    try {
      const adapter = new GitLabRepositoryAdapter({
        provider: "gitlab",
        owner: "group/subgroup",
        repo: "site",
        branch: "main",
        postsPath: "content/posts",
        mediaPath: "content/media"
      }, "pat");
      await adapter.validateConnection();
      expect(requests[0].url).toContain("https://gitlab.com/api/v4/projects/group%2Fsubgroup%2Fsite/repository/tree?");
      expect(requests[0].url).toContain("path=content%2Fposts");
      expect(requests[0].url).toContain("ref=main");
      expect(requests[0].token).toBe("pat");
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("loads GitHub Writer posts concurrently", async () => {
    let activeFileReads = 0;
    let maxActiveFileReads = 0;
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async (input) => {
      const url = String(input);
      if (url.includes("/git/trees/main?")) {
        return new Response(JSON.stringify({
          tree: [
            { type: "blob", path: "content/posts/older.md", sha: "older" },
            { type: "blob", path: "content/posts/newer.md", sha: "newer" }
          ]
        }), { status: 200, headers: { "content-type": "application/json" } });
      }
      activeFileReads += 1;
      maxActiveFileReads = Math.max(maxActiveFileReads, activeFileReads);
      await new Promise((resolve) => setTimeout(resolve, 10));
      activeFileReads -= 1;
      const newer = url.includes("/git/blobs/newer");
      return new Response(JSON.stringify({
        content: Buffer.from(`---\ntitle: ${newer ? "Newer" : "Older"}\ndate: ${newer ? "2026-05-12" : "2026-05-11"}\n---\n\nBody`).toString("base64")
      }), { status: 200, headers: { "content-type": "application/json" } });
    };

    try {
      const adapter = new GitHubRepositoryAdapter({
        provider: "github",
        owner: "me",
        repo: "site",
        branch: "main",
        postsPath: "content/posts",
        mediaPath: "content/media"
      }, "pat");
      const posts = await adapter.listPosts();
      expect(posts.map((post) => post.title)).toEqual(["Newer", "Older"]);
      expect(maxActiveFileReads).toBeGreaterThan(1);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("deletes GitHub Writer posts and media in a single commit", async () => {
    const requests: Array<{ url: string; method: string; body?: unknown }> = [];
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async (input, init = {}) => {
      const url = String(input);
      const method = init.method ?? "GET";
      requests.push({ url, method, body: init.body ? JSON.parse(String(init.body)) : undefined });
      if (url.includes("/contents/content/posts/post.md")) return new Response(JSON.stringify({ type: "file", path: "content/posts/post.md", sha: "post-sha" }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.includes("/contents/content/media/photo.jpg")) return new Response(JSON.stringify({ type: "file", path: "content/media/photo.jpg", sha: "photo-sha" }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.includes("/git/ref/heads/main")) return new Response(JSON.stringify({ object: { sha: "parent-sha" } }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.includes("/git/commits/parent-sha")) return new Response(JSON.stringify({ sha: "parent-sha", tree: { sha: "tree-sha" } }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.endsWith("/git/trees")) return new Response(JSON.stringify({ sha: "new-tree-sha" }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.endsWith("/git/commits")) return new Response(JSON.stringify({ sha: "new-commit-sha", html_url: "https://github.test/commit" }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.includes("/git/refs/heads/main")) return new Response(JSON.stringify({ ok: true }), { status: 200, headers: { "content-type": "application/json" } });
      return new Response("{}", { status: 404, headers: { "content-type": "application/json" } });
    };

    try {
      const adapter = new GitHubRepositoryAdapter({
        provider: "github",
        owner: "me",
        repo: "site",
        branch: "main",
        postsPath: "content/posts",
        mediaPath: "content/media"
      }, "pat");
      const result = await adapter.deletePost({ path: "content/posts/post.md", slug: "post", sha: "post-sha", mediaPaths: ["content/media/photo.jpg"] });
      expect(result.sha).toBe("new-commit-sha");
      const treeRequest = requests.find((request) => request.url.endsWith("/git/trees"));
      expect(treeRequest?.body).toMatchObject({
        base_tree: "tree-sha",
        tree: [
          { path: "content/posts/post.md", sha: null },
          { path: "content/media/photo.jpg", sha: null }
        ]
      });
      expect(requests.filter((request) => request.method === "DELETE")).toHaveLength(0);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("saves GitHub Writer posts and media in a single commit", async () => {
    const requests: Array<{ url: string; method: string; body?: unknown }> = [];
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async (input, init = {}) => {
      const url = String(input);
      const method = init.method ?? "GET";
      requests.push({ url, method, body: init.body ? JSON.parse(String(init.body)) : undefined });
      if (url.includes("/contents/content/posts/post.md")) return new Response(JSON.stringify({ type: "file", path: "content/posts/post.md", sha: "post-sha" }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.includes("/contents/content/media/photo.jpg")) return new Response("{}", { status: 404, headers: { "content-type": "application/json" } });
      if (url.includes("/git/ref/heads/main")) return new Response(JSON.stringify({ object: { sha: "parent-sha" } }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.includes("/git/commits/parent-sha")) return new Response(JSON.stringify({ sha: "parent-sha", tree: { sha: "tree-sha" } }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.endsWith("/git/blobs")) return new Response(JSON.stringify({ sha: `blob-${requests.filter((request) => request.url.endsWith("/git/blobs")).length}` }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.endsWith("/git/trees")) return new Response(JSON.stringify({ sha: "new-tree-sha" }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.endsWith("/git/commits")) return new Response(JSON.stringify({ sha: "new-commit-sha", html_url: "https://github.test/commit" }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.includes("/git/refs/heads/main")) return new Response(JSON.stringify({ ok: true }), { status: 200, headers: { "content-type": "application/json" } });
      return new Response("{}", { status: 404, headers: { "content-type": "application/json" } });
    };

    try {
      const adapter = new GitHubRepositoryAdapter({
        provider: "github",
        owner: "me",
        repo: "site",
        branch: "main",
        postsPath: "content/posts",
        mediaPath: "content/media"
      }, "pat");
      const result = await adapter.savePost({
        path: "content/posts/post.md",
        slug: "post",
        status: "published",
        content: "---\ndate: 2026-05-11\n---\n\n![](/media/photo.jpg)",
        sha: "post-sha",
        media: [{ path: "content/media/photo.jpg", contentBase64: Buffer.from("image").toString("base64"), message: "Upload media" }]
      });
      expect(result.sha).toBe("new-commit-sha");
      const treeRequest = requests.find((request) => request.url.endsWith("/git/trees"));
      expect(treeRequest?.body).toMatchObject({
        base_tree: "tree-sha",
        tree: [
          { path: "content/posts/post.md" },
          { path: "content/media/photo.jpg" }
        ]
      });
      expect(requests.filter((request) => request.url.includes("/contents/") && request.method === "PUT")).toHaveLength(0);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("retries GitHub Writer media saves when the branch moved", async () => {
    let refUpdates = 0;
    let refReads = 0;
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async (input, init = {}) => {
      const url = String(input);
      const method = init.method ?? "GET";
      if (url.includes("/contents/content/posts/post.md")) return new Response("{}", { status: 404, headers: { "content-type": "application/json" } });
      if (url.includes("/contents/content/media/photo.jpg")) return new Response("{}", { status: 404, headers: { "content-type": "application/json" } });
      if (url.includes("/git/ref/heads/main") && method === "GET") {
        refReads += 1;
        return new Response(JSON.stringify({ object: { sha: refReads === 1 ? "old-parent" : "new-parent" } }), { status: 200, headers: { "content-type": "application/json" } });
      }
      if (url.includes("/git/commits/old-parent")) return new Response(JSON.stringify({ sha: "old-parent", tree: { sha: "old-tree" } }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.includes("/git/commits/new-parent")) return new Response(JSON.stringify({ sha: "new-parent", tree: { sha: "new-tree" } }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.endsWith("/git/blobs")) return new Response(JSON.stringify({ sha: "blob-sha" }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.endsWith("/git/trees")) return new Response(JSON.stringify({ sha: "tree-sha" }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.endsWith("/git/commits")) return new Response(JSON.stringify({ sha: `commit-${refReads}` }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.includes("/git/refs/heads/main") && method === "PATCH") {
        refUpdates += 1;
        if (refUpdates === 1) return new Response(JSON.stringify({ message: "Update is not a fast forward" }), { status: 422, headers: { "content-type": "application/json" } });
        return new Response(JSON.stringify({ ok: true }), { status: 200, headers: { "content-type": "application/json" } });
      }
      return new Response("{}", { status: 404, headers: { "content-type": "application/json" } });
    };

    try {
      const adapter = new GitHubRepositoryAdapter({
        provider: "github",
        owner: "me",
        repo: "site",
        branch: "main",
        postsPath: "content/posts",
        mediaPath: "content/media"
      }, "pat");
      const result = await adapter.savePost({
        path: "content/posts/post.md",
        slug: "post",
        status: "draft",
        content: "Body\n\n![](/media/photo.jpg)",
        media: [{ path: "content/media/photo.jpg", contentBase64: Buffer.from("image").toString("base64"), message: "Upload media" }]
      });
      expect(result.sha).toBe("commit-2");
      expect(refUpdates).toBe(2);
      expect(refReads).toBe(2);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("reuses the latest GitHub branch head after a successful batch commit", async () => {
    let refReads = 0;
    const commits: string[] = [];
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async (input, init = {}) => {
      const url = String(input);
      const method = init.method ?? "GET";
      if (url.includes("/contents/content/posts/")) return new Response("{}", { status: 404, headers: { "content-type": "application/json" } });
      if (url.includes("/contents/content/media/")) return new Response("{}", { status: 404, headers: { "content-type": "application/json" } });
      if (url.includes("/git/ref/heads/main") && method === "GET") {
        refReads += 1;
        return new Response(JSON.stringify({ object: { sha: "initial-parent" } }), { status: 200, headers: { "content-type": "application/json" } });
      }
      if (url.includes("/git/commits/initial-parent")) return new Response(JSON.stringify({ sha: "initial-parent", tree: { sha: "initial-tree" } }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.includes("/git/commits/commit-1")) return new Response(JSON.stringify({ sha: "commit-1", tree: { sha: "tree-1" } }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.endsWith("/git/blobs")) return new Response(JSON.stringify({ sha: "blob-sha" }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.endsWith("/git/trees")) return new Response(JSON.stringify({ sha: "new-tree-sha" }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.endsWith("/git/commits")) {
        const sha = `commit-${commits.length + 1}`;
        commits.push(sha);
        return new Response(JSON.stringify({ sha }), { status: 200, headers: { "content-type": "application/json" } });
      }
      if (url.includes("/git/refs/heads/main") && method === "PATCH") return new Response(JSON.stringify({ ok: true }), { status: 200, headers: { "content-type": "application/json" } });
      return new Response("{}", { status: 404, headers: { "content-type": "application/json" } });
    };

    try {
      const adapter = new GitHubRepositoryAdapter({
        provider: "github",
        owner: "me",
        repo: "site",
        branch: "main",
        postsPath: "content/posts",
        mediaPath: "content/media"
      }, "pat");
      await adapter.savePost({
        path: "content/posts/one.md",
        slug: "one",
        status: "draft",
        content: "One",
        media: [{ path: "content/media/one.jpg", contentBase64: Buffer.from("one").toString("base64"), message: "Upload media" }]
      });
      await adapter.savePost({
        path: "content/posts/two.md",
        slug: "two",
        status: "draft",
        content: "Two",
        media: [{ path: "content/media/two.jpg", contentBase64: Buffer.from("two").toString("base64"), message: "Upload media" }]
      });
      expect(refReads).toBe(1);
      expect(commits).toEqual(["commit-1", "commit-2"]);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("deletes GitLab Writer posts and media in a single commit", async () => {
    const requests: Array<{ url: string; method: string; body?: unknown }> = [];
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async (input, init = {}) => {
      const url = String(input);
      const method = init.method ?? "GET";
      requests.push({ url, method, body: init.body ? JSON.parse(String(init.body)) : undefined });
      if (url.includes("/repository/files/")) return new Response(JSON.stringify({ file_path: "file", file_name: "file", blob_id: "sha", content: "" }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.endsWith("/repository/commits")) return new Response(JSON.stringify({ id: "new-commit-sha", web_url: "https://gitlab.test/commit" }), { status: 200, headers: { "content-type": "application/json" } });
      return new Response("{}", { status: 404, headers: { "content-type": "application/json" } });
    };

    try {
      const adapter = new GitLabRepositoryAdapter({
        provider: "gitlab",
        owner: "me",
        repo: "site",
        branch: "main",
        postsPath: "content/posts",
        mediaPath: "content/media"
      }, "pat");
      const result = await adapter.deletePost({ path: "content/posts/post.md", slug: "post", mediaPaths: ["content/media/photo.jpg"] });
      expect(result.sha).toBe("new-commit-sha");
      const commitRequest = requests.find((request) => request.url.endsWith("/repository/commits"));
      expect(commitRequest?.body).toMatchObject({
        branch: "main",
        commit_message: "Delete post: post",
        actions: [
          { action: "delete", file_path: "content/posts/post.md" },
          { action: "delete", file_path: "content/media/photo.jpg" }
        ]
      });
      expect(requests.filter((request) => request.method === "DELETE")).toHaveLength(0);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("saves GitLab Writer posts and media in a single commit", async () => {
    const requests: Array<{ url: string; method: string; body?: unknown }> = [];
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async (input, init = {}) => {
      const url = String(input);
      const method = init.method ?? "GET";
      requests.push({ url, method, body: init.body ? JSON.parse(String(init.body)) : undefined });
      if (url.includes("/repository/files/content%2Fposts%2Fpost.md")) return new Response(JSON.stringify({ file_path: "content/posts/post.md", file_name: "post.md", blob_id: "sha", content: "" }), { status: 200, headers: { "content-type": "application/json" } });
      if (url.includes("/repository/files/content%2Fmedia%2Fphoto.jpg")) return new Response("{}", { status: 404, headers: { "content-type": "application/json" } });
      if (url.endsWith("/repository/commits")) return new Response(JSON.stringify({ id: "new-commit-sha", web_url: "https://gitlab.test/commit" }), { status: 200, headers: { "content-type": "application/json" } });
      return new Response("{}", { status: 404, headers: { "content-type": "application/json" } });
    };

    try {
      const adapter = new GitLabRepositoryAdapter({
        provider: "gitlab",
        owner: "me",
        repo: "site",
        branch: "main",
        postsPath: "content/posts",
        mediaPath: "content/media"
      }, "pat");
      const result = await adapter.savePost({
        path: "content/posts/post.md",
        slug: "post",
        status: "published",
        sha: "sha",
        content: "---\ndate: 2026-05-11\n---\n\n![](/media/photo.jpg)",
        media: [{ path: "content/media/photo.jpg", contentBase64: Buffer.from("image").toString("base64"), message: "Upload media" }]
      });
      expect(result.sha).toBe("new-commit-sha");
      const commitRequest = requests.find((request) => request.url.endsWith("/repository/commits"));
      expect(commitRequest?.body).toMatchObject({
        branch: "main",
        commit_message: "Publish post: post",
        actions: [
          { action: "update", file_path: "content/posts/post.md" },
          { action: "create", file_path: "content/media/photo.jpg" }
        ]
      });
      expect(requests.filter((request) => request.url.includes("/repository/files/") && ["POST", "PUT"].includes(request.method))).toHaveLength(0);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("overrides Writer to the local provider in the dev server", async () => {
    const site = await makeSite();
    const config = await loadConfig(site);
    config.writer = {
      enabled: true,
      provider: "github",
      owner: "example",
      repo: "site",
      branch: "main"
    };

    expect(localWriterConfig(config).writer?.provider).toBe("local");
  });

  it("serves local Writer API requests from the working copy", async () => {
    const site = await makeSite();
    const config = localWriterConfig({
      ...await loadConfig(site),
      writer: {
        enabled: true,
        provider: "gitlab",
        owner: "example",
        repo: "site",
        branch: "main"
      }
    });
    const content = "---\ntitle: Local\nslug: local\ndate: 2026-05-11T10:00:00.000Z\nstatus: draft\nupdated_at: 2026-05-11T10:00:00.000Z\n---\n\nBody\n\n![](/media/photo.jpg)";
    const save = await localApi("PUT", "/__inkstead-writer/api/post", { path: "content/posts/local.md", content }, site, config);
    expect(save.status).toBe(200);
    expect(await fs.readFile(path.join(site, "content/posts/local.md"), "utf8")).toBe(content);
    const duplicatePost = await localApi("PUT", "/__inkstead-writer/api/post", { path: "content/posts/local.md", content: content.replace("Body", "Replacement") }, site, config);
    expect(duplicatePost.status).toBe(400);
    expect(await fs.readFile(path.join(site, "content/posts/local.md"), "utf8")).toBe(content);

    const posts = await localApi("GET", "/__inkstead-writer/api/posts", undefined, site, config);
    expect((posts.body as Array<{ slug: string }>).map((post) => post.slug)).toContain("local");
    expect((posts.body as Array<{ slug: string; date?: string }>).find((post) => post.slug === "local")?.date).toBe("2026-05-11T10:00:00.000Z");

    const upload = await localApi("PUT", "/__inkstead-writer/api/asset", {
      path: "content/media/photo.jpg",
      contentBase64: Buffer.from("fake image").toString("base64")
    }, site, config);
    expect(upload.status).toBe(200);
    const duplicate = await localApi("PUT", "/__inkstead-writer/api/asset", {
      path: "content/media/photo.jpg",
      contentBase64: Buffer.from("replacement").toString("base64")
    }, site, config);
    expect(duplicate.status).toBe(400);
    const media = await localApi("GET", "/__inkstead-writer/api/assets?folder=content%2Fmedia", undefined, site, config);
    expect((media.body as Array<{ name: string }>).map((asset) => asset.name)).toContain("photo.jpg");

    const deleted = await localApi("DELETE", "/__inkstead-writer/api/post", { path: "content/posts/local.md", mediaPaths: ["content/media/photo.jpg"] }, site, config);
    expect(deleted.status).toBe(200);
    await expect(fs.stat(path.join(site, "content/media/photo.jpg"))).rejects.toThrow();

    const escape = await localApi("PUT", "/__inkstead-writer/api/post", { path: "content/pages/nope.md", content }, site, config);
    expect(escape.status).toBe(400);
  });

  it("resolves extensionless dev server paths to directory index files", () => {
    expect(staticFilePath("/")).toBe("index.html");
    expect(staticFilePath("/writer")).toBe("writer/index.html");
    expect(staticFilePath("/writer/")).toBe("writer/index.html");
    expect(staticFilePath("/assets/app.js")).toBe("assets/app.js");
  });

  it("serves JavaScript with a module-compatible MIME type", () => {
    expect(contentType("assets/app.js")).toBe("text/javascript; charset=utf-8");
    expect(contentType("assets/app.mjs")).toBe("text/javascript; charset=utf-8");
  });

  it("does not show an Untitled fallback in Writer previews", () => {
    expect(previewTitle(undefined)).toBeUndefined();
    expect(previewTitle("   ")).toBeUndefined();
    expect(previewTitle("Named")).toBe("Named");
  });

  it("ships Writer PWA metadata and Inkstead app icons", async () => {
    const index = await fs.readFile(path.join(process.cwd(), "src/writer/app/index.html"), "utf8");
    expect(index).toContain("location.replace");
    expect(index).toContain('<meta name="robots" content="noindex, nofollow" />');
    const manifest = JSON.parse(await fs.readFile(path.join(process.cwd(), "src/writer/app/public/manifest.webmanifest"), "utf8"));
    expect(manifest.name).toBe("Inkstead Writer");
    expect(manifest.display).toBe("fullscreen");
    expect(manifest.start_url).toBe("./");
    expect(manifest.scope).toBe("./");
    expect(manifest.icons.map((icon: { src: string }) => icon.src)).toEqual(["./icons/inkstead-192.png", "./icons/inkstead-512.png"]);
    await expect(fs.stat(path.join(process.cwd(), "src/writer/app/public/icons/inkstead-192.png"))).resolves.toBeTruthy();
    await expect(fs.stat(path.join(process.cwd(), "src/writer/app/public/icons/inkstead-512.png"))).resolves.toBeTruthy();
    await expect(fs.stat(path.join(process.cwd(), "src/writer/app/public/icons/apple-touch-icon.png"))).resolves.toBeTruthy();
  });
});

async function localApi(method: string, url: string, body: unknown, root: string, config: Parameters<typeof handleWriterLocalApi>[3]): Promise<{ status: number; body: unknown }> {
  const request = Readable.from(body === undefined ? [] : [JSON.stringify(body)]) as unknown as Parameters<typeof handleWriterLocalApi>[0];
  request.method = method;
  request.url = url;
  let status = 0;
  let responseBody = "";
  const response = {
    writeHead(nextStatus: number) {
      status = nextStatus;
    },
    end(chunk: string) {
      responseBody = chunk;
    }
  } as unknown as Parameters<typeof handleWriterLocalApi>[1];
  await handleWriterLocalApi(request, response, root, config);
  return { status, body: JSON.parse(responseBody) };
}

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
    const site = await makeSite();
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
    const site = await makeSite();
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
    const site = await makeSite();
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

describe("frontmatter syndication", () => {
  it("prepares oversized images for syndication without changing the original", async () => {
    const source = path.join(tempRoot, "large.png");
    const original = await sharp({
      create: {
        width: 1200,
        height: 1200,
        channels: 3,
        background: "#5fc9b5"
      }
    }).png().toBuffer();
    await fs.writeFile(source, original);

    const prepared = await prepareImageForSyndication(source, { maxBytes: 20_000, maxDimension: 800 });
    expect(prepared.generated).toBe(true);
    expect(prepared.mimeType).toBe("image/jpeg");
    expect(prepared.bytes.byteLength).toBeLessThanOrEqual(20_000);
    expect(await fs.readFile(source)).toEqual(original);
  });

  it("uses the original image when it already fits syndication limits", async () => {
    const source = path.join(tempRoot, "small.jpg");
    const original = await sharp({
      create: {
        width: 64,
        height: 64,
        channels: 3,
        background: "#f7b733"
      }
    }).jpeg().toBuffer();
    await fs.writeFile(source, original);

    const prepared = await prepareImageForSyndication(source, { maxBytes: 100_000, maxDimension: 800 });
    expect(prepared.generated).toBe(false);
    expect(prepared.path).toBe(source);
    expect(prepared.bytes).toEqual(original);
  });

  it("updates only syndication data and preserves the markdown body", () => {
    const original = "---\ndate: 2026-05-10T18:30:00+01:00\nsyndicate:\n  - mastodon\n---\n\nBody **must** stay.\n\n";
    const updated = updateSyndicationFrontmatter(original, "mastodon", { status: "published", url: "https://example.com/1" });
    expect(updated).toContain("syndication:");
    expect(updated).toContain("mastodon:");
    expect(updated.endsWith("\nBody **must** stay.\n")).toBe(true);
  });

  it("can represent already published targets for idempotent syndication", () => {
    const updated = updateSyndicationFrontmatter("---\ndate: 2026-05-10T18:30:00+01:00\n---\n\nHi\n", "bluesky", { status: "published", uri: "at://did/post" });
    expect(updated).toContain("status: published");
    expect(updated).toContain("at://did/post");
  });
});
