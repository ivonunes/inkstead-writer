import path from "node:path";
import { existsSync } from "node:fs";
import { ciProviders, requirementsForConfig, uniqueEnvironmentVariables } from "./adapters/registry.js";
import type { CiProviderName, DeployProviderName, InksteadConfig, SyndicationProviderName } from "./config/types.js";
import { writeFileEnsured } from "../utils/fs.js";

export interface InitSiteOptions {
  ci?: CiProviderName | "none";
  deploy?: DeployProviderName | "none";
  deployProjectName?: string;
  syndication?: SyndicationProviderName[];
}

function siteConfig(projectName: string, options: InitSiteOptions = {}): InksteadConfig {
  const config: InksteadConfig = {
    site: { title: "My Website", url: "https://example.com", author: "Your Name", description: "Notes, photos, and longer writing." },
    content: { posts: "content/posts", pages: "content/pages", photos: "content/photos" }
  };
  if (options.ci !== "none") config.ci = { provider: options.ci ?? "github-actions" };
  if (options.deploy === "github-pages") config.ci = { provider: "github-actions" };
  if (options.deploy === "gitlab-pages") config.ci = { provider: "gitlab-ci" };
  if (options.deploy === "github-pages") config.deploy = { provider: "github-pages" };
  if (options.deploy === "gitlab-pages") config.deploy = { provider: "gitlab-pages" };
  if (options.deploy === "cloudflare-workers" || options.deploy === undefined) {
    config.deploy = { provider: "cloudflare-workers", projectName: options.deployProjectName ?? projectName };
  }
  if (options.syndication && options.syndication.length > 0) config.syndication = { providers: options.syndication };
  return config;
}

function postFrontmatter(base: Record<string, string>, syndication: SyndicationProviderName[]): string {
  const fields = Object.entries(base).map(([key, value]) => `${key}: ${value}`);
  const socialTargets = syndication.filter((provider) => provider !== "flickr");
  if (socialTargets.length > 0) fields.push(`syndicate:\n${socialTargets.map((provider) => `  - ${provider}`).join("\n")}`);
  return `---\n${fields.join("\n")}\n---`;
}

export async function initSite(directory = ".", options: InitSiteOptions = {}): Promise<string> {
  const root = path.resolve(process.cwd(), directory);
  if (existsSync(root) && directory !== ".") {
    throw new Error(`${directory} already exists.`);
  }
  const projectName = path.basename(root);
  const config = siteConfig(projectName, options);
  const envNames = uniqueEnvironmentVariables(config);
  const workflow = config.ci ? ciProviders[config.ci.provider].generateWorkflow({
    environmentVariables: envNames,
    deploymentProvider: config.deploy?.provider,
    buildOutput: config.build?.output ?? "dist",
    hasSyndication: Boolean(config.syndication?.providers.length)
  })[0] : undefined;
  const syndication = config.syndication?.providers ?? [];
  const files: Record<string, string> = {
    "package.json": JSON.stringify({
      type: "module",
      scripts: {
        dev: "inkstead dev",
        build: "inkstead build",
        deploy: "inkstead deploy",
        publish: "inkstead publish",
        requirements: "inkstead requirements",
        doctor: "inkstead doctor"
      },
      dependencies: { inkstead: "^1.0.0" }
    }, null, 2) + "\n",
    "site.config.ts": `import { defineConfig } from "inkstead";

export default defineConfig(${JSON.stringify(config, null, 2)});
`,
    ".env.example": `${requirementsForConfig(config).map((requirement) => `${requirement.environmentVariable}=`).join("\n")}\n`,
    ".gitignore": "node_modules/\ndist/\n.env\n.env.*\n!.env.example\n.DS_Store\n.site/\n",
    "README.md": "# My Inkstead Site\n\nDocumentation: https://inkstead.dev/\n",
    "content/posts/hello.md": `${postFrontmatter({ date: "2026-05-10T18:30:00+01:00" }, syndication)}\n\nThinking about notes...\n`,
    "content/posts/first-article.md": `${postFrontmatter({ title: "\"Why I Still Want a Personal Website\"", date: "2026-05-10T18:30:00+01:00" }, syndication)}\n\nLonger article content here.\n`,
    "content/pages/about.md": "---\ntitle: About\n---\n\nThis is my website.\n",
    "content/pages/now.md": "---\ntitle: Now\n---\n\nWhat I am focused on now.\n",
    "content/photos/.gitkeep": ""
  };
  if (workflow) files[workflow.path] = workflow.content;

  for (const [file, content] of Object.entries(files)) {
    await writeFileEnsured(path.join(root, file), content);
  }

  return `Your Inkstead site has been created.

Next steps:

1. Install dependencies
   cd ${path.basename(root)}
   npm install

2. Add local secrets
   cp .env.example .env

3. Fill in the required values in .env.

4. For CI publishing, add the same values as secrets or variables.

5. Check your setup
   npm run doctor

6. Preview locally
   npm run dev`;
}
