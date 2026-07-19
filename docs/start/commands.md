# Commands

Inside a site, run commands through the site command, `./inkstead-writer`. It keeps the site on the Inkstead Writer version recorded in `inkstead-writer.json`. The globally installed `inkstead-writer` is mainly for creating sites and managing cached binaries.

## Writing

- `new post` — create an article or note with the right filename and frontmatter. Options: `--kind article|note`, `--title`, `--text`.
- `dev` — build the site, serve it locally, and reload the browser on changes. Use `--port` to change the port. See [Getting Started](/start/getting-started/).

## Building And Publishing

- `build` — build the static site into the output folder, `dist` by default.
- `deploy` — deploy an already-built site to the configured target. See [Deployment](/deployment/).
- `publish` — build, deploy, syndicate, then rebuild and redeploy if syndication added links.
- `syndicate` — publish pending posts to configured syndication providers without deploying. See [Syndication](/syndication/).

## Checks

- `doctor` — check config, content, publishing setup, and required environment variables.
- `requirements` — print the environment variable names your publishing and syndication setup needs.

## Themes

- `theme eject` — copy the default templates into your theme folder. `--force` overwrites existing files.
- `theme check` — check templates without building the site.
- `theme format` — format templates. `--check` reports differences without writing.
- `theme language-server` — run the Plume language server for editor integrations.

See [Themes](/start/themes/) for details.

## Maintenance

- `update` — update the site to the latest Inkstead Writer release. `--check` only reports, `--dry-run` previews the migration.
- `migrate` — apply migrations for the version already recorded in the site.
- `cache list` and `cache clean` — inspect or prune downloaded binaries. `cache clean --dry-run` previews.
- `version` — print the Inkstead Writer version.

See [Upgrading](/upgrading/) for how versions and migrations fit together.

## Creating Sites

- `init` — create a new site interactively. Run `inkstead-writer init --help` to see the non-interactive options for publishing, CI, syndication, and app connection setup.
