export type FrontmatterValue = string | undefined;
export type WriterFrontmatter = Record<string, FrontmatterValue>;

export interface ParsedPostMarkdown {
  frontmatter: WriterFrontmatter;
  body: string;
}

function unquote(value: string): string {
  const trimmed = value.trim();
  if ((trimmed.startsWith('"') && trimmed.endsWith('"')) || (trimmed.startsWith("'") && trimmed.endsWith("'"))) {
    return trimmed.slice(1, -1);
  }
  return trimmed;
}

function quote(value: string): string {
  if (/^[a-z0-9._:/+-]+$/i.test(value)) return value;
  return JSON.stringify(value);
}

export function parsePostMarkdown(markdown: string): ParsedPostMarkdown {
  if (!markdown.startsWith("---\n")) return { frontmatter: {}, body: markdown };
  const end = markdown.indexOf("\n---", 4);
  if (end < 0) return { frontmatter: {}, body: markdown };

  const frontmatter: WriterFrontmatter = {};
  const rawFrontmatter = markdown.slice(4, end).trim();
  for (const line of rawFrontmatter.split("\n")) {
    const match = line.match(/^([A-Za-z0-9_-]+):\s*(.*)$/);
    if (!match) continue;
    frontmatter[match[1]] = unquote(match[2] ?? "");
  }

  const bodyStart = markdown.slice(end + 4).replace(/^\n+/, "");
  return { frontmatter, body: bodyStart };
}

export function serializePostMarkdown(frontmatter: WriterFrontmatter, body: string): string {
  const lines = Object.entries(frontmatter)
    .filter((entry): entry is [string, string] => typeof entry[1] === "string" && entry[1].length > 0)
    .map(([key, value]) => `${key}: ${quote(value)}`);
  return `---\n${lines.join("\n")}\n---\n\n${body.replace(/^\n+/, "")}`;
}
