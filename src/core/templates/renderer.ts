import { existsSync } from "node:fs";
import path from "node:path";
import { Liquid } from "liquidjs";
import type { InksteadConfig } from "../config/types.js";
import type { CategoryCollection, NormalizedPage, NormalizedPost } from "../content/types.js";

export interface PaginationData {
  current: number;
  total: number;
  title?: string;
  previousUrl?: string;
  nextUrl?: string;
}

export interface TemplateCollections {
  allPosts: NormalizedPost[];
  pages: NormalizedPage[];
  categories: CategoryCollection[];
  photoPosts: NormalizedPost[];
}

export interface TemplateRenderer {
  home(posts: NormalizedPost[], pagination: PaginationData, title: string): Promise<string>;
  category(category: CategoryCollection, posts: NormalizedPost[], pagination: PaginationData): Promise<string>;
  post(post: NormalizedPost): Promise<string>;
  page(page: NormalizedPage): Promise<string>;
}

function titleForPost(post: NormalizedPost): string {
  return post.title ?? (post.kind === "photo-note" ? "Photo note" : "Note");
}

function dateDisplay(date: Date): string {
  return date.toLocaleDateString("en-GB");
}

function categorySlug(category: string): string {
  return category.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
}

function plainTextFromHtml(html: string): string {
  return html
    .replace(/<(br|\/p|\/div|\/li|\/h[1-6]|\/blockquote)\b[^>]*>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function serializePost(post: NormalizedPost): Record<string, unknown> {
  return {
    ...post,
    displayTitle: titleForPost(post),
    excerpt: post.excerpt,
    hasMore: post.hasMore,
    dateIso: post.date.toISOString(),
    dateDisplay: dateDisplay(post.date),
    lastmodIso: post.lastmod?.toISOString(),
    lastmodDisplay: post.lastmod ? dateDisplay(post.lastmod) : undefined,
    categoryLinks: post.categories.map((name) => ({ name, slug: categorySlug(name), url: `/categories/${categorySlug(name)}/` })),
    previous: post.previous ? { title: titleForPost(post.previous), urlPath: post.previous.urlPath } : undefined,
    next: post.next ? { title: titleForPost(post.next), urlPath: post.next.urlPath } : undefined
  };
}

function serializeCollections(collections: TemplateCollections): Record<string, unknown> {
  return {
    posts: collections.allPosts.map(serializePost),
    pages: collections.pages,
    categories: collections.categories,
    photoPosts: collections.photoPosts.map(serializePost)
  };
}

export function createTemplateRenderer(root: string, config: InksteadConfig, collections: TemplateCollections): TemplateRenderer {
  const defaultDir = path.join(import.meta.dirname, "defaults");
  const themeDir = path.join(root, config.theme?.path ?? "theme");
  const engine = new Liquid({
    root: existsSync(themeDir) ? [themeDir, defaultDir] : [defaultDir],
    extname: ".liquid",
    jsTruthy: true
  });

  async function renderBody(template: string, context: Record<string, unknown>): Promise<string> {
    const fullContext = {
      site: config.site,
      config,
      collections: serializeCollections(collections),
      posts: collections.allPosts.map(serializePost),
      pages: collections.pages,
      categories: collections.categories,
      photoPosts: collections.photoPosts.map(serializePost),
      now: {
        year: new Date().getFullYear()
      },
      ...context
    };
    const content = await engine.renderFile(template, fullContext);
    if (/<!doctype html/i.test(content)) return content;
    return engine.renderFile("layout", { ...fullContext, content });
  }

  function pageTemplate(page: NormalizedPage): string {
    const candidate = `${page.slug}.liquid`;
    return existsSync(path.join(themeDir, candidate)) ? page.slug : "page";
  }

  function meta(title: string, canonicalUrl: string, description = config.site.description): Record<string, string | undefined> {
    return {
      title: title === config.site.title ? title : `${title} - ${config.site.title}`,
      canonicalUrl,
      description
    };
  }

  function metaDescriptionForPost(post: NormalizedPost): string | undefined {
    return plainTextFromHtml(post.excerpt) || config.site.description;
  }

  return {
    home: (posts, pagination, title) => renderBody("home", {
      title,
      posts: posts.map(serializePost),
      pages: collections.pages,
      categories: collections.categories,
      photoPosts: collections.photoPosts.map(serializePost),
      pagination,
      meta: meta(title, config.site.url)
    }),
    category: (category, posts, pagination) => renderBody("category", {
      title: `#${category.name}`,
      category,
      posts: posts.map(serializePost),
      pages: collections.pages,
      categories: collections.categories,
      photoPosts: collections.photoPosts.map(serializePost),
      pagination,
      meta: meta(`#${category.name}`, `${config.site.url.replace(/\/$/, "")}${category.urlPath}`)
    }),
    post: (post) => renderBody("post", {
      post: serializePost(post),
      meta: meta(titleForPost(post), post.canonicalUrl, metaDescriptionForPost(post))
    }),
    page: (page) => renderBody(pageTemplate(page), {
      page,
      meta: meta(page.title, page.canonicalUrl)
    })
  };
}
