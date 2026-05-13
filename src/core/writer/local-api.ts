import type { IncomingMessage, ServerResponse } from "node:http";
import { createHash } from "node:crypto";
import { promises as fs } from "node:fs";
import path from "node:path";
import matter from "gray-matter";
import type { InksteadConfig } from "../config/types.js";
import { ensureDir, listMarkdownFiles } from "../../utils/fs.js";

interface LocalAsset {
  path: string;
  name: string;
  sha?: string;
}

function json(response: ServerResponse, status: number, body: unknown): void {
  response.writeHead(status, { "content-type": "application/json" });
  response.end(JSON.stringify(body));
}

async function readJson<T>(request: IncomingMessage): Promise<T> {
  const chunks: Buffer[] = [];
  for await (const chunk of request) chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  return JSON.parse(Buffer.concat(chunks).toString("utf8")) as T;
}

function cleanRelativePath(value: string): string {
  return value.replace(/^\/+/, "");
}

function safePath(root: string, base: string, value: string): string {
  const basePath = path.resolve(root, base);
  const fullPath = path.resolve(root, cleanRelativePath(value));
  if (fullPath !== basePath && !fullPath.startsWith(`${basePath}${path.sep}`)) {
    throw new Error("Path is outside the configured Writer directory.");
  }
  return fullPath;
}

function relative(root: string, file: string): string {
  return path.relative(root, file).split(path.sep).join("/");
}

function sha(content: Buffer | string): string {
  return createHash("sha1").update(content).digest("hex");
}

async function fileExists(file: string): Promise<boolean> {
  return fs.access(file).then(() => true, () => false);
}

function summarizePost(filePath: string, content: string): Record<string, unknown> {
  const parsed = matter(content);
  const slug = typeof parsed.data.slug === "string" ? parsed.data.slug : path.basename(filePath, ".md");
  return {
    path: filePath,
    slug,
    title: typeof parsed.data.title === "string" ? parsed.data.title : undefined,
    excerpt: postExcerpt(parsed.content),
    status: parsed.data.status === "draft" ? "draft" : "published",
    date: frontmatterDate(parsed.data.date),
    updatedAt: frontmatterDate(parsed.data.updated_at)
  };
}

function frontmatterDate(value: unknown): string | undefined {
  if (typeof value === "string") return value;
  if (value instanceof Date && !Number.isNaN(value.valueOf())) return value.toISOString();
  return undefined;
}

function postExcerpt(markdown: string, maxLength = 80): string | undefined {
  const text = markdown
    .split(/\r?\n/)
    .map((line) => line
      .replace(/!\[[^\]]*]\([^)]*\)/g, "")
      .replace(/<img\b[^>]*(?:>|$)/gi, "")
      .replace(/\[([^\]]+)]\([^)]*\)/g, "$1")
      .replace(/<[^>]+>/g, " ")
      .replace(/[`*_>#-]/g, "")
      .replace(/[\p{Extended_Pictographic}\u{1F1E6}-\u{1F1FF}\uFE0F\u200D]/gu, "")
      .replace(/\s+/g, " ")
      .trim())
    .find((line) => line.length > 0);
  if (!text) return undefined;
  return text.length > maxLength ? `${text.slice(0, maxLength - 1).trimEnd()}…` : text;
}

async function listAssets(root: string, config: InksteadConfig, folderPath: string): Promise<LocalAsset[]> {
  const folder = safePath(root, config.content.media, folderPath);
  const entries = await fs.readdir(folder, { withFileTypes: true }).catch(() => []);
  const output: LocalAsset[] = [];
  for (const entry of entries) {
    if (!entry.isFile()) continue;
    const fullPath = path.join(folder, entry.name);
    const body = await fs.readFile(fullPath);
    output.push({ path: relative(root, fullPath), name: entry.name, sha: sha(body) });
  }
  return output.sort((a, b) => a.path.localeCompare(b.path));
}

export async function handleWriterLocalApi(request: IncomingMessage, response: ServerResponse, root: string, config: InksteadConfig): Promise<boolean> {
  const url = new URL(request.url ?? "/", "http://localhost");
  if (!url.pathname.startsWith("/__inkstead-writer/api/")) return false;
  if (config.writer?.provider !== "local") {
    json(response, 404, { error: "Local Writer API is available only when writer.provider is local." });
    return true;
  }

  try {
    const route = url.pathname.replace("/__inkstead-writer/api", "");
    if (request.method === "GET" && route === "/validate") {
      await fs.access(path.join(root, config.content.posts));
      json(response, 200, { ok: true });
      return true;
    }

    if (request.method === "GET" && route === "/posts") {
      const files = await listMarkdownFiles(path.join(root, config.content.posts));
      const posts = await Promise.all(files.map(async (file) => {
        const content = await fs.readFile(file, "utf8");
        return summarizePost(relative(root, file), content);
      }));
      posts.sort((a, b) => String(b.date ?? b.updatedAt ?? "").localeCompare(String(a.date ?? a.updatedAt ?? "")));
      json(response, 200, posts);
      return true;
    }

    if (request.method === "GET" && route === "/post") {
      const postPath = url.searchParams.get("path");
      if (!postPath) throw new Error("Missing post path.");
      const file = safePath(root, config.content.posts, postPath);
      const content = await fs.readFile(file, "utf8");
      json(response, 200, { ...summarizePost(relative(root, file), content), content, sha: sha(content) });
      return true;
    }

    if (request.method === "PUT" && route === "/post") {
      const change = await readJson<{ path: string; content: string; sha?: string; media?: Array<{ path: string; contentBase64: string }> }>(request);
      const file = safePath(root, config.content.posts, change.path);
      if (!change.sha && await fileExists(file)) throw new Error(`${change.path} already exists.`);
      for (const asset of change.media ?? []) {
        const assetFile = safePath(root, config.content.media, asset.path);
        await ensureDir(path.dirname(assetFile));
        await fs.writeFile(assetFile, Buffer.from(asset.contentBase64, "base64"), { flag: "wx" });
      }
      await ensureDir(path.dirname(file));
      await fs.writeFile(file, change.content);
      json(response, 200, { sha: sha(change.content) });
      return true;
    }

    if (request.method === "DELETE" && route === "/post") {
      const change = await readJson<{ path: string; mediaPaths?: string[] }>(request);
      await fs.rm(safePath(root, config.content.posts, change.path), { force: true });
      for (const assetPath of change.mediaPaths ?? []) await fs.rm(safePath(root, config.content.media, assetPath), { force: true });
      json(response, 200, { ok: true });
      return true;
    }

    if (request.method === "GET" && route === "/assets") {
      const folder = url.searchParams.get("folder");
      if (!folder) throw new Error("Missing asset folder.");
      json(response, 200, await listAssets(root, config, folder));
      return true;
    }

    if (request.method === "PUT" && route === "/asset") {
      const asset = await readJson<{ path: string; contentBase64: string }>(request);
      const file = safePath(root, config.content.media, asset.path);
      const body = Buffer.from(asset.contentBase64, "base64");
      await ensureDir(path.dirname(file));
      await fs.writeFile(file, body, { flag: "wx" });
      json(response, 200, { path: relative(root, file), name: path.basename(file), sha: sha(body) });
      return true;
    }

    if (request.method === "DELETE" && route === "/assets") {
      const payload = await readJson<{ paths: string[] }>(request);
      for (const assetPath of payload.paths) await fs.rm(safePath(root, config.content.media, assetPath), { force: true });
      json(response, 200, { ok: true });
      return true;
    }

    json(response, 404, { error: "Writer local API route was not found." });
  } catch (error) {
    json(response, 400, { error: error instanceof Error ? error.message : "Writer local API failed." });
  }
  return true;
}
