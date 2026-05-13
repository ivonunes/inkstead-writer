import { promises as fs } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

async function markdownFiles(root: string): Promise<string[]> {
  const entries = await fs.readdir(root, { withFileTypes: true });
  const files = await Promise.all(entries.map(async (entry) => {
    const fullPath = path.join(root, entry.name);
    if (entry.isDirectory()) return markdownFiles(fullPath);
    return entry.isFile() && entry.name.endsWith(".md") ? [fullPath] : [];
  }));
  return files.flat();
}

describe("docs", () => {
  it("keeps referenced docs assets present", async () => {
    const docsRoot = path.join(process.cwd(), "docs");
    const files = await markdownFiles(docsRoot);
    const missing: string[] = [];
    for (const file of files) {
      const markdown = await fs.readFile(file, "utf8");
      for (const match of markdown.matchAll(/!\[[^\]]*]\((\/assets\/[^)]+)\)/g)) {
        const assetPath = path.join(docsRoot, match[1].replace(/^\//, ""));
        try {
          await fs.access(assetPath);
        } catch {
          missing.push(`${path.relative(docsRoot, file)} -> ${match[1]}`);
        }
      }
    }
    expect(missing).toEqual([]);
  });
});
