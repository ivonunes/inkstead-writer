# Deployment

Inkstead Writer can publish your built site without changing how you write posts or build themes.

Choose a deployment target during `inkstead-writer init`, or change it later in `inkstead-writer.json`.

Some publishing targets, such as GitHub Pages and GitLab Pages, run through their matching CI provider. Inkstead Writer checks those combinations when it loads your config.

## What Publish Does

`./inkstead-writer publish` runs the full publishing flow:

1. Build the site.
2. Deploy the built output.
3. Syndicate posts that ask to be syndicated.
4. Rebuild and deploy again if syndication added new links to post frontmatter.

That order means social posts can link to pages that are already live.

If you only want to deploy an already-built site, run:

```bash
./inkstead-writer build
./inkstead-writer deploy
```

## Before Publishing

When you are ready to publish, check the deployment requirements:

```bash
./inkstead-writer doctor
```

If `doctor` reports missing environment variables and you want to publish from your own machine, create a local `.env` file:

```bash
cp .env.example .env
```

Fill in the required values in `.env`, then run `./inkstead-writer doctor` again. If you publish through CI, add the same names from `.env.example` as secrets or variables in your CI provider instead.

If `doctor` says a generated workflow differs from Inkstead Writer's current template, run:

```bash
./inkstead-writer migrate
```

The migrate command updates generated workflow files such as `.github/workflows/publish.yml`, `.gitlab-ci.yml`, `.forgejo/workflows/publish.yml`, and the root `./inkstead-writer` command.

Inkstead Writer writes a custom not-found page to `404.html` in the build output. Static hosts that support custom 404 files can serve it automatically; Cloudflare Workers deployments use the same file through Workers static asset handling.

Provider guides:

- [Cloudflare Workers](./cloudflare-workers/)
- [Netlify](./netlify/)
- [GitHub Pages](./github-pages/)
- [GitLab Pages](./gitlab-pages/)
