# GitLab CI

Inkstead Writer can generate a `.gitlab-ci.yml` pipeline during `inkstead-writer init`.

The pipeline runs on `main` and can also be started manually from GitLab. It runs:

```bash
./inkstead-writer publish
```

If you choose [GitLab Pages](/deployment/gitlab-pages/) as the publishing target, Inkstead Writer generates a Pages-specific pipeline instead.

## CI/CD Variables

Run `./inkstead-writer requirements`, then add the listed environment variable names as GitLab CI/CD variables. The exact list depends on your publishing and syndication setup.

## Syndication Metadata Commits

When syndication adds links to your posts in GitLab CI, Inkstead Writer commits those changes with `[skip ci]` and pushes them back to the repository.

GitLab must allow the pipeline token to push to the repository. If your project does not allow that, syndication can still publish, but the metadata commit will not be pushed back automatically.
