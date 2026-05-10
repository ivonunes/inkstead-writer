import { promises as fs } from "node:fs";
import path from "node:path";
import type { DeploymentProvider } from "../../core/adapters/types.js";

export const githubPagesProvider: DeploymentProvider = {
  name: "GitHub Pages",
  requirements: () => [],
  deploy: async ({ distDir }) => {
    if (!process.env.GITHUB_ACTIONS) {
      throw new Error("GitHub Pages deployment is handled by GitHub Actions. Push your site to GitHub to publish it.");
    }
    await fs.writeFile(path.join(distDir, ".nojekyll"), "").catch(() => undefined);
  },
  doctor: async ({ env }) => [{
    status: env.GITHUB_ACTIONS ? "pass" : "warn",
    label: env.GITHUB_ACTIONS ? "GitHub Pages running in GitHub Actions" : "GitHub Pages deploys from GitHub Actions",
    message: env.GITHUB_ACTIONS ? "Pages artifact will be deployed" : "push to GitHub to publish"
  }]
};
