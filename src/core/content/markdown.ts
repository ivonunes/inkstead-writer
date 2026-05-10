import { promises as fs } from "node:fs";
import matter from "gray-matter";
import MarkdownIt from "markdown-it";
import type { ParsedMarkdown } from "./types.js";
import { slugFromFile } from "../../utils/fs.js";
import type { InksteadConfig } from "../config/types.js";

function markdownRenderer(config?: InksteadConfig): MarkdownIt {
  return new MarkdownIt({
    html: config?.markdown?.html ?? true,
    breaks: config?.markdown?.breaks ?? true,
    linkify: true,
    typographer: true
  });
}

export async function parseMarkdownFile(file: string, config?: InksteadConfig): Promise<ParsedMarkdown> {
  const raw = await fs.readFile(file, "utf8");
  const parsed = matter(raw);
  return {
    path: file,
    slug: slugFromFile(file),
    frontmatter: parsed.data,
    body: parsed.content,
    html: markdownRenderer(config).render(parsed.content)
  };
}

export function renderMarkdown(markdown: string, config?: InksteadConfig): string {
  return markdownRenderer(config).render(markdown);
}
