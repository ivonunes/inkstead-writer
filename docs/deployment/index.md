# Deployment

Inkstead can publish through deployment adapters without changing how you write posts or build themes.

Choose a deployment target during `npx inkstead init`, or change it later in `site.config.ts`.

Some deployment adapters require a matching CI adapter. Inkstead validates adapter combinations when it loads `site.config.ts`.

## Before Publishing

When you are ready to publish, check the deployment requirements:

```bash
npm run doctor
```

If `doctor` reports missing environment variables and you want to publish from your own machine, create a local `.env` file:

```bash
cp .env.example .env
```

Fill in the required values in `.env`, then run `npm run doctor` again. If you publish through CI, add the same names from `.env.example` as secrets or variables in your CI provider instead.

If `doctor` says a generated workflow differs from Inkstead's current template, run:

```bash
npm run upgrade
```

The upgrade command updates generated workflow files such as `.github/workflows/publish.yml`, `.gitlab-ci.yml`, or `.forgejo/workflows/publish.yml`. It asks before writing unless you pass `-- --force`.

Adapter guides:

- [Cloudflare Workers](./cloudflare-workers/)
- [Netlify](./netlify/)
- [GitHub Pages](./github-pages/)
- [GitLab Pages](./gitlab-pages/)
