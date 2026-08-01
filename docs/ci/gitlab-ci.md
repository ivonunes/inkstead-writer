# GitLab CI

GitLab CI is GitLab's built-in pipeline service. If your site lives on GitLab, the generated pipeline publishes it every time you push, so a finished post goes live on its own.

Inkstead Writer can generate a `.gitlab-ci.yml` pipeline during `inkstead-writer init`. The pipeline runs when you push and can also be started manually from GitLab. It runs:

```bash
./inkstead-writer publish
```

If you choose [GitLab Pages](../deployment/gitlab-pages.md) as the publishing target, Inkstead Writer generates a Pages-specific pipeline instead.

## CI/CD variables

To see which variables your site needs, run:

```bash
./inkstead-writer requirements
```

Add the listed environment variable names as GitLab CI/CD variables. The exact list depends on your publishing and syndication setup.

## Saving syndication links

When syndication adds links to your posts, the pipeline commits them back to the repository, which requires GitLab to allow the pipeline token to push. See [Saving syndication links](index.md#saving-syndication-links) for how this works.
