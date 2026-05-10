import { promises as fs } from "node:fs";
import path from "node:path";
import sharp from "sharp";
import type { InksteadConfig } from "../config/types.js";

export interface ImageOptimizationOptions {
  enabled: boolean;
  maxWidth: number;
  maxHeight: number;
  quality: number;
}

const imageExtensions = new Set([".jpg", ".jpeg", ".png", ".webp", ".avif"]);

export function imageOptimizationOptions(config: InksteadConfig): ImageOptimizationOptions {
  const configured = config.photos;
  return {
    enabled: configured?.optimize ?? true,
    maxWidth: configured?.maxWidth ?? 2400,
    maxHeight: configured?.maxHeight ?? 2400,
    quality: configured?.quality ?? 82
  };
}

async function imagePaths(root: string): Promise<string[]> {
  const entries = await fs.readdir(root, { withFileTypes: true }).catch(() => []);
  const paths = await Promise.all(entries.map(async (entry) => {
    const entryPath = path.join(root, entry.name);
    if (entry.isDirectory()) return imagePaths(entryPath);
    if (entry.isFile() && imageExtensions.has(path.extname(entry.name).toLowerCase())) return [entryPath];
    return [];
  }));
  return paths.flat();
}

async function optimizeImage(file: string, options: ImageOptimizationOptions): Promise<void> {
  const extension = path.extname(file).toLowerCase();
  let image = sharp(file, { animated: false }).rotate().resize({
    width: options.maxWidth,
    height: options.maxHeight,
    fit: "inside",
    withoutEnlargement: true
  });

  if (extension === ".jpg" || extension === ".jpeg") {
    image = image.jpeg({ quality: options.quality, mozjpeg: true });
  } else if (extension === ".png") {
    image = image.png({ compressionLevel: 9, effort: 10 });
  } else if (extension === ".webp") {
    image = image.webp({ quality: options.quality });
  } else if (extension === ".avif") {
    image = image.avif({ quality: options.quality });
  }

  const optimized = await image.toBuffer().catch(() => undefined);
  if (!optimized) return;
  await fs.writeFile(file, optimized);
}

export async function optimizeBuiltImages(root: string, config: InksteadConfig): Promise<void> {
  const options = imageOptimizationOptions(config);
  if (!options.enabled) return;
  const files = await imagePaths(root);
  await Promise.all(files.map((file) => optimizeImage(file, options)));
}
