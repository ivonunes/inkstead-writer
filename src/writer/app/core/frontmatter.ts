export interface RawFrontmatterBlock {
  raw: string[];
}

export type FrontmatterValue = string | string[] | RawFrontmatterBlock | undefined;
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
  const lines = rawFrontmatter ? rawFrontmatter.split("\n") : [];
  for (let index = 0; index < lines.length; index += 1) {
    const match = lines[index].match(/^([A-Za-z0-9_-]+):\s*(.*)$/);
    if (!match) continue;
    const key = match[1];
    const value = match[2] ?? "";
    const trimmed = value.trim();
    if (trimmed === "[]") {
      frontmatter[key] = [];
      continue;
    }
    if (trimmed !== "") {
      frontmatter[key] = unquote(value);
      continue;
    }
    const block: string[] = [];
    while (index + 1 < lines.length && /^\s+/.test(lines[index + 1])) {
      index += 1;
      block.push(lines[index]);
    }
    frontmatter[key] = block.length > 0 && block.every((line) => /^\s*-\s*/.test(line))
      ? block.map((line) => unquote(line.replace(/^\s*-\s*/, "")))
      : { raw: block };
  }

  const bodyStart = markdown.slice(end + 4).replace(/^\n+/, "");
  return { frontmatter, body: bodyStart };
}

export function serializePostMarkdown(frontmatter: WriterFrontmatter, body: string): string {
  const lines = Object.entries(frontmatter)
    .filter((entry): entry is [string, string | string[] | RawFrontmatterBlock] => {
      if (typeof entry[1] === "string") return entry[1].length > 0;
      return Array.isArray(entry[1]) || Boolean(entry[1] && typeof entry[1] === "object" && "raw" in entry[1]);
    })
    .flatMap(([key, value]) => {
      if (Array.isArray(value)) return value.length > 0 ? [`${key}:`, ...value.map((item) => `  - ${quote(item)}`)] : [`${key}: []`];
      if (typeof value === "object" && "raw" in value) return [`${key}:`, ...value.raw];
      return [`${key}: ${quote(value)}`];
    });
  return `---\n${lines.join("\n")}\n---\n\n${body.replace(/^\n+/, "")}`;
}
