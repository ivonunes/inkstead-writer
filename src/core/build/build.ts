import { promises as fs } from "node:fs";
import path from "node:path";
import type { InksteadConfig } from "../config/types.js";
import { groupPostsByCategory, isGalleryPhotoPost, loadPages, loadPosts } from "../content/load-content.js";
import { jsonFeed, rssFeed, sitemap } from "../feeds/feeds.js";
import { createTemplateRenderer, type TemplateRenderer } from "../templates/renderer.js";
import { ensureDir, writeFileEnsured } from "../../utils/fs.js";
import { runHookCommands } from "./hooks.js";
import { optimizeBuiltImages } from "./images.js";
import { copyWriterApp } from "../writer/build.js";

export async function buildSite(root: string, config: InksteadConfig): Promise<void> {
  await runHookCommands(config.hooks?.beforeBuild, root);
  const dist = path.join(root, config.build?.output ?? "dist");
  await fs.rm(dist, { recursive: true, force: true });
  await ensureDir(dist);
  const posts = await loadPosts(root, config);
  const pages = await loadPages(root, config);
  const categories = groupPostsByCategory(posts);
  const photoPosts = posts.filter(isGalleryPhotoPost);
  const renderer = createTemplateRenderer(root, config, { allPosts: posts, pages, categories, photoPosts });
  const postsPerPage = config.pagination?.postsPerPage ?? 20;

  await writePaginatedIndex({
    dist,
    config,
    renderer,
    pages,
    posts,
    postsPerPage,
    title: config.site.title,
    firstOutput: path.join(dist, "index.html"),
    pageOutput: (page) => path.join(dist, "page", String(page), "index.html"),
    pageUrl: (page) => page === 1 ? "/" : `/page/${page}/`
  });
  for (const category of categories) {
    await writePaginatedIndex({
      dist,
      config,
      renderer,
      pages,
      posts: category.posts,
      category,
      postsPerPage,
      title: `#${category.name}`,
      firstOutput: path.join(dist, category.urlPath, "index.html"),
      pageOutput: (page) => path.join(dist, "categories", category.slug, "page", String(page), "index.html"),
      pageUrl: (page) => page === 1 ? category.urlPath : `/categories/${category.slug}/page/${page}/`
    });
    await writeFileEnsured(path.join(dist, category.feedPath), rssFeed(config, category.posts, { title: `${config.site.title} - ${category.name}`, path: category.feedPath }));
  }
  for (const post of posts) {
    await writeFileEnsured(path.join(dist, post.urlPath, "index.html"), await renderer.post(post));
  }
  for (const page of pages) {
    await writeFileEnsured(path.join(dist, page.urlPath, "index.html"), await renderer.page(page));
  }

  await writeFileEnsured(path.join(dist, "feed.xml"), rssFeed(config, posts));
  await writeFileEnsured(path.join(dist, "feed.json"), jsonFeed(config, posts));
  await writeFileEnsured(path.join(dist, "sitemap.xml"), sitemap(config, [config.site.url, ...posts.map((post) => post.canonicalUrl), ...pages.map((page) => page.canonicalUrl), ...categories.map((category) => `${config.site.url.replace(/\/$/, "")}${category.urlPath}`)]));

  const mediaDir = path.join(root, config.content.media);
  await fs.cp(mediaDir, path.join(dist, "media"), { recursive: true, force: true }).catch(() => undefined);
  await optimizeBuiltImages(path.join(dist, "media"), config);
  for (const asset of config.assets?.passthrough ?? []) {
    await fs.cp(path.join(root, asset.from), path.join(dist, asset.to ?? "."), { recursive: true, force: true }).catch(() => undefined);
  }
  await copyWriterApp(dist, config);
  await runHookCommands(config.hooks?.afterBuild, root);
}

async function writePaginatedIndex(options: {
  dist: string;
  config: InksteadConfig;
  renderer: TemplateRenderer;
  pages: Awaited<ReturnType<typeof loadPages>>;
  posts: Awaited<ReturnType<typeof loadPosts>>;
  category?: ReturnType<typeof groupPostsByCategory>[number];
  postsPerPage: number;
  title: string;
  firstOutput: string;
  pageOutput: (page: number) => string;
  pageUrl: (page: number) => string;
}): Promise<void> {
  const pageCount = Math.max(1, Math.ceil(options.posts.length / options.postsPerPage));
  for (let page = 1; page <= pageCount; page += 1) {
    const pagePosts = options.posts.slice((page - 1) * options.postsPerPage, page * options.postsPerPage);
    const output = page === 1 ? options.firstOutput : options.pageOutput(page);
    const pagination = {
      current: page,
      total: pageCount,
      previousUrl: page > 1 ? options.pageUrl(page - 1) : undefined,
      nextUrl: page < pageCount ? options.pageUrl(page + 1) : undefined,
      title: options.title
    };
    const html = options.category
      ? await options.renderer.category(options.category, pagePosts, pagination)
      : await options.renderer.home(pagePosts, pagination, options.title);
    await writeFileEnsured(output, html);
  }
}
