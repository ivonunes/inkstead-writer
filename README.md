# Inkstead Writer

Inkstead Writer is an opinionated publishing engine for personal indie websites. Write in Markdown, build a static site, deploy anywhere, and optionally syndicate posts to social media.

Inkstead Writer runs through a small POSIX launcher script that downloads the right single Swift binary for each site. macOS and Linux are the supported release targets.

## Get Started

The full documentation is available at [inkstead.dev](https://inkstead.dev/).

Install the `inkstead-writer` launcher, then create a site:

```bash
curl -fsSL https://install.inkstead.dev/writer | sh
inkstead-writer init my-site
cd my-site
./inkstead-writer doctor
./inkstead-writer dev
```

On macOS, you can also install with Homebrew:

```bash
brew tap ivonunes/tap
brew install inkstead-writer
```

Generated sites include a root `./inkstead-writer` wrapper. Commit it with the site; it downloads the version recorded in `inkstead-writer.json` into the user Inkstead Writer cache when needed. The global launcher also works for site commands when you run it from inside an existing site.

Use `inkstead-writer init --help` to see adapter options for deployment, CI, syndication, and app connection overrides.

## Plume

Inkstead Writer themes are written in Plume, a templating language for building expressive websites. Plume brings HTML, styles, assets, and behaviour into one coherent authoring model, while Inkstead Writer embeds it and exposes theme tooling through `inkstead-writer theme ...` so site-local wrappers do not need a separate Plume install.
