export type FrontmatterValue = string | string[] | undefined;
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
  let currentListKey: string | undefined;
  for (const line of rawFrontmatter.split("\n")) {
    const item = line.match(/^\s*-\s*(.*)$/);
    if (item && currentListKey) {
      const list = frontmatter[currentListKey];
      frontmatter[currentListKey] = [...(Array.isArray(list) ? list : []), unquote(item[1] ?? "")];
      continue;
    }
    const match = line.match(/^([A-Za-z0-9_-]+):\s*(.*)$/);
    if (!match) continue;
    const value = match[2] ?? "";
    const trimmed = value.trim();
    if (trimmed === "[]") {
      currentListKey = undefined;
      frontmatter[match[1]] = [];
      continue;
    }
    currentListKey = trimmed === "" ? match[1] : undefined;
    frontmatter[match[1]] = currentListKey ? [] : unquote(value);
  }

  const bodyStart = markdown.slice(end + 4).replace(/^\n+/, "");
  return { frontmatter, body: bodyStart };
}

export function serializePostMarkdown(frontmatter: WriterFrontmatter, body: string): string {
  const lines = Object.entries(frontmatter)
    .filter((entry): entry is [string, string | string[]] => {
      if (typeof entry[1] === "string") return entry[1].length > 0;
      return Array.isArray(entry[1]);
    })
    .flatMap(([key, value]) => Array.isArray(value)
      ? value.length > 0 ? [`${key}:`, ...value.map((item) => `  - ${quote(item)}`)] : [`${key}: []`]
      : [`${key}: ${quote(value)}`]);
  return `---\n${lines.join("\n")}\n---\n\n${body.replace(/^\n+/, "")}`;
}
