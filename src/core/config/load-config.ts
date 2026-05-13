import { pathToFileURL } from "node:url";
import { existsSync } from "node:fs";
import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import ts from "typescript";
import { z } from "zod";
import type { InksteadConfig } from "./types.js";

const configSchema = z.object({
  site: z.object({
    title: z.string().min(1),
    url: z.string().url(),
    author: z.string().min(1),
    description: z.string().optional(),
    lang: z.string().optional(),
    timezone: z.string().optional(),
    email: z.string().optional(),
    avatar: z.string().optional(),
    bio: z.string().optional(),
    navigation: z.array(z.object({
      name: z.string(),
      url: z.string(),
      icon: z.string().optional(),
      className: z.string().optional()
    })).optional(),
    social: z.array(z.object({
      name: z.string(),
      url: z.string(),
      relMe: z.boolean().optional(),
      icon: z.string().optional(),
      className: z.string().optional()
    })).optional()
  }),
  content: z.object({
    posts: z.string().default("content/posts"),
    pages: z.string().default("content/pages"),
    media: z.string().default("content/media")
  }).transform((content) => ({
    ...content
  })),
  build: z.object({ output: z.string().optional() }).optional(),
  hooks: z.object({
    beforeBuild: z.array(z.string()).optional(),
    afterBuild: z.array(z.string()).optional()
  }).optional(),
  urls: z.object({ posts: z.enum(["dated", "slug"]).optional() }).optional(),
  markdown: z.object({ html: z.boolean().optional(), breaks: z.boolean().optional() }).optional(),
  assets: z.object({
    passthrough: z.array(z.object({ from: z.string(), to: z.string().optional() })).optional()
  }).optional(),
  photos: z.object({
    optimize: z.boolean().optional(),
    maxWidth: z.number().int().positive().optional(),
    maxHeight: z.number().int().positive().optional(),
    quality: z.number().int().min(1).max(100).optional()
  }).optional(),
  theme: z.object({
    path: z.string().optional(),
    showPoweredBy: z.boolean().optional()
  }).optional(),
  pagination: z.object({ postsPerPage: z.number().int().positive().optional() }).optional(),
  feeds: z.object({ limit: z.number().int().positive().optional() }).optional(),
  writer: z.object({
    enabled: z.boolean().optional(),
    path: z.string().min(1).optional(),
    provider: z.enum(["github", "gitlab", "local"]),
    owner: z.string().min(1).optional(),
    repo: z.string().min(1).optional(),
    branch: z.string().min(1).optional(),
    categories: z.array(z.string().min(1)).refine((items) => new Set(items).size === items.length, "Writer categories must be unique.").optional()
  }).strict().optional(),
  ci: z.object({ provider: z.enum(["github-actions", "gitlab-ci"]) }).optional(),
  deploy: z.discriminatedUnion("provider", [
    z.object({ provider: z.literal("cloudflare-workers"), projectName: z.string().min(1) }),
    z.object({ provider: z.literal("github-pages"), projectName: z.string().optional() }),
    z.object({ provider: z.literal("gitlab-pages"), projectName: z.string().optional() })
  ]).optional(),
  syndication: z.object({
    providers: z.array(z.enum(["mastodon", "bluesky", "flickr"]))
  }).optional()
}).superRefine((config, ctx) => {
  if (config.deploy?.provider === "github-pages" && config.ci?.provider !== "github-actions") {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["ci", "provider"],
      message: "GitHub Pages deployment requires GitHub Actions CI."
    });
  }
  if (config.deploy?.provider === "gitlab-pages" && config.ci?.provider !== "gitlab-ci") {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["ci", "provider"],
      message: "GitLab Pages deployment requires GitLab CI."
    });
  }
  if (config.writer?.enabled && config.writer.provider !== "local") {
    for (const field of ["owner", "repo", "branch"] as const) {
      if (!config.writer[field]) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          path: ["writer", field],
          message: `Remote Writer provider requires ${field}.`
        });
      }
    }
  }
});

export async function loadConfig(root = process.cwd()): Promise<InksteadConfig> {
  const configPath = path.join(root, "site.config.ts");
  if (!existsSync(configPath)) {
    throw new Error("site.config.ts was not found.");
  }

  const source = await fs.readFile(configPath, "utf8");
  let transpiled = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.ES2022, target: ts.ScriptTarget.ES2022 }
  }).outputText;
  transpiled = transpiled
    .replace(/import\s+\{\s*defineConfig\s*\}\s+from\s+["']inkstead["'];?/g, "const defineConfig = (config) => config;")
    .replaceAll("from \"inkstead\"", `from ${JSON.stringify(pathToFileURL(path.join(import.meta.dirname, "../../index.js")).href)}`);
  const tempFile = path.join(os.tmpdir(), `inkstead-config-${Date.now()}-${Math.random().toString(16).slice(2)}.mjs`);
  await fs.writeFile(tempFile, transpiled);
  const mod = await import(pathToFileURL(tempFile).href);
  return configSchema.parse(mod.default);
}
