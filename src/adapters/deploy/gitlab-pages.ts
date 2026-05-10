import { promises as fs } from "node:fs";
import path from "node:path";
import type { DeploymentProvider } from "../../core/adapters/types.js";

export const gitlabPagesProvider: DeploymentProvider = {
  name: "GitLab Pages",
  requirements: () => [],
  deploy: async ({ root, distDir }) => {
    if (!process.env.GITLAB_CI) {
      throw new Error("GitLab Pages deployment is handled by GitLab CI. Push your site to GitLab to publish it.");
    }
    await fs.writeFile(path.join(distDir, ".nojekyll"), "").catch(() => undefined);
    await fs.cp(distDir, path.join(root, "public"), { recursive: true, force: true });
  },
  doctor: async ({ env }) => [{
    status: env.GITLAB_CI ? "pass" : "warn",
    label: env.GITLAB_CI ? "GitLab Pages running in GitLab CI" : "GitLab Pages deploys from GitLab CI",
    message: env.GITLAB_CI ? "public artifact will be published" : "push to GitLab to publish"
  }]
};
