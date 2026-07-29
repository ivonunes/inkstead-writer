# Inkstead Writer

Inkstead Writer is an opinionated publishing engine for personal indie websites. Write in Markdown, build a static site, deploy anywhere, and optionally syndicate posts to social media.

Inkstead Writer supports macOS and Linux.

## Get Started

Install the `inkstead-writer` launcher, then create and preview a site:

```bash
curl -fsSL https://install.inkstead.app | sh
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

The full documentation is available at [inkstead.app/writer](https://inkstead.app/writer).

Inside a site, use the generated `./inkstead-writer` command. It keeps that site on the Inkstead Writer version recorded in `inkstead-writer.json`. Use `inkstead-writer init --help` to see options for publishing, CI, syndication, and app connection setup.

## Plume

Inkstead Writer themes are written in Plume, a templating language for building expressive websites. Plume brings HTML, styles, assets, and behaviour into one authoring model. Inkstead Writer includes Plume, so theme commands run through `./inkstead-writer theme ...` without a separate Plume install.
