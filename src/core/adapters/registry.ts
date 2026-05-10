import type { CiProviderName, DeployProviderName, InksteadConfig, SyndicationProviderName } from "../config/types.js";
import type { AdapterRequirement, CiProvider, DeploymentProvider, SyndicationProvider } from "./types.js";
import { githubActionsProvider } from "../../adapters/ci/github-actions.js";
import { gitlabCiProvider } from "../../adapters/ci/gitlab-ci.js";
import { cloudflareWorkersProvider } from "../../adapters/deploy/cloudflare-workers.js";
import { githubPagesProvider } from "../../adapters/deploy/github-pages.js";
import { gitlabPagesProvider } from "../../adapters/deploy/gitlab-pages.js";
import { mastodonProvider } from "../../adapters/syndication/mastodon.js";
import { blueskyProvider } from "../../adapters/syndication/bluesky.js";
import { flickrProvider } from "../../adapters/syndication/flickr.js";

export const ciProviders: Record<CiProviderName, CiProvider> = {
  "github-actions": githubActionsProvider,
  "gitlab-ci": gitlabCiProvider
};

export const deployProviders: Record<DeployProviderName, DeploymentProvider> = {
  "cloudflare-workers": cloudflareWorkersProvider,
  "github-pages": githubPagesProvider,
  "gitlab-pages": gitlabPagesProvider
};

export const syndicationProviders: Record<SyndicationProviderName, SyndicationProvider> = {
  mastodon: mastodonProvider,
  bluesky: blueskyProvider,
  flickr: flickrProvider
};

export function requirementsForConfig(config: InksteadConfig): AdapterRequirement[] {
  const requirements: AdapterRequirement[] = [];
  if (config.ci) requirements.push(...ciProviders[config.ci.provider].requirements());
  if (config.deploy) requirements.push(...deployProviders[config.deploy.provider].requirements());
  for (const provider of config.syndication?.providers ?? []) {
    requirements.push(...syndicationProviders[provider].requirements());
  }
  return requirements;
}

export function uniqueEnvironmentVariables(config: InksteadConfig): string[] {
  return [...new Set(requirementsForConfig(config).map((item) => item.environmentVariable).filter((item): item is string => Boolean(item)))];
}
