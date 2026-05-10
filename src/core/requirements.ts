import type { InksteadConfig } from "./config/types.js";
import { ciProviders, deployProviders, requirementsForConfig, syndicationProviders } from "./adapters/registry.js";

export function renderRequirements(config: InksteadConfig): string {
  const lines = ["This site is configured to use:", ""];
  lines.push("CI", `- ${config.ci ? ciProviders[config.ci.provider].name : "None"}`, "");
  lines.push("Deployment");
  if (config.deploy) lines.push(`- ${deployProviders[config.deploy.provider].name}`);
  lines.push("", "Syndication");
  for (const provider of config.syndication?.providers ?? []) lines.push(`- ${syndicationProviders[provider].name}`);
  lines.push("", "Required local environment variables:", "");
  for (const requirement of requirementsForConfig(config).filter((item) => item.environmentVariable)) {
    lines.push(`- ${requirement.environmentVariable}`);
  }
  lines.push("", "For local publishing, add these to .env.", "For CI publishing, add the same names as secrets or variables.");
  return `${lines.join("\n")}\n`;
}
