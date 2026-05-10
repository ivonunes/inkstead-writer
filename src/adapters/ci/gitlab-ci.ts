import { existsSync } from "node:fs";
import path from "node:path";
import type { CiProvider } from "../../core/adapters/types.js";

export const gitlabCiProvider: CiProvider = {
  name: "GitLab CI",
  requirements: () => [],
  generateWorkflow: ({ deploymentProvider, buildOutput = "dist", hasSyndication = false }) => {
    if (deploymentProvider === "gitlab-pages") {
      return [{
        path: ".gitlab-ci.yml",
        content: `image: node:22

stages:
  - deploy${hasSyndication ? `
  - syndicate
  - redeploy` : ""}

deploy-pages:
  stage: deploy
  rules:
    - if: '$CI_COMMIT_BRANCH == "main"'
    - if: '$CI_PIPELINE_SOURCE == "web"'
  script:
    - npm ci
    - npm run build
    - touch ${buildOutput}/.nojekyll
  pages:
    publish: ${buildOutput}${hasSyndication ? `
  artifacts:
    paths:
      - ${buildOutput}` : ""}
${hasSyndication ? `
syndicate:
  stage: syndicate
  needs:
    - deploy-pages
  rules:
    - if: '$CI_COMMIT_BRANCH == "main"'
    - if: '$CI_PIPELINE_SOURCE == "web"'
  script:
    - npm ci
    - npm run syndicate
    - git config user.name "GitLab CI"
    - git config user.email "gitlab-ci@example.invalid"
    - git add content/posts
    - git commit -m "Update syndication data [skip ci]" || true
    - git remote set-url origin "https://gitlab-ci-token:${"${CI_JOB_TOKEN}"}@${"${CI_SERVER_HOST}"}/${"${CI_PROJECT_PATH}"}.git"
    - git push origin HEAD:${"${CI_COMMIT_BRANCH}"}
  artifacts:
    paths:
      - content/posts

redeploy-pages:
  stage: redeploy
  needs:
    - syndicate
  rules:
    - if: '$CI_COMMIT_BRANCH == "main"'
    - if: '$CI_PIPELINE_SOURCE == "web"'
  script:
    - npm ci
    - npm run build
    - touch ${buildOutput}/.nojekyll
  pages:
    publish: ${buildOutput}` : ""}
`
      }];
    }

    return [{
      path: ".gitlab-ci.yml",
      content: `image: node:22

stages:
  - publish

publish:
  stage: publish
  rules:
    - if: '$CI_COMMIT_BRANCH == "main"'
    - if: '$CI_PIPELINE_SOURCE == "web"'
  before_script:
    - npm ci
  script:
    - npm run publish
`
    }];
  },
  doctor: async ({ root }) => [{
    status: existsSync(path.join(root, ".gitlab-ci.yml")) ? "pass" : "fail",
    label: "publish pipeline found",
    message: ".gitlab-ci.yml"
  }]
};
