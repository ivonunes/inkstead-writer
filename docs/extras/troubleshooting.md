# Troubleshooting

When something is not working, start with the built-in checks, then jump to the section that matches your problem. Most issues come down to a missing setting or a file in the wrong place.

Run doctor first:

```bash
./inkstead-writer doctor
```

It reports anything wrong with your setup; see [what doctor checks](../start/commands.md#what-doctor-checks) for the full list.

## Missing environment variables

For local publishing, copy `.env.example` to `.env` and fill in the values. For publishing from CI, add the same names as secrets or variables.

## A post does not appear

Check that the file is in `content/posts`, has a valid `date` and is not saved as a page.

## Deployment fails

Run `./inkstead-writer build` first. If the build works but publish fails, check the secrets your publishing target needs.

## Syndication reposts unexpectedly

Check the post frontmatter. Providers that have already published should show `syndication.<provider>.status: published`; a post without that record will be attempted again.

## Syndication fails

The post records the provider's error under `syndication.<provider>.error`. Recorded targets are not attempted again automatically; to retry, delete that provider's entry from the post's `syndication` block and publish again.

A syndication failure never fails the publish or CI run.

## A date or URL is off by a day

Set `site.timezone` in `inkstead-writer.json`. Timestamps without an explicit offset are treated as UTC, and the timezone decides which calendar day a post falls on. See [Site Configuration](../start/site-configuration.md).

## Cache folders

Downloaded binaries and the media optimisation cache live in `~/Library/Caches/inkstead-writer` on macOS and `${XDG_CACHE_HOME:-$HOME/.cache}/inkstead-writer` on Linux.

`./inkstead-writer cache clean` prunes old binaries. The whole folder is also safe to delete; Inkstead Writer rebuilds it on the next run.

## Windows

The built-in `./inkstead-writer dev` server currently runs only on macOS and Linux. On Windows, use `./inkstead-writer build` and serve the output directory with another local static server.
