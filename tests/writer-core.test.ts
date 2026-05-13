import { describe, expect, it } from "vitest";
import { parsePostMarkdown, serializePostMarkdown } from "../src/writer/app/core/frontmatter.js";
import { categoriesFromFrontmatter, shouldShowCategoryTargets, shouldShowSyndicationTargets, syndicationTargetsFromFrontmatter, unmanagedCategoriesFromFrontmatter } from "../src/writer/app/core/editor-state.js";
import { isPostFileCacheStale, isPostSummaryCacheStale, removePostFile, removePostSummary, upsertPostFile, upsertPostSummary } from "../src/writer/app/core/post-cache.js";
import { buildPostMarkdown, formatPostDate, postDateSortValue, postExcerpt, postListLabel, postStatusLabel, slugForNewPost, slugifyTitle, summarizePost } from "../src/writer/app/core/posts.js";
import { extractMarkdownImageReferences } from "../src/writer/app/core/markdown.js";
import { markdownMediaReference, mediaAssetPath, referencedMediaPaths, uniqueAssetFilename } from "../src/writer/app/core/assets.js";

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

  it("round-trips richer frontmatter without dropping unknown or nested fields", () => {
    const original = "---\ntitle: \"A Post\"\nsummary: Custom summary.\nsyndicate:\n  - mastodon\ncategories:\n  - \"Long Form\"\nsyndication:\n  mastodon:\n    status: published\n    url: https://example.com/post\n---\n\nBody";
    const parsed = parsePostMarkdown(original);
    const serialized = serializePostMarkdown(parsed.frontmatter, parsed.body);
    expect(serialized).toContain("summary: \"Custom summary.\"");
    expect(serialized).toContain("categories:\n  - \"Long Form\"");
    expect(serialized).toContain("syndication:\n  mastodon:\n    status: published\n    url: https://example.com/post");
  });

  it("preserves nested syndication results while saving Writer edits", () => {
    const markdown = buildPostMarkdown({
      title: "A Post",
      slug: "a-post",
      status: "published",
      body: "Updated",
      existingMarkdown: "---\ntitle: \"A Post\"\ndate: 2026-05-01T10:00:00.000Z\nsyndication:\n  mastodon:\n    status: published\n    url: https://example.com/post\n---\n\nBody",
      now: new Date("2026-05-11T10:00:00.000Z")
    });
    expect(markdown).toContain("syndication:\n  mastodon:\n    status: published\n    url: https://example.com/post");
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
    expect(postExcerpt("First line\nSecond line")).toBe("First line");
    expect(postExcerpt("📍 New York, USA 📷 iPhone 16 Pro <img src=\"/media/img0931.jpeg\"")).toBe("New York, USA iPhone 16 Pro");
    expect(postExcerpt("![](/media/a.jpg)\n  ✨ A note after an image")).toBe("A note after an image");
    expect(postExcerpt("This is a deliberately long note line that should be shortened before it creates too much noise in the Writer list.")).toBe("This is a deliberately long note line that should be shortened before it create…");
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

  it("decides Writer editor target control visibility from status and config", () => {
    expect(shouldShowSyndicationTargets("draft", ["mastodon"])).toBe(true);
    expect(shouldShowSyndicationTargets("published", ["mastodon"])).toBe(false);
    expect(shouldShowSyndicationTargets("draft", [])).toBe(false);
    expect(shouldShowCategoryTargets(["Photography"])).toBe(true);
    expect(shouldShowCategoryTargets([])).toBe(false);
  });

  it("loads configured and unmanaged Writer targets from frontmatter", () => {
    expect(syndicationTargetsFromFrontmatter(undefined, ["mastodon", "bluesky"])).toEqual(["mastodon", "bluesky"]);
    expect(syndicationTargetsFromFrontmatter(["mastodon", "unknown"], ["mastodon", "bluesky"])).toEqual(["mastodon"]);
    expect(categoriesFromFrontmatter(["Photography", "Travel"], ["Photography"])).toEqual(["Photography"]);
    expect(unmanagedCategoriesFromFrontmatter(["Photography", "Travel"], ["Photography"])).toEqual(["Travel"]);
  });

  it("updates cached Writer post summaries without losing date ordering", () => {
    const older = { path: "content/posts/older.md", slug: "older", status: "published" as const, date: "2026-05-10T10:00:00.000Z", title: "Older" };
    const newer = { path: "content/posts/newer.md", slug: "newer", status: "published" as const, date: "2026-05-12T10:00:00.000Z", title: "Newer" };
    const middle = { path: "content/posts/middle.md", slug: "middle", status: "draft" as const, date: "2026-05-11T10:00:00.000Z", title: "Middle" };
    expect(upsertPostSummary([older, newer], middle).map((post) => post.slug)).toEqual(["newer", "middle", "older"]);
    expect(upsertPostSummary([older], { ...older, title: "Updated" })).toEqual([{ ...older, title: "Updated" }]);
    expect(removePostSummary([older, newer], newer.path)?.map((post) => post.slug)).toEqual(["older"]);
  });

  it("marks Writer post summary caches stale after the refresh window", () => {
    expect(isPostSummaryCacheStale(undefined, 1_000, 300)).toBe(true);
    expect(isPostSummaryCacheStale(800, 1_000, 300)).toBe(false);
    expect(isPostSummaryCacheStale(700, 1_000, 300)).toBe(true);
  });

  it("updates cached Writer post files by path", () => {
    const post = { path: "content/posts/post.md", slug: "post", status: "published" as const, content: "Body" };
    expect(upsertPostFile({}, post, 1_000)).toEqual({ [post.path]: { post, loadedAt: 1_000 } });
    expect(removePostFile({ [post.path]: { post, loadedAt: 1_000 } }, post.path)).toEqual({});
    expect(isPostFileCacheStale(undefined, 1_000, 300)).toBe(true);
    expect(isPostFileCacheStale({ post, loadedAt: 800 }, 1_000, 300)).toBe(false);
    expect(isPostFileCacheStale({ post, loadedAt: 700 }, 1_000, 300)).toBe(true);
  });
});
