import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { ciProviders, uniqueEnvironmentVariables } from "./adapters/registry.js";
import type { GeneratedFile } from "./adapters/types.js";
import type { InksteadConfig } from "./config/types.js";
import { writeFileEnsured } from "../utils/fs.js";

export type WorkflowUpgradeStatus = "current" | "changed" | "missing";

export interface WorkflowUpgrade {
  path: string;
  status: WorkflowUpgradeStatus;
  content: string;
}

export function expectedWorkflowFiles(config: InksteadConfig): GeneratedFile[] {
  if (!config.ci) return [];
  return ciProviders[config.ci.provider].generateWorkflow({
    environmentVariables: uniqueEnvironmentVariables(config),
    deploymentProvider: config.deploy?.provider,
    buildOutput: config.build?.output ?? "dist",
    hasSyndication: Boolean(config.syndication?.providers.length)
  });
}

export async function workflowUpgradePlan(root: string, config: InksteadConfig): Promise<WorkflowUpgrade[]> {
  const expected = expectedWorkflowFiles(config);
  const plan: WorkflowUpgrade[] = [];
  for (const file of expected) {
    const absolutePath = path.join(root, file.path);
    if (!existsSync(absolutePath)) {
      plan.push({ path: file.path, status: "missing", content: file.content });
      continue;
    }
    const current = await readFile(absolutePath, "utf8");
    plan.push({ path: file.path, status: current === file.content ? "current" : "changed", content: file.content });
  }
  return plan;
}

export async function applyWorkflowUpgrades(root: string, upgrades: WorkflowUpgrade[]): Promise<string[]> {
  const applied: string[] = [];
  for (const upgrade of upgrades.filter((item) => item.status !== "current")) {
    await writeFileEnsured(path.join(root, upgrade.path), upgrade.content);
    applied.push(upgrade.path);
  }
  return applied;
}
