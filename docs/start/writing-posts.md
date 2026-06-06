# Writing Posts

Posts live in `content/posts` as Markdown files with optional frontmatter.

```md
---
title: A Post Title
date: 2026-05-10T18:30:00+01:00
---

Your post content goes here.
```

To create a post locally with the right filename and frontmatter:

```bash
inkstead-writer new post
```

Inkstead Writer asks whether the post is a long article or a note. Articles get a `title` field and an empty body; notes use the text you enter as the body and omit `title`.

If syndication is enabled for the site, new articles and notes include the enabled text-capable providers in `syndicate` by default. Photo-only providers are skipped for text posts.

The paths on this page use the default site structure. You can change the content folders in [Site Configuration](/start/site-configuration/).

## Articles, Notes, And Photo Notes

Inkstead Writer infers the kind of post from the content:

- Posts with a `title` are articles.
- Posts without a `title` are notes.
- Untitled posts with images are photo notes.

Inkstead Writer infers photo notes from Markdown or HTML images in the body.

Pages live in `content/pages` and never syndicate.

## Collections

Custom collections live in `content/collections/<name>` as Markdown files. They are useful for structured content that is not part of the blog timeline, such as books, projects, albums, talks, or links.

```txt
content/collections/books/the-left-hand-of-darkness.md
```

```md
---
title: The Left Hand of Darkness
author: Ursula K. Le Guin
order: 1
---

Notes about the book.
```

The collection name must be a valid Plume identifier, such as `books` or `projects`. Frontmatter fields are exposed to templates, and the Markdown body is available as rendered HTML.

Items with `status: draft` are skipped. Items sort by `order` ascending when present, then by `date` descending, then by title and path.

See [Themes](/start/themes/) for rendering collections in templates.

## Permalinks

Posts use dated permalinks by default:

```txt
/2026/05/10/my-post/
```

That keeps URLs stable even if two posts share similar titles over time.

## Photos

For photo posts, add a Markdown image to an untitled post:

```md
---
date: 2026-05-10T18:30:00+01:00
---

Morning coffee.

![](/media/coffee.jpg)
```

You can keep original files in the media folder and reference the public path you want your theme to render.

During builds, Inkstead Writer copies the media folder to `/media/`. It resizes very large JPEG, PNG, and WebP images to a reasonable web size and strips metadata from the copied files on macOS and Linux. Your originals are left unchanged. Passthrough assets are not optimised.

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

Posts can include one or more categories:

```yaml
categories:
  - Photography
  - Travel
```

When categories are present, Inkstead Writer generates paginated category indexes at `/categories/<category>/`, RSS feeds at `/categories/<category>/feed.xml`, and JSON feeds at `/categories/<category>/feed.json`.

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

Article index excerpts use `summary` frontmatter when present:

```yaml
summary: A short custom introduction for index pages.
```

Without `summary`, Inkstead Writer uses the content before `<!--more-->`.

```md
This appears on index pages.

<!--more-->

This only appears on the post page.
```

Themes can use `post.excerpt` and `post.hasMore`. `post.excerpt` is rendered HTML, so Markdown links and formatting work on index pages.

If neither `summary` nor `<!--more-->` exists, Inkstead Writer creates a short excerpt from the post body automatically.

## Raw HTML And Line Breaks

Markdown supports raw HTML and hard line breaks by default. That means small HTML snippets are preserved, and single newlines inside a paragraph render as `<br>`.
