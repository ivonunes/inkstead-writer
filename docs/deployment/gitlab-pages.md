# GitLab Pages

If your site lives in a GitLab repository, GitLab Pages can host it. Publishing runs through GitLab CI: you push your writing, and a pipeline builds and deploys the site for you.

## Configuration

Choose GitLab Pages during `inkstead-writer init`, or add this to `inkstead-writer.json` later:

```json
{
  "deploy": {
    "provider": "gitlab-pages"
  }
}
```

## Publishing

When GitLab Pages is selected during `init`, Inkstead Writer generates `.gitlab-ci.yml` with a Pages job. Push to GitLab, or start the pipeline manually from GitLab. The pipeline is described in [GitLab CI](../ci/gitlab-ci.md).

> **Note:** GitLab Pages is published by GitLab CI, so a local `./inkstead-writer deploy` does not publish directly to GitLab Pages.

## Variables

GitLab Pages itself does not need deployment secrets. If you use syndication, add the provider variables from `.env.example` as GitLab CI/CD variables.

If you want to check content, config and any syndication variables before pushing, run `./inkstead-writer doctor` locally.

## Build output

By default, Inkstead Writer builds to `dist` and the GitLab Pages workflow publishes `dist`. If you change `build.output`, regenerate or update `.gitlab-ci.yml` so the Pages `publish` path matches.
