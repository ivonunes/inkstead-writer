# Getting Started

Inkstead Writer turns a folder of Markdown files into a personal website. The quickest path is:

Inkstead Writer runs through a small POSIX launcher script that downloads the right single Swift binary for each site. macOS and Linux are the supported release targets.

Install the launcher:

```bash
curl -fsSL https://install.inkstead.dev/writer | sh
```

Or, on macOS with Homebrew:

```bash
brew tap ivonunes/tap
brew install inkstead-writer
```

Then create and run a site:

```bash
inkstead-writer init my-site
cd my-site
./inkstead-writer dev
```

The installer writes to `/usr/local/bin` by default. To install somewhere else, run:

```bash
curl -fsSL https://install.inkstead.dev/writer | sh -s -- --dir "$HOME/.local/bin"
```

During `init`, choose where you want to deploy, whether you want automated publishing, whether posts should syndicate to social media, and whether you want to configure the Inkstead app connection up front. The global launcher downloads the latest release for `init`, and generated sites include a root `./inkstead-writer` wrapper that downloads the recorded Inkstead Writer version into the user Inkstead Writer cache when needed. You can start small and add more later in `inkstead-writer.json`.

![A starter Inkstead Writer website running locally.](/assets/getting-started-site.png)

Open the local URL printed by `./inkstead-writer dev`, then edit the starter content:

- `content/posts` contains dated posts for your homepage and feeds.
- `content/pages` contains standalone pages like About or Now.
- `content/media` contains original photo files you want to keep with the site.
- `content/collections` can contain custom Markdown collections for structured content.

## Your First Post

Create a Markdown file in `content/posts`:

```md
---
title: Hello From My Website
date: 2026-05-10T18:30:00+01:00
---

This is my first Inkstead Writer post.
```

Run `./inkstead-writer dev` and the post appears on the homepage. Posts use dated permalinks by default, such as `/2026/05/10/hello-from-my-website/`.

## Build The Site

When you are ready to generate the static site:

```bash
./inkstead-writer build
```

The built website is written to `dist`.

## Publish It

If you chose a deployment target during `init`, publish with:

```bash
./inkstead-writer publish
```

`publish` builds the site, deploys it, syndicates any posts that ask to be syndicated, then updates the site again if new syndication links were added.

Before publishing, fill in `.env` for local publishing. If you chose automated publishing, add the same values as CI secrets or variables.

Run `./inkstead-writer doctor` before publishing to check your config, content, deployment setup, and required environment variables.
