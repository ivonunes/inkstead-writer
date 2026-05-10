import { existsSync } from "node:fs";
import path from "node:path";
import dotenv from "dotenv";
import type { InksteadConfig } from "../config/types.js";
import type { DoctorCheck } from "../adapters/types.js";
import { ciProviders, deployProviders, requirementsForConfig } from "../adapters/registry.js";
import { loadPosts } from "../content/load-content.js";

function mark(check: DoctorCheck): string {
  const icon = check.status === "pass" ? "✓" : check.status === "warn" ? "!" : "✗";
  return `${icon} ${check.label}${check.message ? ` (${check.message})` : ""}`;
}

export async function runDoctor(root: string, config: InksteadConfig): Promise<{ output: string; issues: number }> {
  dotenv.config({ path: path.join(root, ".env") });
  const hasEnv = existsSync(path.join(root, ".env"));
  const checks: DoctorCheck[] = [
    { status: existsSync(path.join(root, "site.config.ts")) ? "pass" : "fail", label: "site.config.ts found" },
    ...Object.values(config.content).map((dir) => ({ status: existsSync(path.join(root, dir)) ? "pass" : "fail", label: `${dir} found` }) as DoctorCheck),
    { status: hasEnv ? "pass" : "warn", label: hasEnv ? ".env loaded" : ".env not found" }
  ];
  for (const requirement of requirementsForConfig(config)) {
    if (requirement.environmentVariable) {
      checks.push({ status: process.env[requirement.environmentVariable] ? "pass" : "fail", label: `${requirement.environmentVariable} is ${process.env[requirement.environmentVariable] ? "set" : "missing"}` });
    }
  }
  if (config.ci) checks.push(...await ciProviders[config.ci.provider].doctor({ root, env: process.env }));
  if (config.deploy) checks.push(...await deployProviders[config.deploy.provider].doctor({ root, env: process.env }));
  try {
    await loadPosts(root, config);
  } catch (error) {
    checks.push({ status: "fail", label: error instanceof Error ? error.message : "content validation failed" });
  }
  const issues = checks.filter((check) => check.status === "fail").length;
  const next = checks.filter((check) => check.status === "fail").map((check) => `- Fix: ${check.label}`);
  return {
    issues,
    output: `Checking site...

${checks.map(mark).join("\n")}

Result
${issues} ${issues === 1 ? "issue" : "issues"} found.
${next.length ? `\nNext steps:\n${next.join("\n")}` : ""}\n`
  };
}
