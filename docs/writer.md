# Inkstead Writer

Inkstead Writer is an optional writing interface that ships with Inkstead. It is a small static app for creating, editing, previewing, publishing, and deleting Markdown posts stored in your site repository.

Writer is intentionally minimal: no database, no hosted service, and no CMS complexity.

![Inkstead Writer showing the posts list.](/assets/writer-posts.png)

## Enable Writer

Choose Writer during `npx inkstead init`, or add a `writer` section to `site.config.ts` later:

```ts
import { defineConfig } from "inkstead";

export default defineConfig({
  site: { title: "My Website", url: "https://example.com", author: "Your Name" },
  content: { posts: "content/posts", pages: "content/pages", media: "content/media" },
  writer: {
    enabled: true,
    path: "/writer",
    provider: "github",
    owner: "example-user",
    repo: "example-site",
    branch: "main",
    categories: ["Photography", "Essays"]
  }
});
```

When you build the site, Inkstead copies Writer into the output directory at `/writer` by default and writes a public `inkstead-writer.config.json` file next to it.

Secrets are never written to this config file. Writer asks for a personal access token in the browser.

![Inkstead Writer editing a post.](/assets/writer-editor.png)

## Categories

Writer can show category toggles for the categories you use most often:

```ts
writer: {
  enabled: true,
  provider: "github",
  owner: "example-user",
  repo: "example-site",
  branch: "main",
  categories: ["Photography", "Essays"]
}
```

If `categories` is omitted or empty, Writer does not show category controls.

## Providers

Writer supports:

- `github`
- `gitlab`
- `forgejo`
- `local`

Use `github`, `gitlab`, or `forgejo` for published sites. Use a personal access token that is limited to the target repository and has repository contents read/write permissions.

For GitLab, `owner` may include nested groups:

```ts
writer: {
  enabled: true,
  path: "/writer",
  provider: "gitlab",
  owner: "group/subgroup",
  repo: "example-site",
  branch: "main"
}
```

For Forgejo, set `instanceUrl` to the base URL of your Forgejo instance:

```ts
writer: {
  enabled: true,
  path: "/writer",
  provider: "forgejo",
  instanceUrl: "https://codeberg.org",
  owner: "example-user",
  repo: "example-site",
  branch: "main"
}
```

## Local Development

When you run:

```bash
npm run dev
```

Inkstead automatically uses the local filesystem provider for Writer if Writer is enabled. This happens even if your config is set to `github`, `gitlab`, or `forgejo`.

In local mode, Writer does not ask for a token. It writes directly to your working copy through the Inkstead dev server. The local API is only available from the dev server and only writes inside the configured post and media directories.

Open Writer at:

```text
http://localhost:4321/writer/
```

## Mobile App

Writer is installable as a Progressive Web App on supported mobile browsers.

Open `/writer/` on your phone and use the browser’s Add to Home Screen or Install action.
