import type { InksteadConfig } from "./config/types.js";
import { ciProviders, deployProviders, requirementsForConfig, syndicationProviders } from "./adapters/registry.js";

const useColor = Boolean(process.stdout.isTTY && !process.env.NO_COLOR);
const colors = {
  reset: "\x1b[0m",
  bold: "\x1b[1m",
  dim: "\x1b[2m",
  blue: "\x1b[34m"
};

function style(value: string, code: string): string {
  return useColor ? `${code}${value}${colors.reset}` : value;
}

function row(label: string, value: string): string {
  return `  ${style(label.padEnd(14), colors.dim)} ${value}`;
}

export function renderRequirements(config: InksteadConfig): string {
  const syndication = config.syndication?.providers ?? [];
  const requirements = requirementsForConfig(config).filter((item) => item.environmentVariable);
  const lines = [style("Inkstead Requirements", colors.bold), ""];

  lines.push(style("Configured Adapters", colors.bold));
  lines.push(row("CI", config.ci ? ciProviders[config.ci.provider].name : "None"));
  lines.push(row("Deployment", config.deploy ? deployProviders[config.deploy.provider].name : "None"));
  lines.push(row("Syndication", syndication.length > 0 ? syndication.map((provider) => syndicationProviders[provider].name).join(", ") : "None"));

  lines.push("", style("Environment Variables", colors.bold));
  if (requirements.length === 0) {
    lines.push("  No local environment variables are required.");
  } else {
    const longestName = Math.max(...requirements.map((requirement) => requirement.environmentVariable?.length ?? 0));
    for (const requirement of requirements) {
      const name = requirement.environmentVariable ?? "";
      const description = requirement.description.replace(/\.$/, "");
      lines.push(`  ${style(name.padEnd(longestName), colors.blue)}  ${description}`);
    }
    lines.push("", style("Local Publishing", colors.bold));
    lines.push("  cp .env.example .env");
    lines.push("  Fill in the values, then run npm run doctor.");
    lines.push("", style("CI Publishing", colors.bold));
    lines.push("  Add the same names from .env.example as secrets or variables.");
  }
  return `${lines.join("\n")}\n`;
}
