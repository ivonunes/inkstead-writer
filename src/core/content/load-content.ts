import path from "node:path";
import { existsSync } from "node:fs";
import type { InksteadConfig, SyndicationProviderName } from "../config/types.js";
import type { CategoryCollection, NormalizedPage, NormalizedPost, ParsedMarkdown, PostKind } from "./types.js";
import { listMarkdownFiles } from "../../utils/fs.js";
import { parseMarkdownFile, renderMarkdown } from "./markdown.js";

function cleanBaseUrl(url: string): string {
  return url.replace(/\/$/, "");
}

function asStringArray(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

function asCategories(value: unknown): string[] {
  if (typeof value === "string") return [value].filter(Boolean);
  return asStringArray(value).map((category) => category.trim()).filter(Boolean);
}

function titleizeCategory(segment: string): string {
  return segment
    .replace(/[-_]+/g, " ")
    .trim()
    .replace(/\s+/g, " ")
    .replace(/\b\w/g, (char) => char.toUpperCase());
}

function directoryCategories(file: string, root: string, config: InksteadConfig): string[] {
  const postsRoot = path.join(root, config.content.posts);
  const relativeDir = path.relative(postsRoot, path.dirname(file));
  if (!relativeDir || relativeDir === ".") return [];
  return relativeDir
    .split(path.sep)
    .filter((segment) => segment && segment !== "..")
    .map(titleizeCategory);
}

function uniqueCategories(categories: string[]): string[] {
  const seen = new Set<string>();
  const output: string[] = [];
  for (const category of categories) {
    const key = slugifyCategory(category);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    output.push(category);
  }
  return output;
}

export function slugifyCategory(category: string): string {
  return category.trim().toLowerCase().replace(/&/g, " and ").replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
}

function asProviderArray(value: unknown): SyndicationProviderName[] {
  const allowed = new Set(["mastodon", "bluesky", "flickr"]);
  return asStringArray(value).filter((item): item is SyndicationProviderName => allowed.has(item));
}

function imagesFromBody(body: string): string[] {
  const images = [
    ...body.matchAll(/!\[[^\]]*\]\(([^)\s]+)(?:\s+["'][^"']*["'])?\)/g),
    ...body.matchAll(/<img[^>]+src=["']([^"']+)["']/gi)
  ].map((match) => match[1]).filter(Boolean);
  return [...new Set(images)];
}

function firstImageFromBody(body: string): string | undefined {
  return imagesFromBody(body)[0];
}

function imageExtension(image: string): string {
  const clean = image.split(/[?#]/)[0] ?? image;
  return path.extname(clean).toLowerCase();
}

export function isGalleryPhotoPost(post: NormalizedPost): boolean {
  if (post.kind !== "photo-note") return false;
  const image = post.firstImage ?? post.photos[0];
  return imageExtension(image ?? "") !== ".png";
}

function dateParts(date: Date): { year: string; month: string; day: string } {
  return {
    year: String(date.getFullYear()),
    month: String(date.getMonth() + 1).padStart(2, "0"),
    day: String(date.getDate()).padStart(2, "0")
  };
}

function slugWithoutDate(slug: string): string {
  return slug.replace(/^\d{4}-\d{2}-\d{2}-/, "");
}

function postUrlPath(parsed: ParsedMarkdown, config: InksteadConfig, date: Date): string {
  if (typeof parsed.frontmatter.url === "string") return parsed.frontmatter.url;
  const slug = slugWithoutDate(parsed.slug);
  if ((config.urls?.posts ?? "dated") === "slug") return `/posts/${slug}/`;
  const { year, month, day } = dateParts(date);
  return `/${year}/${month}/${day}/${slug}/`;
}

function inferKind(parsed: ParsedMarkdown): PostKind {
  const hasTitle = typeof parsed.frontmatter.title === "string" && parsed.frontmatter.title.length > 0;
  const photos = asStringArray(parsed.frontmatter.photos);
  const bodyImages = imagesFromBody(parsed.body);
  if (hasTitle) return "article";
  if (photos.length > 0 || bodyImages.length > 0) return "photo-note";
  return "note";
}

function isRemoteImage(ref: string): boolean {
  return /^https?:\/\//i.test(ref);
}

function sourcePhotoPath(ref: string, parsed: ParsedMarkdown, config: InksteadConfig, root: string): string | undefined {
  if (isRemoteImage(ref)) return undefined;
  if (ref.startsWith("/photos/")) return path.join(root, config.content.photos, ref.replace(/^\/photos\//, ""));
  if (ref.startsWith("/")) return path.join(root, ref.replace(/^\//, ""));
  if (ref.startsWith(`${config.content.photos}/`)) return path.join(root, ref);

  const contentPhotoPath = path.join(root, config.content.photos, ref);
  if (existsSync(contentPhotoPath)) return contentPhotoPath;

  return path.resolve(path.dirname(parsed.path), ref);
}

function sourcePhotoPaths(refs: string[], parsed: ParsedMarkdown, config: InksteadConfig, root: string): string[] {
  const seen = new Set<string>();
  const output: string[] = [];
  for (const ref of refs) {
    const source = sourcePhotoPath(ref, parsed, config, root);
    if (!source || seen.has(source)) continue;
    seen.add(source);
    output.push(source);
  }
  return output;
}

function addImageClass(html: string, className: string): string {
  return html.replace(/<img\b([^>]*)>/gi, (match, attrs: string) => {
    const classMatch = attrs.match(/\sclass=(["'])(.*?)\1/i);
    if (!classMatch) return `<img class="${className}"${attrs}>`;
    const existing = classMatch[2].split(/\s+/).filter(Boolean);
    if (existing.includes(className)) return match;
    return match.replace(classMatch[0], ` class=${classMatch[1]}${[...existing, className].join(" ")}${classMatch[1]}`);
  });
}

function syndicationUrls(value: unknown): string[] {
  if (Array.isArray(value)) return value.filter((item): item is string => typeof item === "string");
  if (typeof value === "object" && value) {
    return Object.values(value as Record<string, Record<string, unknown>>)
      .map((item) => item?.url)
      .filter((item): item is string => typeof item === "string");
  }
  return [];
}

function stripHtml(value: string): string {
  return value.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
}

const voidHtmlTags = new Set(["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"]);

function htmlTagName(tag: string): string | undefined {
  return tag.match(/^<\/?\s*([a-zA-Z][\w:-]*)/)?.[1]?.toLowerCase();
}

function truncateHtmlWords(html: string, count: number): { html: string; text: string; truncated: boolean } {
  const openTags: string[] = [];
  let output = "";
  let words = 0;
  let truncated = false;
  const tokens = html.match(/<[^>]+>|[^<]+/g) ?? [];

  for (const token of tokens) {
    if (token.startsWith("<")) {
      if (token.startsWith("<!--")) {
        output += token;
        continue;
      }

      const name = htmlTagName(token);
      output += token;

      if (!name || voidHtmlTags.has(name) || /\/>\s*$/.test(token)) continue;
      if (token.startsWith("</")) {
        const index = openTags.lastIndexOf(name);
        if (index >= 0) openTags.splice(index, 1);
      } else {
        openTags.push(name);
      }
      continue;
    }

    for (const part of token.match(/\s+|\S+/g) ?? []) {
      if (!/\S/.test(part)) {
        if (words > 0) output += part;
        continue;
      }
      if (words >= count) {
        truncated = true;
        break;
      }
      output += part;
      words += 1;
    }

    if (truncated) break;
  }

  if (truncated) {
    output = `${output.trimEnd()}…`;
    for (const tag of openTags.reverse()) output += `</${tag}>`;
  }

  return {
    html: output,
    text: stripHtml(output),
    truncated
  };
}

function removeExcerptMedia(html: string): string {
  return html
    .replace(/<img\b[^>]*>/gi, "")
    .replace(/<video\b[\s\S]*?<\/video>/gi, "")
    .replace(/<audio\b[\s\S]*?<\/audio>/gi, "")
    .replace(/<figure\b[\s\S]*?<\/figure>/gi, "");
}

function excerptData(parsed: ParsedMarkdown, config: InksteadConfig, wordLimit = 70): { summary?: string; excerpt: string; hasMore: boolean } {
  const summary = typeof parsed.frontmatter.summary === "string" ? parsed.frontmatter.summary.trim() : undefined;
  const body = parsed.body.trim();
  const moreIndex = body.indexOf("<!--more-->");
  const source = summary || (moreIndex >= 0 ? body.slice(0, moreIndex).trim() : body);
  const sourceHtml = summary || moreIndex >= 0 ? renderMarkdown(source, config) : removeExcerptMedia(renderMarkdown(source, config));
  const fullText = stripHtml(removeExcerptMedia(renderMarkdown(body.replace("<!--more-->", ""), config)));
  const excerpt = truncateHtmlWords(sourceHtml, wordLimit);
  return {
    summary,
    excerpt: excerpt.html,
    hasMore: Boolean(moreIndex >= 0 || excerpt.truncated || excerpt.text !== fullText)
  };
}

export function normalizePost(parsed: ParsedMarkdown, config: InksteadConfig, root = process.cwd()): NormalizedPost {
  if (!parsed.frontmatter.date) {
    throw new Error(`${parsed.path} is missing required date frontmatter.`);
  }
  const date = new Date(String(parsed.frontmatter.date));
  if (Number.isNaN(date.valueOf())) {
    throw new Error(`${parsed.path} has an invalid date.`);
  }
  const lastmod = parsed.frontmatter.lastmod ? new Date(String(parsed.frontmatter.lastmod)) : undefined;
  const urlPath = postUrlPath(parsed, config, date);
  const kind = inferKind(parsed);
  const frontmatterPhotos = asStringArray(parsed.frontmatter.photos);
  const bodyImages = imagesFromBody(parsed.body);
  const firstImage = bodyImages[0] ?? frontmatterPhotos[0];
  const sourcePhotos = sourcePhotoPaths([...frontmatterPhotos, ...bodyImages], parsed, config, root);
  const excerpt = excerptData(parsed, config);
  const syndication = typeof parsed.frontmatter.syndication === "object" && parsed.frontmatter.syndication && !Array.isArray(parsed.frontmatter.syndication)
    ? parsed.frontmatter.syndication as Record<string, Record<string, unknown>>
    : {};
  return {
    ...parsed,
    kind,
    html: kind === "photo-note" ? addImageClass(parsed.html, "u-photo") : parsed.html,
    title: typeof parsed.frontmatter.title === "string" ? parsed.frontmatter.title : undefined,
    summary: excerpt.summary,
    excerpt: excerpt.excerpt,
    hasMore: excerpt.hasMore,
    date,
    lastmod: lastmod && !Number.isNaN(lastmod.valueOf()) ? lastmod : undefined,
    urlPath,
    canonicalUrl: `${cleanBaseUrl(config.site.url)}${urlPath}`,
    photos: frontmatterPhotos,
    sourcePhotos,
    firstImage,
    alt: typeof parsed.frontmatter.alt === "string" ? parsed.frontmatter.alt : undefined,
    categories: uniqueCategories([
      ...directoryCategories(parsed.path, root, config),
      ...asCategories(parsed.frontmatter.categories ?? parsed.frontmatter.category)
    ]),
    syndicate: asProviderArray(parsed.frontmatter.syndicate),
    syndication,
    syndicationUrls: syndicationUrls(parsed.frontmatter.syndication)
  };
}

export function groupPostsByCategory(posts: NormalizedPost[]): CategoryCollection[] {
  const categoryMap = new Map<string, CategoryCollection>();
  for (const post of posts) {
    for (const category of post.categories) {
      const slug = slugifyCategory(category);
      if (!slug) continue;
      const existing = categoryMap.get(slug);
      if (existing) {
        existing.posts.push(post);
      } else {
        categoryMap.set(slug, {
          name: category,
          slug,
          urlPath: `/categories/${slug}/`,
          feedPath: `/categories/${slug}/feed.xml`,
          posts: [post]
        });
      }
    }
  }
  return [...categoryMap.values()].sort((a, b) => a.name.localeCompare(b.name));
}

export function normalizePage(parsed: ParsedMarkdown, config: InksteadConfig): NormalizedPage {
  const title = typeof parsed.frontmatter.title === "string" ? parsed.frontmatter.title : parsed.slug;
  const urlPath = `/${parsed.slug}/`;
  return {
    ...parsed,
    title,
    urlPath,
    canonicalUrl: `${cleanBaseUrl(config.site.url)}${urlPath}`
  };
}

export async function loadPosts(root: string, config: InksteadConfig): Promise<NormalizedPost[]> {
  const files = await listMarkdownFiles(path.join(root, config.content.posts));
  const posts = (await Promise.all(files.map(async (file) => normalizePost(await parseMarkdownFile(file, config), config, root))))
    .sort((a, b) => b.date.valueOf() - a.date.valueOf());
  posts.forEach((post, index) => {
    post.next = index > 0 ? posts[index - 1] : undefined;
    post.previous = index < posts.length - 1 ? posts[index + 1] : undefined;
  });
  return posts;
}

export async function loadPages(root: string, config: InksteadConfig): Promise<NormalizedPage[]> {
  const files = await listMarkdownFiles(path.join(root, config.content.pages));
  return Promise.all(files.map(async (file) => normalizePage(await parseMarkdownFile(file, config), config)));
}

export async function loadContent(root: string, config: InksteadConfig): Promise<{
  posts: NormalizedPost[];
  pages: NormalizedPage[];
  photoPosts: NormalizedPost[];
  categories: CategoryCollection[];
}> {
  const [posts, pages] = await Promise.all([loadPosts(root, config), loadPages(root, config)]);
  return {
    posts,
    pages,
    photoPosts: posts.filter(isGalleryPhotoPost),
    categories: groupPostsByCategory(posts)
  };
}
