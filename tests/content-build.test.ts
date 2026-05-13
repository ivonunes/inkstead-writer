import { promises as fs } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import sharp from "sharp";
import { buildSite, createPost, ejectTheme, loadConfig } from "../src/index.js";
import { loadPosts } from "../src/core/content/load-content.js";
import { textForSyndication } from "../src/core/syndication/text.js";
import { copyWriterApp } from "../src/core/writer/build.js";
import { syndicationProviders } from "../src/core/adapters/registry.js";
import { syndicateSite } from "../src/core/syndication/syndicate.js";
import { useSiteFixture } from "./helpers/site.js";

const fixture = useSiteFixture();

describe("content and build", () => {
  it("can copy default templates into a site theme without overwriting existing files", async () => {
    const site = await fixture.makeSite();
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
    const site = await fixture.makeSite();
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
    const site = await fixture.makeSite();
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
    const site = await fixture.makeSite();
    await fs.writeFile(path.join(site, "content/posts/2026-05-13-markdown-note.md"), "---\ndate: 2026-05-13T18:30:00+01:00\nsyndicate:\n  - mastodon\n---\n\nThinking about **bold** and _italic_ notes with a [link](https://example.com/post).\n\n`code` is okay.\n\n![](/media/sample.jpg)\n");
    const config = await loadConfig(site);
    const post = (await loadPosts(site, config)).find((item) => item.slug === "2026-05-13-markdown-note");
    expect(post ? textForSyndication(post) : "").toBe("Thinking about bold and italic notes with a link (https://example.com/post).\n\ncode is okay.");
  });

  it("creates a new article with title, date, and enabled text syndication", async () => {
    const site = await fixture.makeSite();
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
    const site = await fixture.makeSite();
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
    const site = await fixture.makeSite();
    const config = await loadConfig(site);
    const date = new Date(2026, 4, 10, 12, 30);
    const note = await createPost(site, config, { kind: "note", text: "📍 Tokyo, Japan\n\nLess **duct tape**, more <em>website</em>.", date });
    const emojiOnly = await createPost(site, config, { kind: "note", text: "✨📷", date });
    expect(note.relativePath).toBe("content/posts/2026-05-10-tokyo-japan-less-duct-tape-more-website.md");
    expect(emojiOnly.relativePath).toBe("content/posts/2026-05-10-untitled-1230.md");
  });

  it("supports output paths, asset passthrough, raw HTML, hard breaks, and pagination", async () => {
    const site = await fixture.makeSite();
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
    const site = await fixture.makeSite();
    const writerDist = path.join(fixture.tempRoot, "writer-dist");
    const dist = path.join(site, "dist");
    await fs.mkdir(path.join(writerDist, "assets"), { recursive: true });
    await fs.mkdir(path.join(writerDist, "icons"), { recursive: true });
    await fs.writeFile(path.join(writerDist, "index.html"), "<meta name=\"robots\" content=\"noindex, nofollow\"><link rel=\"manifest\" href=\"./manifest.webmanifest\"><script type=\"module\" src=\"./assets/app.js\"></script><link rel=\"stylesheet\" href=\"./assets/app.css\"><div id=\"root\"></div>");
    await fs.writeFile(path.join(writerDist, "manifest.webmanifest"), "{\"name\":\"Inkstead Writer\"}");
    await fs.writeFile(path.join(writerDist, "assets/app.js"), "console.log('writer')");
    await fs.writeFile(path.join(writerDist, "assets/app.css"), "body{}");
    await fs.writeFile(path.join(writerDist, "icons/inkstead-192.png"), "icon");
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
    await expect(fs.stat(path.join(dist, "writer/assets/app.css"))).resolves.toBeTruthy();
    await expect(fs.stat(path.join(dist, "writer/manifest.webmanifest"))).resolves.toBeTruthy();
    await expect(fs.stat(path.join(dist, "writer/icons/inkstead-192.png"))).resolves.toBeTruthy();
    const writerHtml = await fs.readFile(path.join(dist, "writer/index.html"), "utf8");
    expect(writerHtml).toContain('name="robots" content="noindex, nofollow"');
    expect(writerHtml).toContain("./assets/app.js");
    expect(writerHtml).toContain("./assets/app.css");
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
    const site = await fixture.makeSite();
    const config = await loadConfig(site);
    await copyWriterApp(path.join(site, "dist"), config, { writerDist: path.join(fixture.tempRoot, "missing") });
    await expect(fs.stat(path.join(site, "dist/writer"))).rejects.toThrow();
  });

  it("can hide the default powered-by footer link", async () => {
    const site = await fixture.makeSite();
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
    const site = await fixture.makeSite();
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
    const site = await fixture.makeSite();
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
    const site = await fixture.makeSite();
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
    const site = await fixture.makeSite();
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
    const site = await fixture.makeSite();
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
    const site = await fixture.makeSite();
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
    const site = await fixture.makeSite();
    await fs.mkdir(path.join(site, "content/posts/essays"), { recursive: true });
    await fs.writeFile(path.join(site, "content/posts/essays/2026-08-11-dedupe.md"), "---\ntitle: Dedupe\ndate: 2026-08-11T18:30:00+01:00\ncategories:\n  - essays\n---\n\nOne category.\n");
    const config = await loadConfig(site);
    const post = (await loadPosts(site, config)).find((item) => item.slug === "2026-08-11-dedupe");
    expect(post?.categories).toHaveLength(1);
  });

  it("uses summary and more comments for index excerpts", async () => {
    const site = await fixture.makeSite();
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
    const site = await fixture.makeSite();
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
    const site = await fixture.makeSite();
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
    const site = await fixture.makeSite();
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
    const site = await fixture.makeSite();
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
