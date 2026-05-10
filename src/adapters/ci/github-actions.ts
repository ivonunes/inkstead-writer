import { existsSync } from "node:fs";
import path from "node:path";
import type { CiProvider } from "../../core/adapters/types.js";

function secretEnv(environmentVariables: string[]): string {
  return environmentVariables.length > 0 ? `
        env:
${environmentVariables.map((name) => `          ${name}: \${{ secrets.${name} }}`).join("\n")}` : "";
}

function pagesWorkflow(environmentVariables: string[], buildOutput: string, hasSyndication: boolean): string {
  return `name: Publish

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: write
  pages: write
  id-token: write

jobs:
  build-pages:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          persist-credentials: true

      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: npm

      - uses: actions/configure-pages@v5
      - run: npm ci
      - run: npm run build
      - run: touch ${buildOutput}/.nojekyll
      - uses: actions/upload-pages-artifact@v4
        with:
          name: github-pages-initial
          path: ${buildOutput}

  deploy-pages:
    runs-on: ubuntu-latest
    needs: build-pages
    environment:
      name: github-pages
      url: \${{ steps.deployment.outputs.page_url }}
    steps:
      - id: deployment
        uses: actions/deploy-pages@v4
        with:
          artifact_name: github-pages-initial${hasSyndication ? `

  syndicate-pages:
    runs-on: ubuntu-latest
    needs: deploy-pages
    steps:
      - uses: actions/checkout@v4
        with:
          persist-credentials: true

      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: npm

      - run: npm ci
      - run: npm run syndicate${secretEnv(environmentVariables)}
      - run: |
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git add content/posts
          git commit -m "Update syndication data [skip ci]" || true
          git push origin HEAD:\${{ github.ref_name }}
      - run: npm run build
      - run: touch ${buildOutput}/.nojekyll
      - uses: actions/upload-pages-artifact@v4
        with:
          name: github-pages-updated
          path: ${buildOutput}

  redeploy-pages:
    runs-on: ubuntu-latest
    needs: syndicate-pages
    environment:
      name: github-pages
      url: \${{ steps.deployment.outputs.page_url }}
    steps:
      - id: deployment
        uses: actions/deploy-pages@v4
        with:
          artifact_name: github-pages-updated` : ""}
`;
}

export const githubActionsProvider: CiProvider = {
  name: "GitHub Actions",
  requirements: () => [],
  generateWorkflow: ({ environmentVariables, deploymentProvider, buildOutput = "dist", hasSyndication = false }) => [{
    path: ".github/workflows/publish.yml",
    content: deploymentProvider === "github-pages" ? pagesWorkflow(environmentVariables, buildOutput, hasSyndication) : `name: Publish

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: write

jobs:
  publish:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4
        with:
          persist-credentials: true

      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: npm

      - run: npm ci
      - run: npm run publish${secretEnv(environmentVariables)}
`
  }],
  doctor: async ({ root }) => [{
    status: existsSync(path.join(root, ".github/workflows/publish.yml")) ? "pass" : "fail",
    label: "publish workflow found",
    message: ".github/workflows/publish.yml"
  }]
};
