# Commands

This page lists every `inkstead-writer` command in one place. Inside a site, run commands through the `./inkstead-writer` wrapper. The globally installed `inkstead-writer` is mainly for creating sites and managing cached binaries.

In this guide you will learn:

- how the `./inkstead-writer` wrapper keeps a site on the right version
- which commands you use while writing and previewing
- which commands build, publish and check a site
- which commands manage themes, updates and the binary cache

## The `./inkstead-writer` wrapper

Every site has a small script called `inkstead-writer` at its root, created by `init`. Running `./inkstead-writer` uses it instead of the global binary.

The wrapper reads the version recorded in `inkstead-writer.json` and runs exactly that Inkstead Writer release. If that release is not on your machine yet, the wrapper downloads it, verifies its checksum and caches it, so the first run needs a network connection and later runs do not. The same site therefore behaves the same everywhere: on your machine, on another computer and in CI.

The wrapper works from anywhere inside the site and runs commands from the site root. The bare `inkstead-writer` command is only needed before a site exists, for installing and for `inkstead-writer init`.

## Writing

| Command | What it does |
| --- | --- |
| `new post` | Creates an article or note with the right filename and frontmatter. Options: `--kind` (`article` or `note`), `--title`, `--text`. |
| `dev` | Builds the site, serves it locally and reloads the browser on changes. Use `--port` to change the port. |

See [Getting Started](getting-started.md) for the writing workflow.

## Building and publishing

| Command | What it does |
| --- | --- |
| `build` | Builds the static site into the output folder, `dist` by default. |
| `deploy` | Deploys an already-built site to the configured target. |
| `publish` | Builds, deploys, syndicates, then rebuilds and redeploys if syndication added links. |
| `syndicate` | Publishes pending posts to configured syndication providers without deploying. |

See [Deployment](../deployment/index.md) and [Syndication](../syndication/index.md) for provider setup.

## Checks

| Command | What it does |
| --- | --- |
| `doctor` | Checks the whole site setup and reports anything missing. |
| `requirements` | Prints the environment variable names your publishing and syndication setup needs. |

### What doctor checks

`doctor` looks at everything a publish depends on:

- `inkstead-writer.json` is present and the site configuration loads
- the posts, pages and media folders exist
- `.env` is present, and every environment variable your publishing target and syndication providers need is set
- publishing target settings, such as the Cloudflare Worker name or the Netlify variables
- the `./inkstead-writer` wrapper is present, executable and current
- generated CI workflows match Inkstead Writer's current template and run the wrapper
- all posts load without content errors

It ends with a summary of passes, warnings and blocking issues. When it suggests `./inkstead-writer migrate`, running that brings generated files up to date.

## Themes

| Command | What it does |
| --- | --- |
| `theme eject` | Copies the default templates into your theme folder. `--force` overwrites existing files. |
| `theme check` | Checks templates without building the site. |
| `theme format` | Formats templates. `--check` reports differences without writing. |
| `theme language-server` | Runs the Plume language server for editor integrations. |

See [Themes](themes.md) for details.

## Maintenance

| Command | What it does |
| --- | --- |
| `update` | Updates the site to the latest Inkstead Writer release, or a specific one with `--to <version>`. `--check` only reports, `--dry-run` previews the migration. |
| `migrate` | Applies migrations for the version already recorded in the site. |
| `cache list` | Lists downloaded binaries. |
| `cache clean` | Prunes downloaded binaries. `--dry-run` previews. |
| `version` | Prints the Inkstead Writer version. |

See [Upgrading](../upgrading/index.md) for how versions and migrations fit together.

## Creating sites

| Command | What it does |
| --- | --- |
| `init` | Creates a new site interactively. Run `inkstead-writer init --help` to see the non-interactive options for publishing, CI, syndication and app connection setup. |
