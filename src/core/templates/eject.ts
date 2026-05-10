import { existsSync, promises as fs } from "node:fs";
import path from "node:path";
import { ensureDir } from "../../utils/fs.js";

const templateNames = ["layout.liquid", "home.liquid", "category.liquid", "post.liquid", "page.liquid"];

export async function ejectTheme(root: string, options: { force?: boolean } = {}): Promise<{ copied: string[]; skipped: string[] }> {
  const sourceDir = path.join(import.meta.dirname, "defaults");
  const themeDir = path.join(root, "theme");
  const copied: string[] = [];
  const skipped: string[] = [];

  await ensureDir(themeDir);
  for (const name of templateNames) {
    const destination = path.join(themeDir, name);
    if (!options.force && existsSync(destination)) {
      skipped.push(path.join("theme", name));
      continue;
    }
    await fs.copyFile(path.join(sourceDir, name), destination);
    copied.push(path.join("theme", name));
  }

  return { copied, skipped };
}
