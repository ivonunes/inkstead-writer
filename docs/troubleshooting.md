# Troubleshooting

Start with:

```bash
npm run doctor
```

Doctor checks config, content directories, environment variables, CI setup, deployment requirements, syndication requirements, and obvious content errors.

## Common Fixes

If environment variables are missing, copy `.env.example` to `.env` for local publishing and fill in the values. For CI publishing, add the same names as secrets or variables.

If a post does not appear, check that it is in `content/posts`, has a valid `date`, and is not saved as a page.

If deployment fails, run `npm run build` first. If the build works but publish fails, check the deployment service secrets.

If syndication reposts unexpectedly, check the post frontmatter. Published providers should have `syndication.<provider>.status: published`.
