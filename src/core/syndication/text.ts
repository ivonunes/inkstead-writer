import MarkdownIt from "markdown-it";
import type { NormalizedPost } from "../content/types.js";

const renderer = new MarkdownIt({
  html: true,
  breaks: true,
  linkify: true,
  typographer: false
});

function htmlToText(html: string): string {
  return html
    .replace(/<a\b[^>]*href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi, (_, href: string, label: string) => {
      const text = htmlToText(label).trim();
      return text && text !== href ? `${text} (${href})` : href;
    })
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/p>/gi, "\n\n")
    .replace(/<[^>]+>/g, "")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, "\"")
    .replace(/&#39;/g, "'");
}

function sameLinkText(label: string, href: string): boolean {
  return label.trim().replace(/\/$/, "") === href.trim().replace(/\/$/, "");
}

function attr(token: { attrGet(name: string): string | null }, name: string): string | undefined {
  return token.attrGet(name) ?? undefined;
}

function renderInline(tokens: unknown[], start = 0, stopType?: string): { text: string; index: number } {
  let output = "";
  let index = start;

  while (index < tokens.length) {
    const token = tokens[index] as {
      type: string;
      content?: string;
      children?: unknown[];
      attrGet(name: string): string | null;
    };

    if (stopType && token.type === stopType) return { text: output, index };

    switch (token.type) {
      case "text":
      case "code_inline":
        output += token.content ?? "";
        break;
      case "softbreak":
      case "hardbreak":
        output += "\n";
        break;
      case "html_inline":
        output += htmlToText(token.content ?? "");
        break;
      case "image":
        break;
      case "link_open": {
        const href = attr(token, "href");
        const rendered = renderInline(tokens, index + 1, "link_close");
        const label = rendered.text.trim();
        output += href && label && !sameLinkText(label, href) ? `${label} (${href})` : (label || href || "");
        index = rendered.index;
        break;
      }
      default:
        if (token.children) output += renderInline(token.children).text;
        else if (token.content) output += token.content;
        break;
    }

    index += 1;
  }

  return { text: output, index };
}

export function markdownToSyndicationText(markdown: string): string {
  const blocks: string[] = [];
  for (const token of renderer.parse(markdown, {})) {
    if (token.type === "inline") {
      const text = renderInline(token.children ?? []).text.trim();
      if (text) blocks.push(text);
    } else if (token.type === "fence" || token.type === "code_block") {
      const text = token.content.trim();
      if (text) blocks.push(text);
    } else if (token.type === "html_block") {
      const text = htmlToText(token.content).trim();
      if (text) blocks.push(text);
    }
  }

  return blocks
    .join("\n\n")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

export function textForSyndication(post: NormalizedPost): string {
  if (post.title) return `${post.title}\n${post.canonicalUrl}`;
  return markdownToSyndicationText(post.body);
}
