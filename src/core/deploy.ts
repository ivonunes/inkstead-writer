import dotenv from "dotenv";
import path from "node:path";
import type { InksteadConfig } from "./config/types.js";
import { deployProviders } from "./adapters/registry.js";

export async function deploySite(root: string, config: InksteadConfig): Promise<void> {
  dotenv.config({ path: path.join(root, ".env") });
  if (!config.deploy) throw new Error("No deployment provider is configured.");
  await deployProviders[config.deploy.provider].deploy({
    root,
    distDir: path.join(root, config.build?.output ?? "dist"),
    projectName: config.deploy.projectName,
    env: process.env
  });
}
