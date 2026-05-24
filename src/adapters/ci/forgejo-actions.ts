import { existsSync } from "node:fs";
import path from "node:path";
import type { CiProvider } from "../../core/adapters/types.js";

function secretEnv(environmentVariables: string[]): string {
  return environmentVariables.length > 0 ? `
        env:
${environmentVariables.map((name) => `          ${name}: \${{ secrets.${name} }}`).join("\n")}` : "";
}

export const forgejoActionsProvider: CiProvider = {
  name: "Forgejo Actions",
  requirements: () => [],
  generateWorkflow: ({ environmentVariables }) => [{
    path: ".forgejo/workflows/publish.yml",
    content: `name: Publish

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  publish:
    runs-on: docker
    container:
      image: node:22

    steps:
      - uses: actions/checkout@v4
        with:
          persist-credentials: true

      - run: npm ci
      - run: npm run publish${secretEnv(environmentVariables)}
`
  }],
  doctor: async ({ root }) => [{
    status: existsSync(path.join(root, ".forgejo/workflows/publish.yml")) ? "pass" : "fail",
    label: "publish workflow found",
    message: ".forgejo/workflows/publish.yml"
  }]
};
