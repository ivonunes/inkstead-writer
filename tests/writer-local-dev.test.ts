import { promises as fs } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { loadConfig } from "../src/index.js";
import { contentType, localWriterConfig, staticFilePath } from "../src/core/dev.js";
import { previewTitle } from "../src/writer/app/routes/Preview.js";
import { localApi } from "./helpers/local-api.js";
import { useSiteFixture } from "./helpers/site.js";

const fixture = useSiteFixture();

describe("writer local dev", () => {
  it("overrides Writer to the local provider in the dev server", async () => {
    const site = await fixture.makeSite();
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
    const site = await fixture.makeSite();
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
    const content = "---\ntitle: Local\nslug: local\ndate: 2026-05-11T10:00:00.000Z\nstatus: draft\nsyndicate:\n  - mastodon\ncategories:\n  - Photography\nupdated_at: 2026-05-11T10:00:00.000Z\n---\n\nBody\n\n![](/media/photo.jpg)";
    const save = await localApi("PUT", "/__inkstead-writer/api/post", { path: "content/posts/local.md", content }, site, config);
    expect(save.status).toBe(200);
    expect(await fs.readFile(path.join(site, "content/posts/local.md"), "utf8")).toBe(content);
    expect(await fs.readFile(path.join(site, "content/posts/local.md"), "utf8")).toContain("categories:\n  - Photography");
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
