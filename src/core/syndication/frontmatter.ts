import matter from "gray-matter";

export function updateSyndicationFrontmatter(
  markdown: string,
  provider: string,
  result: Record<string, unknown>
): string {
  const parsed = matter(markdown);
  const data = { ...parsed.data };
  const syndication = typeof data.syndication === "object" && data.syndication
    ? { ...data.syndication as Record<string, unknown> }
    : {};
  syndication[provider] = result;
  data.syndication = syndication;
  const nextFrontmatter = matter.stringify(parsed.content, data).trimEnd();
  return `${nextFrontmatter}\n`;
}
