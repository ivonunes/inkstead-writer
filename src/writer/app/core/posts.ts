import { parsePostMarkdown, serializePostMarkdown, type WriterFrontmatter } from "./frontmatter.js";

export type PostStatus = "draft" | "published";

export interface PostSummary {
  path: string;
  slug: string;
  title?: string;
  excerpt?: string;
  status: PostStatus;
  date?: string;
  updatedAt?: string;
}

export interface PostFile extends PostSummary {
  content: string;
  sha?: string;
}

export function slugifyTitle(title: string): string {
  return title
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/&/g, " and ")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80)
    .replace(/-+$/g, "");
}

function datePrefix(now = new Date()): string {
  const pad = (value: number) => String(value).padStart(2, "0");
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
}

function timeSuffix(now = new Date()): string {
  const pad = (value: number) => String(value).padStart(2, "0");
  return `${pad(now.getHours())}${pad(now.getMinutes())}`;
}

export function slugForNewPost(title: string | undefined, body = "", now = new Date()): string {
  const text = title?.trim() || postExcerpt(body, 80) || `untitled-${timeSuffix(now)}`;
  return `${datePrefix(now)}-${slugifyTitle(text) || `untitled-${timeSuffix(now)}`}`;
}

export function postPath(contentPath: string, slug: string): string {
  return `${contentPath.replace(/\/+$/g, "")}/${slug}.md`;
}

export function filenameSlug(filePath: string): string {
  return filePath.split("/").pop()?.replace(/\.md$/i, "") ?? filePath;
}

export function summarizePost(path: string, markdown: string): PostSummary {
  const parsed = parsePostMarkdown(markdown);
  const slug = parsed.frontmatter.slug || filenameSlug(path);
  const status = parsed.frontmatter.status === "draft" ? "draft" : "published";
  return {
    path,
    slug,
    title: parsed.frontmatter.title,
    excerpt: postExcerpt(parsed.body),
    status,
    date: parsed.frontmatter.date,
    updatedAt: parsed.frontmatter.updated_at
  };
}

export function postDateSortValue(post: Pick<PostSummary, "date" | "updatedAt">): string {
  return post.date ?? post.updatedAt ?? "";
}

export function postExcerpt(markdown: string, maxLength = 120): string | undefined {
  const text = markdown
    .replace(/\r?\n+/g, " ")
    .replace(/!\[[^\]]*]\([^)]*\)/g, "")
    .replace(/<img\b[^>]*(?:>|$)/gi, "")
    .replace(/\[([^\]]+)]\([^)]*\)/g, "$1")
    .replace(/<[^>]+>/g, " ")
    .replace(/[`*_>#-]/g, "")
    .replace(/\s+/g, " ")
    .trim();
  if (!text) return undefined;
  return text.length > maxLength ? `${text.slice(0, maxLength - 1).trimEnd()}…` : text;
}

export function postListLabel(post: Pick<PostSummary, "title" | "excerpt">): string {
  return post.title?.trim() || post.excerpt || "Untitled";
}

export function postStatusLabel(status: PostStatus): string {
  return status === "draft" ? "Draft" : "Published";
}

export function formatPostDate(value: string | undefined, locale?: string | string[]): string | undefined {
  if (!value) return undefined;
  const date = new Date(value);
  if (Number.isNaN(date.valueOf())) return value;
  return new Intl.DateTimeFormat(locale, { dateStyle: "medium" }).format(date);
}

export function buildPostMarkdown(options: {
  title?: string;
  slug: string;
  status: PostStatus;
  body: string;
  existingMarkdown?: string;
  updateDate?: boolean;
  now?: Date;
}): string {
  const parsed = options.existingMarkdown ? parsePostMarkdown(options.existingMarkdown) : { frontmatter: {}, body: "" };
  const now = (options.now ?? new Date()).toISOString();
  const frontmatter: WriterFrontmatter = {
    ...parsed.frontmatter,
    title: options.title?.trim() || undefined,
    slug: undefined,
    status: options.status === "draft" ? "draft" : undefined,
    date: options.updateDate ? now : parsed.frontmatter.date,
    updated_at: now
  };
  return serializePostMarkdown(frontmatter, options.body);
}
