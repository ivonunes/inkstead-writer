# Troubleshooting

Start with:

```bash
./inkstead-writer doctor
```

Doctor checks config, content folders, environment variables, CI setup, deployment requirements, syndication requirements, and common content errors.

## AI Coding Agents

Interactive `inkstead-writer init` can generate an `AGENTS.md` file with project-specific Inkstead Writer and Plume guidance.

## Common Fixes

If environment variables are missing, copy `.env.example` to `.env` for local publishing and fill in the values. For CI publishing, add the same names as secrets or variables.

If a post does not appear, check that it is in `content/posts`, has a valid `date`, and is not saved as a page.

If deployment fails, run `./inkstead-writer build` first. If the build works but publish fails, check the deployment service secrets.

If syndication reposts unexpectedly, check the post frontmatter. Published providers should have `syndication.<provider>.status: published`.

On Windows, use `./inkstead-writer build` and serve the output directory with another local static server. The built site, configuration, templates, deployment, and syndication code are written to be portable, but the built-in `./inkstead-writer dev` server currently only runs on macOS and Linux.
