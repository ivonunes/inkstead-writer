# Writing Posts

Every post on your site is a Markdown file in `content/posts`. This page covers the different kinds of post, how their URLs and categories work and what you can put in the frontmatter, the block between the `---` lines at the top of a file.

In this guide you will learn:

- how articles, notes and photo notes differ
- how permalinks, categories and pagination work
- how excerpts are chosen for index pages and feeds
- which frontmatter fields posts understand

A minimal post looks like this:

```md
---
title: A Post Title
date: 2026-05-10T18:30:00+01:00
---

Your post content goes here.
```

Dates accept ISO 8601 timestamps or a plain date like `date: 2026-05-10`. Timestamps without an explicit offset and plain dates are treated as UTC.

To create a post locally with the right filename and frontmatter:

```bash
./inkstead-writer new post
```

Inkstead Writer asks whether the post is a long article or a note. Articles get a `title` field and an empty body; notes use the text you enter as the body and omit `title`.

If [syndication](../syndication/index.md) is enabled for the site, new articles and notes include the enabled text-capable providers in `syndicate` by default. Photo-only providers are skipped for text posts.

The paths on this page use the default site structure. You can change the content folders in [Site Configuration](site-configuration.md).

## Articles, notes and photo notes

You never declare a kind of post. Inkstead Writer infers it from the content:

- Posts with a `title` are articles.
- Posts without a `title` are notes.
- Untitled posts with images are photo notes.

Inkstead Writer infers photo notes from Markdown or HTML images in the body.

Pages live in `content/pages` and never syndicate.

## Collections

Some content does not belong in the blog timeline: books you have read, projects, albums, talks or links. Custom collections hold that kind of structured content, as Markdown files in `content/collections/<name>`:

```txt
content/collections/books/the-left-hand-of-darkness.md
```

A collection item is an ordinary Markdown file whose frontmatter carries whatever fields you need:

```md
---
title: The Left Hand of Darkness
author: Ursula K. Le Guin
order: 1
---

Notes about the book.
```

The collection name is used as a name in [templates](themes.md), so keep it to letters and numbers with no spaces, such as `books` or `projects`. Frontmatter fields are exposed to templates, and the Markdown body is available as rendered HTML.

Items with `status: draft` are skipped. Items sort by `order` ascending when present, then by `date` descending, then by title and path.

See [Themes](themes.md) for rendering collections in templates.

## Permalinks

Posts use dated permalinks by default:

```txt
/2026/05/10/my-post/
```

That keeps URLs stable even if two posts share similar titles over time.

## Photos

When you want to post a photo, add a Markdown image to an untitled post:

```md
---
date: 2026-05-10T18:30:00+01:00
---

Morning coffee.

![](/media/coffee.jpg)
```

You can keep original files in the media folder and reference the public path you want your theme to render.

During builds, Inkstead Writer copies the media folder to `/media/`. It resizes very large JPEG, PNG and WebP images to a reasonable web size and strips metadata from the copied files on macOS and Linux. Your originals are left unchanged. Passthrough assets are not optimised.

You can tune or disable this in `inkstead-writer.json`:

```json
{
  "media": {
    "optimize": true,
    "maxWidth": 2400,
    "maxHeight": 2400,
    "quality": 82
  }
}
```

## Categories

To group related posts, give them one or more categories:

```yaml
categories:
  - Photography
  - Travel
```

When categories are present, Inkstead Writer generates paginated category indexes at `/categories/<category>/`, RSS feeds at `/categories/<category>/feed.xml` and JSON feeds at `/categories/<category>/feed.json`.

Posts in nested folders under `content/posts` also receive categories from their directory names. For example, `content/posts/essays/my-post.md` is assigned to `Essays` even without category frontmatter. Posts directly inside `content/posts` only use frontmatter categories.

## Pagination

Inkstead Writer paginates the homepage and category indexes automatically. By default, each index page shows 20 posts before creating pages like:

```txt
/page/2/
/categories/photography/page/2/
```

The default theme includes `Newer` and `Older` links when more pages exist.

To change the number of posts per page:

```json
{
  "pagination": {
    "postsPerPage": 10
  }
}
```

## Excerpts

Index pages show a short excerpt of each article rather than the whole post. You control what appears with `summary` frontmatter:

```yaml
summary: A short custom introduction for index pages.
```

Without `summary`, Inkstead Writer uses the content before `<!--more-->`:

```md
This appears on index pages.

<!--more-->

This only appears on the post page.
```

Themes can use `post.excerpt` and `post.hasMore`. `post.excerpt` is rendered HTML, so Markdown links and formatting work on index pages.

If neither `summary` nor `<!--more-->` exists, Inkstead Writer creates a short excerpt from the post body automatically.

## Frontmatter reference

Posts understand these frontmatter fields. Everything except `date` is optional.

| Field | What it does |
| --- | --- |
| `title` | The post title. Posts without one are notes. |
| `date` | When the post was published. ISO 8601 timestamps and plain dates work; values without an offset are UTC. |
| `lastmod` | When the post was last updated. Feeds use it for the modified date. |
| `summary` | A custom excerpt for index pages and feeds. |
| `categories` | A list of category names. |
| `status` | Set to `draft` to keep the post out of builds. |
| `url` | A custom permalink that replaces the default dated URL. |
| `photos` | Image paths to treat as the post's photos, in addition to images in the body. |
| `alt` | Alt text for the post's primary image, available to themes as `post.alt`. |
| `syndicate` | The providers this post should syndicate to. See [Syndication](../syndication/index.md). |
| `syndication` | Written by Inkstead Writer after [syndication](../syndication/index.md), recording each provider's status and link. You normally never edit this. |

Pages in `content/pages` use `title`, and collection items can carry any fields your templates want; see [Collections](#collections).

## Markdown flavour

Posts render with CommonMark plus GitHub Flavored Markdown extensions: tables, strikethrough, task lists, autolinked URLs and footnotes. Fenced code blocks keep their language as a `language-<name>` class for client-side highlighters.

Smart punctuation is applied outside code: `...` becomes `…`, straight quotes become curly quotes and `--`/`---` become en and em dashes. Code spans and code blocks are left untouched.

## Raw HTML and line breaks

Markdown supports raw HTML and hard line breaks by default. That means small HTML snippets are preserved, and single newlines inside a paragraph render as `<br>`.
