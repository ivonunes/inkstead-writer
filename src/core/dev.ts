import { createServer } from "node:http";
import { promises as fs } from "node:fs";
import path from "node:path";
import chokidar from "chokidar";
import type { InksteadConfig } from "./config/types.js";
import { buildSite } from "./build/build.js";
import { handleWriterLocalApi } from "./writer/local-api.js";

export function contentType(file: string): string {
  if (file.endsWith(".html")) return "text/html; charset=utf-8";
  if (file.endsWith(".js") || file.endsWith(".mjs")) return "text/javascript; charset=utf-8";
  if (file.endsWith(".css")) return "text/css";
  if (file.endsWith(".json")) return "application/json";
  if (file.endsWith(".xml")) return "application/xml";
  if (file.endsWith(".jpg") || file.endsWith(".jpeg")) return "image/jpeg";
  if (file.endsWith(".png")) return "image/png";
  return "application/octet-stream";
}

export async function devServer(root: string, config: InksteadConfig, port = 4321): Promise<void> {
  const devConfig = localWriterConfig(config);
  await buildSite(root, devConfig);
  const dist = path.join(root, devConfig.build?.output ?? "dist");
  chokidar.watch([path.join(root, "content"), path.join(root, "site.config.ts")], { ignoreInitial: true })
    .on("all", () => buildSite(root, devConfig).catch((error) => console.error(error)));
  createServer(async (request, response) => {
    const url = new URL(request.url ?? "/", "http://localhost");
    if (await handleWriterLocalApi(request, response, root, devConfig)) return;
    const filePath = path.join(dist, staticFilePath(url.pathname));
    try {
      const body = await fs.readFile(filePath);
      response.writeHead(200, { "content-type": contentType(filePath) });
      response.end(body);
    } catch {
      response.writeHead(404);
      response.end("Not found");
    }
  }).listen(port, () => console.log(`Inkstead dev server running at http://localhost:${port}`));
}

export function staticFilePath(urlPathname: string): string {
  const clean = urlPathname.replace(/^\/+/, "");
  if (!clean || clean.endsWith("/")) return `${clean}index.html`;
  if (!path.extname(clean)) return `${clean}/index.html`;
  return clean;
}

export function localWriterConfig(config: InksteadConfig): InksteadConfig {
  if (!config.writer?.enabled) return config;
  return {
    ...config,
    writer: {
      ...config.writer,
      provider: "local"
    }
  };
}
