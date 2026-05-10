# Deployment

Inkstead can publish through deployment adapters without changing how you write posts or build themes.

Choose a deployment target during `npx inkstead init`, or change it later in `site.config.ts`.

Some deployment adapters require a matching CI adapter. Inkstead validates adapter combinations when it loads `site.config.ts`.

Adapter guides:

- [Cloudflare Workers](./cloudflare-workers/)
- [GitHub Pages](./github-pages/)
- [GitLab Pages](./gitlab-pages/)
