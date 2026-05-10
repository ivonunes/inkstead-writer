import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import sharp from "sharp";
import { mimeFromPath } from "../../utils/mime.js";

export interface PreparedMedia {
  path: string;
  bytes: Buffer;
  mimeType: string;
  filename: string;
  generated: boolean;
}

export interface MediaLimit {
  maxBytes: number;
  maxDimension?: number;
}

const jpegQualities = [88, 82, 76, 70, 64, 58, 52, 46, 40];

async function writeDerivative(source: string, buffer: Buffer, suffix: string): Promise<string> {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "inkstead-media-"));
  const name = `${path.basename(source, path.extname(source))}-${suffix}.jpg`;
  const destination = path.join(dir, name);
  await fs.writeFile(destination, buffer);
  return destination;
}

async function optimize(source: string, limit: MediaLimit): Promise<PreparedMedia | undefined> {
  let image = sharp(source, { animated: false }).rotate();
  if (limit.maxDimension) {
    image = image.resize({
      width: limit.maxDimension,
      height: limit.maxDimension,
      fit: "inside",
      withoutEnlargement: true
    });
  }

  for (const quality of jpegQualities) {
    const bytes = await image.clone().jpeg({ quality, mozjpeg: true }).toBuffer();
    if (bytes.byteLength <= limit.maxBytes) {
      const derivative = await writeDerivative(source, bytes, `${limit.maxBytes}-${quality}`);
      return {
        path: derivative,
        bytes,
        mimeType: "image/jpeg",
        filename: path.basename(derivative),
        generated: true
      };
    }
  }
  return undefined;
}

async function withinOriginalLimits(source: string, bytes: Buffer, mimeType: string, limit: MediaLimit): Promise<boolean> {
  if (bytes.byteLength > limit.maxBytes || !mimeType.startsWith("image/")) return false;
  if (!limit.maxDimension) return true;
  const metadata = await sharp(source, { animated: false }).metadata();
  const width = metadata.width ?? 0;
  const height = metadata.height ?? 0;
  return width <= limit.maxDimension && height <= limit.maxDimension;
}

export async function prepareImageForSyndication(source: string, limit: MediaLimit): Promise<PreparedMedia> {
  const original = await fs.readFile(source);
  const originalMime = mimeFromPath(source);
  if (await withinOriginalLimits(source, original, originalMime, limit)) {
    return {
      path: source,
      bytes: original,
      mimeType: originalMime,
      filename: path.basename(source),
      generated: false
    };
  }

  const optimized = await optimize(source, limit);
  if (!optimized) {
    throw new Error(`Could not compress ${path.basename(source)} below ${limit.maxBytes} bytes.`);
  }
  return optimized;
}
