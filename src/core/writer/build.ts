import { promises as fs } from "node:fs";
import path from "node:path";
import type { InksteadConfig } from "../config/types.js";
import { ensureDir, writeFileEnsured } from "../../utils/fs.js";
import { resolveWriterConfig } from "./config.js";

export interface CopyWriterAppOptions {
  writerDist?: string;
}

function defaultWriterDist(): string {
  return path.resolve(import.meta.dirname, "../../writer/dist");
}

function outputPath(dist: string, writerPath: string): string {
  const relative = writerPath.replace(/^\/+/, "");
  return path.join(dist, relative);
}

export async function copyWriterApp(dist: string, config: InksteadConfig, options: CopyWriterAppOptions = {}): Promise<void> {
  const writer = resolveWriterConfig(config);
  if (!writer) return;

  const source = options.writerDist ?? defaultWriterDist();
  const destination = outputPath(dist, writer.path);
  const indexFile = path.join(source, "index.html");
  await fs.access(indexFile).catch(() => {
    throw new Error(`Inkstead Writer is enabled, but the prebuilt Writer app was not found at ${source}. Run the package build so build:writer runs first.`);
  });

  await ensureDir(destination);
  await fs.cp(source, destination, { recursive: true, force: true });
  await writeFileEnsured(
    path.join(destination, "inkstead-writer.config.json"),
    `${JSON.stringify(writer.publicConfig, null, 2)}\n`
  );
}
