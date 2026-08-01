# Themes

Inkstead Writer ships with a default theme, so a new site looks finished from day one. When you want your own design, you replace parts of the theme with `.plume` template files, and anything you do not replace keeps using the default.

Plume is the template language used by Inkstead Writer. This page focuses on how Inkstead Writer loads themes and what data it passes to them. For the language itself, use the [Plume syntax reference](https://plumekit.dev/docs/syntax/), [component guide](https://plumekit.dev/docs/components/), [resources guide](https://plumekit.dev/docs/customise/resources/) and [behaviour guide](https://plumekit.dev/docs/customise/behaviour/).

In this guide you will learn:

- how to start from the default theme and override parts of it
- which page templates Inkstead Writer looks for and what data they receive
- how assets, images, styles and scripts work in templates
- how to customise feeds, layouts and the footer

## Starting from the default theme

The easiest way to learn the theme structure is to copy the default templates into your site:

```bash
./inkstead-writer theme eject
```

Existing files are left alone. Use `--force` if you want to overwrite them.

You do not need to eject everything to customise a site. Any file you add under `theme` overrides the matching built-in file, and missing files continue to use the default theme.

## Theme folder

The recommended shape is:

```txt
theme/
  layouts/
    default.plume
  pages/
    404.plume
    home.plume
    category.plume
    post.plume
    page.plume
    feed.xml.plume
    feed.json.plume
  components/
    PostCard.plume
  styles/
    site.css
  scripts/
    site.plume
```

If you want to keep themes somewhere else, set `theme.path` in [Site Configuration](site-configuration.md).

## Page templates

Inkstead Writer looks for these page templates under `theme/pages`:

- `404.plume` for the not-found page written to `/404.html`.
- `home.plume` for the homepage.
- `category.plume` for category indexes.
- `post.plume` for posts.
- `page.plume` for standalone pages.
- `feed.xml.plume` for RSS feeds.
- `feed.json.plume` for JSON Feed.

Standalone pages can also use slug-specific templates. For example, `content/pages/photos.md` normally renders with `page.plume`, but `theme/pages/photos.plume` takes over that page when it exists:

```txt
content/pages/photos.md
theme/pages/photos.plume
```

```plume
<h1>{page.title}</h1>

<div class="photo-grid">
  @for post in photoPosts {
    <a href="{post.urlPath}">
      @image(post.firstImage, alt: post.alt | default(""))
    </a>
  }
</div>
```

The not-found page receives a `notFound` object with `title`, `description` and `message` fields.

## Plume in Inkstead Writer

Inkstead Writer marks generated content HTML as safe, so `{post.html}`, `{post.excerpt}`, `{page.html}` and `{content}` render as HTML without `| raw`. Ordinary strings still escape by default.

Use `| raw` only when you intentionally need to render your own trusted string as HTML.

## Theme commands

Check a theme without building the site:

```bash
./inkstead-writer theme check
```

Format templates:

```bash
./inkstead-writer theme format
./inkstead-writer theme format --check
```

Run the language server, the tool that gives your editor checking and completions as you type:

```bash
./inkstead-writer theme language-server
```

Inkstead Writer includes Plume, so the `./inkstead-writer` wrapper uses the Plume version tied to that site. Standalone Plume CLI and editor details live in the [Plume tooling docs](https://plumekit.dev/docs/tooling/).

## Assets and images

Use `asset()` for theme files that should be copied to the built site with a fingerprinted URL, a filename that changes whenever the file changes, so browsers never serve a stale copy:

```plume
<img src="{asset('images/avatar.png')}" alt="Ivo">
```

Relative asset paths are resolved relative to the template or component file first, then relative to the theme folder. Theme assets are emitted under `/assets/plume/`.

For images, prefer `@image`. Inkstead Writer resolves the asset, fingerprints theme images, adds dimensions when it can read them and defaults to `loading="lazy"` and `decoding="async"`:

```plume
@image("images/avatar.png", alt: "Ivo", class: "avatar", sizes: "64px")
```

Add `widths:` to generate responsive variants and a `srcset` automatically:

```plume
@image("images/hero.jpg", alt: "Coastal path", widths: [480, 960, 1440], sizes: "(min-width: 960px) 960px, 100vw")
```

Site media references such as `/media/photo.jpg` keep their public media path. Theme-local images and responsive variants are copied to `/assets/plume/`.

For static files that should be copied without Plume processing, use passthrough assets in `inkstead-writer.json`. See [Site Configuration](site-configuration.md).

## Styles and scripts

Plume templates can declare styles and scripts next to the markup that uses them. Inkstead Writer extracts those resources into fingerprinted files under `/assets/plume/` and injects them into the page:

```plume
@style(file: "styles/site.css")
@script(file: "scripts/site.plume")
```

You can also write inline resource blocks:

```plume
@style(scoped) {
  .photo-grid {
    display: grid;
    gap: 1rem;
  }
}

@script {
  let menu = page.query("#menu")

  on ".menu-toggle".click {
    menu.toggleClass("is-open")
  }
}
```

For the full resource model, see [Plume resources](https://plumekit.dev/docs/customise/resources/).

## Interactivity

Themes can respond to clicks and other browser events without you writing separate JavaScript. Inkstead Writer emits `/assets/plume-runtime.js` only on pages that use Plume state, state bindings, style bindings, browser actions or enhanced navigation:

```plume
@state expanded = false

<button on:click="{expanded.toggle()}" aria-expanded="{expanded}">
  {expanded ? "Hide" : "Show"} details
</button>

<section hidden?="{!expanded}" class:open="{expanded}">
  {post.excerpt}
</section>
```

Use `@navigation` in `theme/layouts/default.plume` when same-origin links should fetch and swap page content without a full reload:

```plume
@navigation(root: "main", viewTransitions: true, scroll: "top") {
  on:beforeSwap {
    page.addClass("is-leaving")
  }

  on:afterSwap {
    page.removeClass("is-leaving")
  }
}
```

See the [Plume behaviour guide](https://plumekit.dev/docs/customise/behaviour/) for state, actions, measurement, viewport events, scripts and navigation hooks.

## Template context

Templates receive:

- `site`
- `config`
- `posts`
- `pages`
- `categories`
- `photoPosts`
- `data`, containing configured build-time JSON data sources
- `collections.posts`
- `collections.pages`
- `collections.categories`
- `collections.photoPosts`
- `collections.<name>`, for custom Markdown collections
- `pagination` on index and category pages
- `post` on post pages
- `page` on page pages
- `category` on category pages
- `notFound` on the 404 page
- `meta`
- `now`, including `now.year`

`meta` includes `title`, `canonicalUrl` and `description`. Post and page pages use an excerpt of their own content for `meta.description`; index and category pages use `site.description`.

Post objects include `previous` and `next` so themes can add post navigation.

`photoPosts` is intended for photography grids. It includes photo notes whose primary image is not a PNG, so screenshots and other PNG notes do not appear there by default.

Custom collections are exposed by folder name. For example, Markdown files in `content/collections/books` are available as `collections.books`:

```plume
@for book in collections.books {
  <article>
    <h2>{book.title}</h2>
    <p>{book.author}</p>
    {book.content}
  </article>
}
```

Configured data sources are exposed under `data`:

```plume
@for event in data.events {
  <article>
    <h2>{event.title}</h2>
    <time datetime="{event.date}">{event.date}</time>
  </article>
}
```

See [Site Configuration](site-configuration.md) for configuring collections and data sources.

## Layouts

If a template returns a full HTML document, Inkstead Writer uses it as-is. Otherwise, the rendered content is wrapped in a layout.

Override `theme/layouts/default.plume` to control the document shell.

## Feed templates

Inkstead Writer writes RSS at `/feed.xml` and JSON Feed at `/feed.json`.

Override these files to customise them:

```txt
theme/pages/feed.xml.plume
theme/pages/feed.json.plume
```

Both templates receive a `feed` object with:

- `title`
- `description`
- `url`
- `path`
- `items`
- `category`

Category feeds use the same templates with `feed.category` populated and `feed.items` scoped to that category.

RSS browser presentation is optional. In `theme/pages/feed.xml.plume`, declare `@style` and `@script` resources, then include `feed.presentationScriptSrc` where you want the browser presentation script to appear. RSS readers still receive RSS.

## Footer attribution

The default templates include a copyright notice and a small `Written in Inkstead` link. To remove the attribution without ejecting or editing the default templates, set:

```json
{
  "theme": {
    "showPoweredBy": false
  }
}
```

## Build hooks

Use hooks when a theme needs generated assets before Inkstead Writer copies passthrough files or resolves Plume asset references. A common use is bundling larger JavaScript modules or compiling CSS before referencing the output with `@script(file:)` or `@style(file:)`:

```json
{
  "hooks": {
    "beforeBuild": ["./build-theme-assets.sh"]
  }
}
```

This keeps bundling outside the engine while still making `./inkstead-writer build` produce a complete site.
