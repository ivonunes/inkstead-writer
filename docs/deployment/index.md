# Deployment

Inkstead Writer can publish through deployment adapters without changing how you write posts or build themes.

Choose a deployment target during `inkstead-writer init`, or change it later in `inkstead-writer.json`.

Some deployment adapters require a matching CI adapter. Inkstead Writer validates adapter combinations when it loads `inkstead-writer.json`.

Writer builds a custom not-found page at `dist/404.html`. Cloudflare Workers deployments serve that file through asset binding 404 handling, and Pages-style static hosts such as Cloudflare Pages, GitHub Pages, and Forgejo Pages include it in their uploaded artifact.

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

The migrate command updates generated workflow files such as `.github/workflows/publish.yml`, `.gitlab-ci.yml`, `.forgejo/workflows/publish.yml`, and the root `./inkstead-writer` wrapper.

Adapter guides:

- [Cloudflare Workers](./cloudflare-workers/)
- [Netlify](./netlify/)
- [GitHub Pages](./github-pages/)
- [GitLab Pages](./gitlab-pages/)
