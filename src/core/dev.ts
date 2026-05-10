import { createServer } from "node:http";
import { promises as fs } from "node:fs";
import path from "node:path";
import chokidar from "chokidar";
import type { InksteadConfig } from "./config/types.js";
import { buildSite } from "./build/build.js";

function contentType(file: string): string {
  if (file.endsWith(".html")) return "text/html; charset=utf-8";
  if (file.endsWith(".css")) return "text/css";
  if (file.endsWith(".json")) return "application/json";
  if (file.endsWith(".xml")) return "application/xml";
  if (file.endsWith(".jpg") || file.endsWith(".jpeg")) return "image/jpeg";
  if (file.endsWith(".png")) return "image/png";
  return "application/octet-stream";
}

export async function devServer(root: string, config: InksteadConfig, port = 4321): Promise<void> {
  await buildSite(root, config);
  const dist = path.join(root, "dist");
  chokidar.watch([path.join(root, "content"), path.join(root, "site.config.ts")], { ignoreInitial: true })
    .on("all", () => buildSite(root, config).catch((error) => console.error(error)));
  createServer(async (request, response) => {
    const url = new URL(request.url ?? "/", "http://localhost");
    const filePath = path.join(dist, url.pathname.endsWith("/") ? url.pathname.slice(1) + "index.html" : url.pathname.slice(1));
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
