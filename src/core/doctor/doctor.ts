import { existsSync } from "node:fs";
import path from "node:path";
import dotenv from "dotenv";
import type { InksteadConfig } from "../config/types.js";
import type { DoctorCheck } from "../adapters/types.js";
import { ciProviders, deployProviders, requirementsForConfig } from "../adapters/registry.js";
import { loadPosts } from "../content/load-content.js";
import { workflowUpgradePlan } from "../upgrade.js";

type DoctorGroup = {
  title: string;
  checks: DoctorCheck[];
};

const useColor = Boolean(process.stdout.isTTY && !process.env.NO_COLOR);
const colors = {
  reset: "\x1b[0m",
  bold: "\x1b[1m",
  dim: "\x1b[2m",
  green: "\x1b[32m",
  yellow: "\x1b[33m",
  red: "\x1b[31m"
};

function style(value: string, code: string): string {
  return useColor ? `${code}${value}${colors.reset}` : value;
}

function statusLabel(status: DoctorCheck["status"]): string {
  const label = status === "pass" ? "✓" : status === "warn" ? "!" : "×";
  if (status === "pass") return style(label, colors.green);
  if (status === "warn") return style(label, colors.yellow);
  return style(label, colors.red);
}

function renderCheck(check: DoctorCheck): string {
  return `  ${statusLabel(check.status)}  ${check.label}${check.message ? ` (${check.message})` : ""}`;
}

function renderGroup(group: DoctorGroup): string {
  return `${style(group.title, colors.bold)}\n${group.checks.map(renderCheck).join("\n")}`;
}

function plural(count: number, singular: string): string {
  return `${count} ${count === 1 ? singular : `${singular}s`}`;
}

export async function runDoctor(root: string, config: InksteadConfig): Promise<{ output: string; issues: number }> {
  dotenv.config({ path: path.join(root, ".env") });
  const hasEnv = existsSync(path.join(root, ".env"));
  const coreChecks: DoctorCheck[] = [
    { status: existsSync(path.join(root, "site.config.ts")) ? "pass" : "fail", label: "site.config.ts found" },
    ...Object.values(config.content).map((dir) => ({ status: existsSync(path.join(root, dir)) ? "pass" : "fail", label: `${dir} found` }) as DoctorCheck)
  ];
  const environmentChecks: DoctorCheck[] = [
    { status: hasEnv ? "pass" : "warn", label: hasEnv ? ".env loaded" : ".env not found" }
  ];
  for (const requirement of requirementsForConfig(config)) {
    if (requirement.environmentVariable) {
      environmentChecks.push({ status: process.env[requirement.environmentVariable] ? "pass" : "fail", label: `${requirement.environmentVariable} is ${process.env[requirement.environmentVariable] ? "set" : "missing"}` });
    }
  }
  const adapterChecks: DoctorCheck[] = [];
  if (config.ci) adapterChecks.push(...await ciProviders[config.ci.provider].doctor({ root, env: process.env }));
  if (config.deploy) adapterChecks.push(...await deployProviders[config.deploy.provider].doctor({ root, env: process.env }));
  const generatedFileChecks: DoctorCheck[] = [];
  for (const upgrade of await workflowUpgradePlan(root, config)) {
    if (upgrade.status === "changed") {
      generatedFileChecks.push({
        status: "warn",
        label: `${upgrade.path} differs from Inkstead's current template`,
        message: "run npm run upgrade"
      });
    }
  }
  const contentChecks: DoctorCheck[] = [];
  try {
    await loadPosts(root, config);
    contentChecks.push({ status: "pass", label: "content loaded" });
  } catch (error) {
    contentChecks.push({ status: "fail", label: error instanceof Error ? error.message : "content validation failed" });
  }
  const groups: DoctorGroup[] = [
    { title: "Core", checks: coreChecks },
    { title: "Environment", checks: environmentChecks },
    ...(adapterChecks.length > 0 ? [{ title: "Adapters", checks: adapterChecks }] : []),
    ...(generatedFileChecks.length > 0 ? [{ title: "Generated Files", checks: generatedFileChecks }] : []),
    { title: "Content", checks: contentChecks }
  ];
  const checks = groups.flatMap((group) => group.checks);
  const issues = checks.filter((check) => check.status === "fail").length;
  const warnings = checks.filter((check) => check.status === "warn").length;
  const passed = checks.filter((check) => check.status === "pass").length;
  const next = checks.filter((check) => check.status === "fail").map((check, index) => `  ${index + 1}. Fix ${check.label}`);
  return {
    issues,
    output: `${style("Inkstead Doctor", colors.bold)}

Summary
  ${statusLabel("pass")}  ${plural(passed, "check")} passed
  ${statusLabel("warn")}  ${plural(warnings, "warning")}
  ${statusLabel("fail")}  ${plural(issues, "issue")}

${groups.map(renderGroup).join("\n\n")}

Result
${issues === 0 ? "No blocking issues found." : `${plural(issues, "blocking issue")} found.`}
${next.length ? `\nNext steps:\n${next.join("\n")}` : ""}\n`
  };
}
