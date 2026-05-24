#!/usr/bin/env node
import { Command } from "commander";
import { spawnSync } from "node:child_process";
import { emitKeypressEvents } from "node:readline";
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
import { applyWorkflowUpgrades, workflowUpgradePlan } from "../core/upgrade.js";
import type { CiProviderName, DeployProviderName, SyndicationProviderName, WriterProviderName } from "../core/config/types.js";

const program = new Command();
program.name("inkstead");

type Choice<T extends string> = {
  value: T;
  label: string;
  description?: string;
};

const useColor = Boolean(process.stdout.isTTY && !process.env.NO_COLOR);
const ansi = {
  bold: "\x1b[1m",
  dim: "\x1b[2m",
  blue: "\x1b[34m",
  green: "\x1b[32m",
  red: "\x1b[31m",
  reset: "\x1b[0m"
};

function style(value: string, ...codes: string[]): string {
  if (!useColor) return value;
  return `${codes.join("")}${value}${ansi.reset}`;
}

function title(value: string): void {
  console.log(`\n${style(value, ansi.bold, ansi.blue)}`);
}

function note(value: string): void {
  console.log(style(value, ansi.dim));
}

function success(value: string): void {
  console.log(style(value, ansi.green));
}

function failure(value: string): void {
  console.error(style(value, ansi.red));
}

function printChoices<T extends string>(choices: Choice<T>[]): void {
  for (const [index, choice] of choices.entries()) {
    const description = choice.description ? ` ${style(choice.description, ansi.dim)}` : "";
    console.log(`  ${style(String(index + 1).padStart(2), ansi.blue)}  ${choice.label}${description}`);
  }
}

async function ask(label: string, fallback?: string): Promise<string> {
  const rl = createInterface({ input, output });
  try {
    const suffix = fallback === undefined ? "" : ` ${style(`[${fallback}]`, ansi.dim)}`;
    return (await rl.question(`${style("?", ansi.blue)} ${label}${suffix}: `)).trim();
  } finally {
    rl.close();
  }
}

function selectLine<T extends string>(choice: Choice<T>, active: boolean, selected?: boolean): string {
  const cursor = active ? style("›", ansi.blue) : " ";
  const marker = selected === undefined ? "" : `${selected ? style("●", ansi.blue) : "○"} `;
  const label = active ? style(choice.label, ansi.bold) : choice.label;
  const description = choice.description ? ` ${style(choice.description, ansi.dim)}` : "";
  return `  ${cursor} ${marker}${label}${description}`;
}

function restorePrompt(renderedLines: number): void {
  if (renderedLines > 0) output.write(`\x1b[${renderedLines}F\x1b[0J`);
}

async function selectChoice<T extends string>(label: string, choices: Choice<T>[], defaultIndex = 0): Promise<T> {
  if (!input.isTTY || !output.isTTY || typeof input.setRawMode !== "function") {
    printChoices(choices);
    const answer = await ask(label, String(defaultIndex + 1));
    const index = Number.parseInt(answer || String(defaultIndex + 1), 10) - 1;
    return choices[index]?.value ?? choices[defaultIndex].value;
  }

  emitKeypressEvents(input);
  const wasRaw = input.isRaw;
  input.setRawMode(true);
  input.resume();

  return new Promise<T>((resolve, reject) => {
    let active = defaultIndex;
    let renderedLines = 0;

    const cleanup = () => {
      input.off("keypress", onKeypress);
      input.setRawMode(Boolean(wasRaw));
      input.pause();
    };
    const finish = (value: T) => {
      cleanup();
      restorePrompt(renderedLines);
      const choice = choices.find((item) => item.value === value) ?? choices[defaultIndex];
      console.log(`${style("✓", ansi.green)} ${label}: ${choice.label}`);
      resolve(value);
    };
    const render = () => {
      restorePrompt(renderedLines);
      const lines = [
        `${style("?", ansi.blue)} ${label} ${style("(use ↑/↓, Enter)", ansi.dim)}`,
        ...choices.map((choice, index) => selectLine(choice, index === active))
      ];
      output.write(`${lines.join("\n")}\n`);
      renderedLines = lines.length;
    };
    const onKeypress = (character: string, key: { name?: string; ctrl?: boolean }) => {
      if (key.ctrl && key.name === "c") {
        cleanup();
        output.write("\n");
        reject(new Error("Cancelled."));
        return;
      }
      if (key.name === "up" || key.name === "left") active = (active - 1 + choices.length) % choices.length;
      else if (key.name === "down" || key.name === "right" || key.name === "tab") active = (active + 1) % choices.length;
      else if (key.name === "return" || key.name === "enter") {
        finish(choices[active].value);
        return;
      } else if (/^[1-9]$/.test(character)) {
        const index = Number.parseInt(character, 10) - 1;
        if (choices[index]) {
          finish(choices[index].value);
          return;
        }
      }
      render();
    };

    input.on("keypress", onKeypress);
    render();
  });
}

async function selectMultiple<T extends string>(label: string, choices: Choice<T>[]): Promise<T[]> {
  if (!input.isTTY || !output.isTTY || typeof input.setRawMode !== "function") {
    printChoices(choices);
    const answer = await ask(label, "");
    const selected = new Set<T>();
    for (const item of answer.split(",").map((part) => part.trim()).filter(Boolean)) {
      const index = Number.parseInt(item, 10) - 1;
      const choice = choices[index] ?? choices.find((candidate) => candidate.value === item || candidate.label.toLowerCase() === item.toLowerCase());
      if (choice) selected.add(choice.value);
    }
    return [...selected];
  }

  emitKeypressEvents(input);
  const wasRaw = input.isRaw;
  input.setRawMode(true);
  input.resume();

  return new Promise<T[]>((resolve, reject) => {
    let active = 0;
    let renderedLines = 0;
    const selected = new Set<T>();

    const cleanup = () => {
      input.off("keypress", onKeypress);
      input.setRawMode(Boolean(wasRaw));
      input.pause();
    };
    const finish = () => {
      cleanup();
      restorePrompt(renderedLines);
      const names = choices.filter((choice) => selected.has(choice.value)).map((choice) => choice.label);
      console.log(`${style("✓", ansi.green)} ${label}: ${names.length > 0 ? names.join(", ") : "None"}`);
      resolve(choices.filter((choice) => selected.has(choice.value)).map((choice) => choice.value));
    };
    const render = () => {
      restorePrompt(renderedLines);
      const lines = [
        `${style("?", ansi.blue)} ${label} ${style("(use ↑/↓, Space, Enter)", ansi.dim)}`,
        ...choices.map((choice, index) => selectLine(choice, index === active, selected.has(choice.value)))
      ];
      output.write(`${lines.join("\n")}\n`);
      renderedLines = lines.length;
    };
    const onKeypress = (character: string, key: { name?: string; ctrl?: boolean }) => {
      if (key.ctrl && key.name === "c") {
        cleanup();
        output.write("\n");
        reject(new Error("Cancelled."));
        return;
      }
      if (key.name === "up" || key.name === "left") active = (active - 1 + choices.length) % choices.length;
      else if (key.name === "down" || key.name === "right" || key.name === "tab") active = (active + 1) % choices.length;
      else if (key.name === "space" || character === " ") {
        const value = choices[active].value;
        if (selected.has(value)) selected.delete(value);
        else selected.add(value);
      } else if (key.name === "return" || key.name === "enter") {
        finish();
        return;
      } else if (/^[1-9]$/.test(character)) {
        const choice = choices[Number.parseInt(character, 10) - 1];
        if (choice) {
          if (selected.has(choice.value)) selected.delete(choice.value);
          else selected.add(choice.value);
        }
      }
      render();
    };

    input.on("keypress", onKeypress);
    render();
  });
}

function commitSyndicationChanges(root: string): void {
  if (!process.env.GITHUB_ACTIONS && !process.env.GITLAB_CI && !process.env.FORGEJO_ACTIONS) return;

  const isGitLab = Boolean(process.env.GITLAB_CI);
  const isForgejo = Boolean(process.env.FORGEJO_ACTIONS);
  spawnSync("git", ["config", "user.name", isGitLab ? "GitLab CI" : isForgejo ? "Forgejo Actions" : "github-actions[bot]"], { cwd: root });
  spawnSync("git", ["config", "user.email", isGitLab ? "gitlab-ci@example.invalid" : isForgejo ? "forgejo-actions@example.invalid" : "41898282+github-actions[bot]@users.noreply.github.com"], { cwd: root });
  spawnSync("git", ["add", "content/posts"], { cwd: root });
  const commit = spawnSync("git", ["commit", "-m", "Update syndication data [skip ci]"], { cwd: root });
  if (commit.status !== 0) return;

  if (isGitLab && process.env.CI_JOB_TOKEN && process.env.CI_SERVER_HOST && process.env.CI_PROJECT_PATH) {
    spawnSync("git", ["remote", "set-url", "origin", `https://gitlab-ci-token:${process.env.CI_JOB_TOKEN}@${process.env.CI_SERVER_HOST}/${process.env.CI_PROJECT_PATH}.git`], { cwd: root });
  }
  if (isGitLab && process.env.CI_COMMIT_BRANCH) {
    spawnSync("git", ["push", "origin", `HEAD:${process.env.CI_COMMIT_BRANCH}`], { cwd: root });
  } else if (isForgejo && process.env.FORGEJO_REF_NAME) {
    spawnSync("git", ["push", "origin", `HEAD:${process.env.FORGEJO_REF_NAME}`], { cwd: root });
  } else {
    spawnSync("git", ["push"], { cwd: root });
  }
}

const deploymentChoices: Choice<DeployProviderName | "none">[] = [
  { value: "cloudflare-workers", label: "Cloudflare Workers", description: "deploy with Wrangler" },
  { value: "netlify", label: "Netlify", description: "deploy with Netlify CLI" },
  { value: "github-pages", label: "GitHub Pages", description: "publish through GitHub Actions" },
  { value: "gitlab-pages", label: "GitLab Pages", description: "publish through GitLab CI" },
  { value: "none", label: "None for now", description: "build locally only" }
];

const syndicationChoices: Choice<SyndicationProviderName>[] = [
  { value: "mastodon", label: "Mastodon" },
  { value: "bluesky", label: "Bluesky" },
  { value: "flickr", label: "Flickr" }
];

const ciChoices: Choice<CiProviderName | "none">[] = [
  { value: "github-actions", label: "GitHub Actions", description: "generate .github/workflows/publish.yml" },
  { value: "gitlab-ci", label: "GitLab CI", description: "generate .gitlab-ci.yml" },
  { value: "forgejo-actions", label: "Forgejo Actions", description: "generate .forgejo/workflows/publish.yml" },
  { value: "none", label: "None for now", description: "add automation later" }
];

const writerProviderChoices: Choice<Exclude<WriterProviderName, "local">>[] = [
  { value: "github", label: "GitHub" },
  { value: "gitlab", label: "GitLab" },
  { value: "forgejo", label: "Forgejo" }
];

const postKindChoices: Choice<NewPostKind>[] = [
  { value: "article", label: "Long article", description: "title plus body" },
  { value: "note", label: "Note", description: "short untitled post" }
];

function inferredWriterProvider(ci: CiProviderName | "none" | undefined): Exclude<WriterProviderName, "local"> | undefined {
  if (ci === "github-actions") return "github";
  if (ci === "gitlab-ci") return "gitlab";
  if (ci === "forgejo-actions") return "forgejo";
  return undefined;
}

function writerProviderLabel(provider: Exclude<WriterProviderName, "local">): string {
  if (provider === "github") return "GitHub";
  if (provider === "gitlab") return "GitLab";
  return "Forgejo";
}

async function promptInitOptions(directory?: string): Promise<InitSiteOptions> {
  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    return { ci: "github-actions", deploy: "cloudflare-workers", deployProjectName: directory ?? "my-website", syndication: [] };
  }
  title("Inkstead init");
  note("Set up the pieces you want now. You can change these later in site.config.ts.");

  title("Deployment");
  const deploy = await selectChoice("Deployment adapter", deploymentChoices);
  const options: InitSiteOptions = { deploy };

  if (deploy === "cloudflare-workers") {
    const fallbackName = directory && directory !== "." ? directory : "my-website";
    options.deployProjectName = await ask("Cloudflare Worker name", fallbackName) || fallbackName;
  }

  if (deploy === "github-pages") {
    options.ci = "github-actions";
    note("GitHub Pages uses GitHub Actions, so a .github/workflows/publish.yml workflow will be added.");
  } else if (deploy === "gitlab-pages") {
    options.ci = "gitlab-ci";
    note("GitLab Pages uses GitLab CI, so a .gitlab-ci.yml workflow will be added.");
  } else {
    title("Continuous Integration");
    options.ci = await selectChoice("CI adapter", ciChoices);
  }

  title("Syndication");
  note("Optional. Choose one or more targets.");
  options.syndication = await selectMultiple("Syndication adapters", syndicationChoices);

  title("Writer");
  note("Writer gives you a private web editor for creating and editing posts.");
  const enableWriter = await selectChoice("Enable Inkstead Writer?", [
    { value: "no", label: "No" },
    { value: "yes", label: "Yes" }
  ]);
  if (enableWriter === "yes") {
    let provider = inferredWriterProvider(options.ci);
    if (!provider) {
      title("Writer Provider");
      provider = await selectChoice("Writer provider", writerProviderChoices);
    } else {
      note(`Writer will use ${writerProviderLabel(provider)} based on your CI choice.`);
    }
    const instanceUrl = provider === "forgejo" ? await ask("Forgejo instance URL", "https://codeberg.org") || "https://codeberg.org" : undefined;
    let owner = "";
    while (!owner) owner = await ask(`${writerProviderLabel(provider)} owner or group`);
    const repoFallback = directory && directory !== "." ? directory : "my-website";
    const repo = await ask("Repository name", repoFallback) || repoFallback;
    const branch = await ask("Branch", "main") || "main";
    options.writer = { enabled: true, provider, instanceUrl, owner, repo, branch };
  }

  return options;
}

async function promptNewPost(): Promise<{ kind: NewPostKind; title?: string; text?: string }> {
  title("New post");
  const kind = await selectChoice("Post type", postKindChoices);
  if (kind === "article") {
    const title = await ask("Title");
    return { kind, title };
  }
  const text = await ask("Note text");
  return { kind, text };
}

program.command("init [directory]").action(async (directory) => {
  console.log(await initSite(directory, await promptInitOptions(directory)));
});

program.command("build").action(async () => {
  const root = process.cwd();
  await buildSite(root, await loadConfig(root));
  success("Built site to dist.");
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
    success(`Created ${result.relativePath}`);
  });

program.command("dev").option("-p, --port <port>", "port", "4321").action(async (options) => {
  const root = process.cwd();
  await devServer(root, await loadConfig(root), Number(options.port));
});

program.command("syndicate").action(async () => {
  const root = process.cwd();
  const result = await syndicateSite(root, await loadConfig(root));
  success(`Syndication complete. Published: ${result.published}. Failed: ${result.failed}.`);
});

program.command("deploy").action(async () => {
  const root = process.cwd();
  await deploySite(root, await loadConfig(root));
});

const theme = program.command("theme");
theme.command("eject").option("-f, --force", "overwrite existing theme files").action(async (options) => {
  const result = await ejectTheme(process.cwd(), { force: Boolean(options.force) });
  for (const file of result.copied) success(`Copied ${file}`);
  for (const file of result.skipped) note(`Skipped ${file} because it already exists. Use --force to overwrite.`);
  if (result.copied.length === 0 && result.skipped.length === 0) note("No theme files were copied.");
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

program.command("upgrade")
  .description("upgrade generated Inkstead project files")
  .option("-f, --force", "write updates without asking")
  .option("--check", "only check whether generated files need updates")
  .action(async (options) => {
    const root = process.cwd();
    const plan = await workflowUpgradePlan(root, await loadConfig(root));
    const updates = plan.filter((item) => item.status !== "current");
    if (updates.length === 0) {
      success("Generated workflow files are up to date.");
      return;
    }

    title("Generated workflow updates");
    for (const update of updates) {
      const label = update.status === "missing" ? "Missing" : "Changed";
      console.log(`  ${style("!", ansi.blue)}  ${label}: ${update.path}`);
    }

    if (options.check) {
      process.exitCode = 1;
      return;
    }

    if (!options.force) {
      const answer = await selectChoice("Update generated workflow files?", [
        { value: "yes", label: "Yes" },
        { value: "no", label: "No" }
      ]);
      if (answer !== "yes") {
        note("No files changed.");
        return;
      }
    }

    for (const file of await applyWorkflowUpgrades(root, updates)) success(`Updated ${file}`);
  });

program.command("doctor").action(async () => {
  const root = process.cwd();
  const result = await runDoctor(root, await loadConfig(root));
  console.log(result.output);
  if (result.issues > 0) process.exitCode = 1;
});

program.parseAsync().catch((error) => {
  failure(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
