import type { InksteadConfig, PublicWriterConfig } from "../config/types.js";

export interface ResolvedWriterConfig {
  enabled: boolean;
  path: string;
  publicConfig: PublicWriterConfig;
}

export function normalizeWriterPath(value = "/writer"): string {
  const trimmed = value.trim();
  const withLeadingSlash = trimmed.startsWith("/") ? trimmed : `/${trimmed}`;
  return withLeadingSlash.replace(/\/+$/g, "") || "/writer";
}

export function publicWriterConfig(config: InksteadConfig): PublicWriterConfig | undefined {
  if (!config.writer?.enabled) return undefined;
  return {
    provider: config.writer.provider,
    owner: config.writer.owner,
    repo: config.writer.repo,
    branch: config.writer.branch,
    instanceUrl: config.writer.instanceUrl,
    postsPath: config.content.posts,
    mediaPath: config.content.media,
    syndicationProviders: config.syndication?.providers ?? [],
    categories: config.writer.categories ?? []
  };
}

export function resolveWriterConfig(config: InksteadConfig): ResolvedWriterConfig | undefined {
  const writer = config.writer;
  const publicConfig = publicWriterConfig(config);
  if (!writer?.enabled || !publicConfig) return undefined;
  return {
    enabled: true,
    path: normalizeWriterPath(writer.path),
    publicConfig
  };
}
