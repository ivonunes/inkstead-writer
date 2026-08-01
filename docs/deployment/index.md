# Deployment

Deployment is how your finished site gets onto the internet. Inkstead Writer publishes the site for you, without changing how you write posts or build themes. This page explains what publishing does and how to check you are ready; the provider guides cover each host in detail.

Choose a publishing target during `inkstead-writer init`, or change it later in `inkstead-writer.json`.

Some targets publish through a matching CI provider: GitHub Pages goes through GitHub Actions and GitLab Pages through GitLab CI. Inkstead Writer checks those combinations when it loads your config, so a mismatch is caught early.

## What publishing does

When you finish a post, one command takes care of everything. `./inkstead-writer publish` runs the full publishing flow:

1. Build the site.
2. Deploy the built output.
3. Syndicate posts that ask to be syndicated.
4. Rebuild and deploy again if syndication added new links to post frontmatter.

That order means social posts can link to pages that are already live.

If you only want to put an already-built site online, run the two steps yourself:

```bash
./inkstead-writer build
./inkstead-writer deploy
```

This builds the site and deploys it, without any syndication.

## Checking your setup

When you are ready to publish, check the deployment requirements:

```bash
./inkstead-writer doctor
```

`doctor` reports anything missing, including the environment variables your publishing target and syndication providers need; see [what doctor checks](../start/commands.md#what-doctor-checks) for the full list.

If `doctor` reports missing environment variables and you want to publish from your own machine, create a local `.env` file:

```bash
cp .env.example .env
```

Fill in the required values in `.env`, then run `./inkstead-writer doctor` again. The `.env` file is ignored by git, so your tokens never end up in the repository.

If you publish through CI instead, add the same names from `.env.example` as CI secrets or variables. See [Continuous Integration](../ci/index.md).

If `doctor` says a generated workflow differs from Inkstead Writer's current template, bring it up to date:

```bash
./inkstead-writer migrate
```

The migrate command updates generated workflow files such as `.github/workflows/publish.yml`, `.gitlab-ci.yml`, `.forgejo/workflows/publish.yml` and the root `./inkstead-writer` wrapper.

## The not-found page

Inkstead Writer writes a custom not-found page to `404.html` in the build output. Static hosts that support custom 404 files can serve it automatically; Cloudflare Workers deployments use the same file through Workers static asset handling.

## Provider guides

Each guide covers one host, from configuration to first publish:

- [Cloudflare Workers](cloudflare-workers.md)
- [Netlify](netlify.md)
- [GitHub Pages](github-pages.md)
- [GitLab Pages](gitlab-pages.md)
