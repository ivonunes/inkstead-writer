import type { WriterPublicConfig } from "../core/config.js";
import { GitHubRepositoryAdapter } from "./github.js";
import { GitLabRepositoryAdapter } from "./gitlab.js";
import { LocalRepositoryAdapter } from "./local.js";
import type { RepositoryAdapter } from "./types.js";

export function createRepositoryAdapter(config: WriterPublicConfig, token: string): RepositoryAdapter {
  if (config.provider === "local") return new LocalRepositoryAdapter();
  if (config.provider === "gitlab") return new GitLabRepositoryAdapter(config, token);
  return new GitHubRepositoryAdapter(config, token);
}
