#!/usr/bin/env node
import { Command } from "commander";
import { spawnSync } from "node:child_process";
import { createInterface } from "node:readline/promises";
import { stdin as input, stdout as output } from "node:process";
import { buildSite } from "../core/build/build.js";
import { loadConfig } from "../core/config/load-config.js";
import { createPost, type NewPostKind } from "../core/content/create-post.js";
import { deploySite } from "../core/deploy.js";
import { devServer } from "../core/dev.js";
import { runDoctor } from "../core/doctor/doctor.js";
import { initSite, type InitSiteOptions } from "../core/init.js";
import { renderRequirements } from "../core/requirements.js";
import { syndicateSite } from "../core/syndication/syndicate.js";
import { ejectTheme } from "../core/templates/eject.js";
import type { CiProviderName, DeployProviderName, SyndicationProviderName, WriterProviderName } from "../core/config/types.js";

const program = new Command();
program.name("inkstead");

function commitSyndicationChanges(root: string): void {
  if (!process.env.GITHUB_ACTIONS && !process.env.GITLAB_CI) return;

  spawnSync("git", ["config", "user.name", process.env.GITLAB_CI ? "GitLab CI" : "github-actions[bot]"], { cwd: root });
  spawnSync("git", ["config", "user.email", process.env.GITLAB_CI ? "gitlab-ci@example.invalid" : "41898282+github-actions[bot]@users.noreply.github.com"], { cwd: root });
  spawnSync("git", ["add", "content/posts"], { cwd: root });
  const commit = spawnSync("git", ["commit", "-m", "Update syndication data [skip ci]"], { cwd: root });
  if (commit.status !== 0) return;

  if (process.env.GITLAB_CI && process.env.CI_JOB_TOKEN && process.env.CI_SERVER_HOST && process.env.CI_PROJECT_PATH) {
    spawnSync("git", ["remote", "set-url", "origin", `https://gitlab-ci-token:${process.env.CI_JOB_TOKEN}@${process.env.CI_SERVER_HOST}/${process.env.CI_PROJECT_PATH}.git`], { cwd: root });
  }
  if (process.env.GITLAB_CI && process.env.CI_COMMIT_BRANCH) {
    spawnSync("git", ["push", "origin", `HEAD:${process.env.CI_COMMIT_BRANCH}`], { cwd: root });
  } else {
    spawnSync("git", ["push"], { cwd: root });
  }
}

const deploymentChoices: Record<string, DeployProviderName | "none"> = {
  "1": "cloudflare-workers",
  "2": "github-pages",
  "3": "gitlab-pages",
  "4": "none"
};

const syndicationChoices: Record<string, SyndicationProviderName> = {
  "1": "mastodon",
  "2": "bluesky",
  "3": "flickr"
};

const ciChoices: Record<string, CiProviderName | "none"> = {
  "1": "github-actions",
  "2": "gitlab-ci",
  "3": "none"
};

const writerProviderChoices: Record<string, Exclude<WriterProviderName, "local">> = {
  "1": "github",
  "2": "gitlab"
};

function inferredWriterProvider(ci: CiProviderName | "none" | undefined): Exclude<WriterProviderName, "local"> | undefined {
  if (ci === "github-actions") return "github";
  if (ci === "gitlab-ci") return "gitlab";
  return undefined;
}

async function promptInitOptions(directory?: string): Promise<InitSiteOptions> {
  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    return { ci: "github-actions", deploy: "cloudflare-workers", deployProjectName: directory ?? "my-website", syndication: [] };
  }
  const rl = createInterface({ input, output });
  try {
    console.log("Choose deployment:");
    console.log("  1. Cloudflare Workers");
    console.log("  2. GitHub Pages");
    console.log("  3. GitLab Pages");
    console.log("  4. None for now");
    const deployAnswer = (await rl.question("Deployment adapter [1]: ")).trim() || "1";
    const deploy = deploymentChoices[deployAnswer] ?? "cloudflare-workers";
    const options: InitSiteOptions = { deploy };

    if (deploy === "cloudflare-workers") {
      const fallbackName = directory && directory !== "." ? directory : "my-website";
      options.deployProjectName = (await rl.question(`Cloudflare Worker name [${fallbackName}]: `)).trim() || fallbackName;
    }

    if (deploy === "github-pages") {
      options.ci = "github-actions";
      console.log("GitHub Pages uses GitHub Actions, so a .github/workflows/publish.yml workflow will be added.");
    } else if (deploy === "gitlab-pages") {
      options.ci = "gitlab-ci";
      console.log("GitLab Pages uses GitLab CI, so a .gitlab-ci.yml workflow will be added.");
    } else {
      console.log("Choose CI workflow:");
      console.log("  1. GitHub Actions");
      console.log("  2. GitLab CI");
      console.log("  3. None for now");
      const ciAnswer = (await rl.question("CI adapter [1]: ")).trim() || "1";
      options.ci = ciChoices[ciAnswer] ?? "github-actions";
    }

    console.log("Choose syndication adapters, separated by commas:");
    console.log("  1. Mastodon");
    console.log("  2. Bluesky");
    console.log("  3. Flickr");
    console.log("  blank. None for now");
    const syndicationAnswer = (await rl.question("Syndication adapters []: ")).trim();
    options.syndication = [...new Set(syndicationAnswer.split(",")
      .map((item) => item.trim())
      .filter(Boolean)
      .map((item) => syndicationChoices[item] ?? item)
      .filter((item): item is SyndicationProviderName => ["mastodon", "bluesky", "flickr"].includes(item)))];

    const writerAnswer = (await rl.question("Enable Inkstead Writer? [y/N]: ")).trim().toLowerCase();
    if (writerAnswer === "y" || writerAnswer === "yes") {
      let provider = inferredWriterProvider(options.ci);
      if (!provider) {
        console.log("Choose Writer repository provider:");
        console.log("  1. GitHub");
        console.log("  2. GitLab");
        const providerAnswer = (await rl.question("Writer provider [1]: ")).trim() || "1";
        provider = writerProviderChoices[providerAnswer] ?? "github";
      } else {
        console.log(`Writer will use ${provider === "github" ? "GitHub" : "GitLab"} based on your CI choice.`);
      }
      let owner = "";
      while (!owner) owner = (await rl.question(`${provider === "github" ? "GitHub" : "GitLab"} owner or group: `)).trim();
      const repoFallback = directory && directory !== "." ? directory : "my-website";
      const repo = (await rl.question(`Repository name [${repoFallback}]: `)).trim() || repoFallback;
      const branch = (await rl.question("Branch [main]: ")).trim() || "main";
      options.writer = { enabled: true, provider, owner, repo, branch };
    }

    return options;
  } finally {
    rl.close();
  }
}

async function promptNewPost(): Promise<{ kind: NewPostKind; title?: string; text?: string }> {
  const rl = createInterface({ input, output });
  try {
    console.log("Choose post type:");
    console.log("  1. Long article");
    console.log("  2. Note");
    const kindAnswer = (await rl.question("Post type [1]: ")).trim() || "1";
    const kind: NewPostKind = kindAnswer === "2" || kindAnswer.toLowerCase() === "note" ? "note" : "article";
    if (kind === "article") {
      const title = (await rl.question("Title: ")).trim();
      return { kind, title };
    }
    const text = (await rl.question("Note text: ")).trim();
    return { kind, text };
  } finally {
    rl.close();
  }
}

program.command("init [directory]").action(async (directory) => {
  console.log(await initSite(directory, await promptInitOptions(directory)));
});

program.command("build").action(async () => {
  const root = process.cwd();
  await buildSite(root, await loadConfig(root));
  console.log("Built site to dist.");
});

program.command("new")
  .description("create new content")
  .command("post")
  .description("create a new article or note")
  .option("-k, --kind <kind>", "post kind: article or note")
  .option("-t, --title <title>", "article title")
  .option("--text <text>", "note text")
  .action(async (options) => {
    const root = process.cwd();
    const config = await loadConfig(root);
    const kind = options.kind === "note" || options.kind === "article" ? options.kind as NewPostKind : undefined;
    const postOptions = kind && (kind === "note" ? options.text : options.title)
      ? { kind, title: options.title, text: options.text }
      : await promptNewPost();
    const result = await createPost(root, config, postOptions);
    console.log(`Created ${result.relativePath}`);
  });

program.command("dev").option("-p, --port <port>", "port", "4321").action(async (options) => {
  const root = process.cwd();
  await devServer(root, await loadConfig(root), Number(options.port));
});

program.command("syndicate").action(async () => {
  const root = process.cwd();
  const result = await syndicateSite(root, await loadConfig(root));
  console.log(`Syndication complete. Published: ${result.published}. Failed: ${result.failed}.`);
});

program.command("deploy").action(async () => {
  const root = process.cwd();
  await deploySite(root, await loadConfig(root));
});

const theme = program.command("theme");
theme.command("eject").option("-f, --force", "overwrite existing theme files").action(async (options) => {
  const result = await ejectTheme(process.cwd(), { force: Boolean(options.force) });
  for (const file of result.copied) console.log(`Copied ${file}`);
  for (const file of result.skipped) console.log(`Skipped ${file} because it already exists. Use --force to overwrite.`);
  if (result.copied.length === 0 && result.skipped.length === 0) console.log("No theme files were copied.");
});

program.command("publish").action(async () => {
  const root = process.cwd();
  const config = await loadConfig(root);
  await buildSite(root, config);
  await deploySite(root, config);
  const result = await syndicateSite(root, config);
  if (result.changed) {
    await buildSite(root, config);
    await deploySite(root, config);
    commitSyndicationChanges(root);
  }
});

program.command("requirements").action(async () => {
  console.log(renderRequirements(await loadConfig(process.cwd())));
});

program.command("doctor").action(async () => {
  const root = process.cwd();
  const result = await runDoctor(root, await loadConfig(root));
  console.log(result.output);
  if (result.issues > 0) process.exitCode = 1;
});

program.parseAsync().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
