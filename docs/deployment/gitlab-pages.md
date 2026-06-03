# GitLab Pages

Inkstead Writer can publish a site with GitLab Pages through GitLab CI.

Choose GitLab Pages during `inkstead-writer init`, or add this to `inkstead-writer.json` later:

```json
{
  "deploy": {
    "provider": "gitlab-pages"
  }
}
```

GitLab Pages is published by GitLab CI. Local `./inkstead-writer deploy` does not publish directly to GitLab Pages.

## Publishing

When GitLab Pages is selected during `init`, Inkstead Writer generates `.gitlab-ci.yml` with a Pages job that:

- installs wrapper dependencies
- runs `./inkstead-writer publish`
- deploys the built site to GitLab Pages

If syndication is enabled, the pipeline publishes the site first, then syndicates posts, saves the new links, and publishes the updated site again.

## Variables

GitLab Pages itself does not need deployment secrets. If you use syndication, add the provider variables from `.env.example` as GitLab CI/CD variables.

Run `./inkstead-writer doctor` locally if you want to check content, config, and any syndication variables before pushing.

## Build Output

By default, Inkstead Writer builds to `dist`, and the GitLab Pages workflow publishes `dist`. If you change `build.output`, regenerate or update `.gitlab-ci.yml` so the Pages `publish` path matches.
