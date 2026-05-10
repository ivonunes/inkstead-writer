import path from "node:path";
import { existsSync } from "node:fs";
import type { InksteadConfig, SyndicationProviderName } from "../config/types.js";
import { writeFileEnsured } from "../../utils/fs.js";

export type NewPostKind = "article" | "note";

export interface CreatePostOptions {
  kind: NewPostKind;
  title?: string;
  text?: string;
  date?: Date;
}

export interface CreatePostResult {
  path: string;
  relativePath: string;
  content: string;
}

function pad(value: number): string {
  return String(value).padStart(2, "0");
}

function localIso(date: Date): string {
  const offsetMinutes = -date.getTimezoneOffset();
  const sign = offsetMinutes >= 0 ? "+" : "-";
  const absoluteOffset = Math.abs(offsetMinutes);
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}${sign}${pad(Math.floor(absoluteOffset / 60))}:${pad(absoluteOffset % 60)}`;
}

function slugify(value: string): string {
  return value
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "")
    .slice(0, 80);
}

function noteSlug(text: string, date: Date): string {
  const words = text.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
  return slugify(words.split(" ").slice(0, 8).join(" ")) || `${pad(date.getHours())}${pad(date.getMinutes())}${pad(date.getSeconds())}`;
}

function quoteYaml(value: string): string {
  return JSON.stringify(value);
}

function textSyndicationProviders(config: InksteadConfig): SyndicationProviderName[] {
  return (config.syndication?.providers ?? []).filter((provider) => provider !== "flickr");
}

function frontmatter(fields: Array<[string, string]>, syndication: SyndicationProviderName[]): string {
  const lines = fields.map(([key, value]) => `${key}: ${value}`);
  if (syndication.length > 0) {
    lines.push("syndicate:", ...syndication.map((provider) => `  - ${provider}`));
  }
  return `---\n${lines.join("\n")}\n---`;
}

function uniquePath(root: string, relativePath: string): string {
  if (!existsSync(path.join(root, relativePath))) return relativePath;
  const extension = path.extname(relativePath);
  const base = relativePath.slice(0, -extension.length);
  for (let index = 2; index < 1000; index += 1) {
    const candidate = `${base}-${index}${extension}`;
    if (!existsSync(path.join(root, candidate))) return candidate;
  }
  throw new Error(`Could not find an available filename for ${relativePath}.`);
}

export async function createPost(root: string, config: InksteadConfig, options: CreatePostOptions): Promise<CreatePostResult> {
  const date = options.date ?? new Date();
  const datePrefix = `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
  const syndication = textSyndicationProviders(config);
  const postsDir = config.content.posts;

  const title = options.title?.trim();
  const text = options.text?.trim();
  if (options.kind === "article" && !title) throw new Error("Article posts require a title.");
  if (options.kind === "note" && !text) throw new Error("Note posts require text.");

  const slug = options.kind === "article" ? slugify(title ?? "") : noteSlug(text ?? "", date);
  const filename = `${datePrefix}-${slug || "post"}.md`;
  const relativePath = uniquePath(root, path.join(postsDir, filename));
  const body = options.kind === "note" ? `${text}\n` : "\n";
  const fields: Array<[string, string]> = options.kind === "article"
    ? [["title", quoteYaml(title ?? "")], ["date", localIso(date)]]
    : [["date", localIso(date)]];
  const content = `${frontmatter(fields, syndication)}\n\n${body}`;
  const absolutePath = path.join(root, relativePath);
  await writeFileEnsured(absolutePath, content);
  return { path: absolutePath, relativePath, content };
}
