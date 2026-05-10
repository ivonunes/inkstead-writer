# GitLab Pages

Inkstead can publish a site with GitLab Pages through GitLab CI.

Choose GitLab Pages during `npx inkstead init`, or add this to `site.config.ts` later:

```ts
deploy: {
  provider: "gitlab-pages"
}
```

GitLab Pages is published by GitLab CI. Local `npm run deploy` does not publish directly to GitLab Pages.

## Publishing

When GitLab Pages is selected during `init`, Inkstead generates `.gitlab-ci.yml` with a Pages job that:

- installs dependencies
- runs `npm run build`
- deploys the built site to GitLab Pages

If syndication is enabled, the pipeline publishes the site first, then syndicates posts, saves the new links, and publishes the updated site again.

## Variables

GitLab Pages itself does not need deployment secrets. If you use syndication, add the provider variables from `.env.example` as GitLab CI/CD variables.

## Build Output

By default, Inkstead builds to `dist`, and the GitLab Pages workflow publishes `dist`. If you change `build.output`, regenerate or update `.gitlab-ci.yml` so the Pages `publish` path matches.
