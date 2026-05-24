import { spawn } from "node:child_process";
import path from "node:path";
import type { DeploymentProvider } from "../../core/adapters/types.js";

export const netlifyProvider: DeploymentProvider = {
  name: "Netlify",
  requirements: () => [
    {
      name: "Netlify site ID",
      type: "config",
      required: true,
      description: "Netlify site ID, also called the project ID in Netlify.",
      environmentVariable: "NETLIFY_SITE_ID",
      githubSecretName: "NETLIFY_SITE_ID"
    },
    {
      name: "Netlify auth token",
      type: "secret",
      required: true,
      description: "Netlify personal access token for CLI deploys.",
      environmentVariable: "NETLIFY_AUTH_TOKEN",
      githubSecretName: "NETLIFY_AUTH_TOKEN"
    }
  ],
  deploy: async ({ root, distDir, env }) => {
    const siteId = env.NETLIFY_SITE_ID;
    const authToken = env.NETLIFY_AUTH_TOKEN;
    if (!siteId) throw new Error("Netlify deployment requires NETLIFY_SITE_ID.");
    if (!authToken) throw new Error("Netlify deployment requires NETLIFY_AUTH_TOKEN.");

    const deployDir = path.relative(root, distDir) || ".";
    await new Promise<void>((resolve, reject) => {
      const child = spawn("npx", ["netlify", "deploy", "--prod", "--no-build", "--dir", deployDir, "--site", siteId], {
        cwd: root,
        stdio: "inherit",
        env: {
          ...env,
          NETLIFY_AUTH_TOKEN: authToken,
          NETLIFY_SITE_ID: siteId
        }
      });
      child.on("exit", (code) => code === 0 ? resolve() : reject(new Error(`netlify deploy exited with ${code}`)));
      child.on("error", reject);
    });
  },
  doctor: async ({ env }) => netlifyProvider.requirements().map((requirement) => ({
    status: env[requirement.environmentVariable ?? ""] ? "pass" : "fail",
    label: `${requirement.environmentVariable} is ${env[requirement.environmentVariable ?? ""] ? "set" : "missing"}`
  }))
};
