import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";
import { writeFileEnsured } from "../../utils/fs.js";
import type { DeploymentProvider } from "../../core/adapters/types.js";

export const cloudflareWorkersProvider: DeploymentProvider = {
  name: "Cloudflare Workers",
  requirements: () => [
    {
      name: "Cloudflare account ID",
      type: "secret",
      required: true,
      description: "Cloudflare account that owns the Worker project.",
      environmentVariable: "CLOUDFLARE_ACCOUNT_ID",
      githubSecretName: "CLOUDFLARE_ACCOUNT_ID"
    },
    {
      name: "Cloudflare API token",
      type: "secret",
      required: true,
      description: "API token with Workers deploy permissions.",
      environmentVariable: "CLOUDFLARE_API_TOKEN",
      githubSecretName: "CLOUDFLARE_API_TOKEN"
    }
  ],
  prepare: async ({ root, distDir, projectName }) => {
    if (!projectName) throw new Error("Cloudflare Workers deployment requires deploy.projectName.");
    return [{
      path: "wrangler.toml",
      content: `name = "${projectName}"
main = ".site/worker.js"
compatibility_date = "2026-05-10"

[assets]
directory = "./${path.relative(root, distDir)}"
`
    }, {
      path: ".site/worker.js",
      content: "export default { async fetch(request, env) { return env.ASSETS.fetch(request); } };\n"
    }];
  },
  deploy: async (context) => {
    if (!context.projectName) throw new Error("Cloudflare Workers deployment requires deploy.projectName.");
    const files = await cloudflareWorkersProvider.prepare?.(context) ?? [];
    for (const file of files) {
      if (file.path === "wrangler.toml" && existsSync(path.join(context.root, file.path))) continue;
      await writeFileEnsured(`${context.root}/${file.path}`, file.content);
    }
    await new Promise<void>((resolve, reject) => {
      const child = spawn("npx", ["wrangler", "deploy"], { cwd: context.root, stdio: "inherit", env: context.env });
      child.on("exit", (code) => code === 0 ? resolve() : reject(new Error(`wrangler deploy exited with ${code}`)));
      child.on("error", reject);
    });
  },
  doctor: async ({ env }) => cloudflareWorkersProvider.requirements().map((requirement) => ({
    status: env[requirement.environmentVariable ?? ""] ? "pass" : "fail",
    label: `${requirement.environmentVariable} is ${env[requirement.environmentVariable ?? ""] ? "set" : "missing"}`
  }))
};
