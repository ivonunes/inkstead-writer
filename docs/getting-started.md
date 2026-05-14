# Getting Started

Inkstead turns a folder of Markdown files into a personal website. The quickest path is:

```bash
npx inkstead init my-site
cd my-site
npm install
npm run dev
```

During `init`, Inkstead asks where you want to deploy, whether you want automated publishing, whether posts should syndicate to social media, and whether you want to enable Writer. You can start small and add more later in `site.config.ts`.

![A starter Inkstead website running locally.](/assets/getting-started-site.png)

Open the local URL printed by `npm run dev`, then edit the starter content:

- `content/posts` contains dated posts for your homepage and feeds.
- `content/pages` contains standalone pages like About or Now.
- `content/media` contains original photo files you want to keep with the site.

## Your First Post

Create a Markdown file in `content/posts`:

```md
---
title: Hello From My Website
date: 2026-05-10T18:30:00+01:00
---

This is my first Inkstead post.
```

Run `npm run dev` and the post appears on the homepage. Posts use dated permalinks by default, such as `/2026/05/10/hello-from-my-website/`.

## Build The Site

When you are ready to generate the static site:

```bash
npm run build
```

The built website is written to `dist`.

## Publish It

If you chose a deployment target during `init`, publish with:

```bash
npm run publish
```

`publish` builds the site, deploys it, syndicates any posts that ask to be syndicated, then updates the site again if new syndication links were added.

Before publishing, fill in `.env` for local publishing. If you chose automated publishing, add the same values as CI secrets or variables.

Run `npm run doctor` before publishing to check your config, content, deployment setup, and required environment variables.
