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

  it("keeps dark mode support in public style surfaces", async () => {
    const root = process.cwd();
    const docsBuilder = await fs.readFile(path.join(root, "scripts/build-docs.mjs"), "utf8");
    const defaultLayout = await fs.readFile(path.join(root, "src/core/templates/defaults/layout.liquid"), "utf8");
    const writerCss = await fs.readFile(path.join(root, "src/writer/app/styles/writer.css"), "utf8");
    for (const source of [docsBuilder, defaultLayout, writerCss]) {
      expect(source).toContain("color-scheme: light dark");
      expect(source).toContain("@media (prefers-color-scheme: dark)");
    }
  });

  it("renders docs command and code fences with enhanced blocks", async () => {
    const docsBuilder = await fs.readFile(path.join(process.cwd(), "scripts/build-docs.mjs"), "utf8");
    expect(docsBuilder).toContain("terminal-block");
    expect(docsBuilder).toContain("source-block");
    expect(docsBuilder).toContain("syntax-keyword");
    expect(docsBuilder).toContain("window-dots");
  });
});
