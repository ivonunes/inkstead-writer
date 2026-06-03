# App Connection

Inkstead can connect to an Inkstead Writer site from the native app. The site build publishes a small public file at the root of the generated site:

```text
/inkstead-writer.json
```

That file tells the app which repository backs the site, where posts and media live, which version of Inkstead Writer built the site, and which posting categories or syndication providers are available. It does not contain tokens or secrets.

## Configure

You can configure the app connection during `inkstead-writer init`, or add it later in `inkstead-writer.json`:

```json
{
  "version": "2.0.0",
  "site": {
    "title": "My Website",
    "url": "https://example.com",
    "author": "Your Name"
  },
  "connection": {
    "provider": "github",
    "repository": "owner/site",
    "branch": "main",
    "categories": ["Notes", "Photos"]
  }
}
```

`provider` can be `github`, `gitlab`, or `forgejo`.

`repository` is the repository owner and name, such as `owner/site`.

`branch` defaults to the branch detected by CI when available.

`instanceUrl` is useful for Forgejo or self-managed GitLab instances.

`categories` gives the app optional shortcuts when composing posts.

## Automatic Detection

If you leave the app connection out of the config, Inkstead Writer still tries to infer useful values during CI builds:

```json
{
  "version": "2.0.0",
  "site": {
    "title": "My Website",
    "url": "https://example.com",
    "author": "Your Name"
  },
  "ci": {
    "provider": "github-actions"
  }
}
```

On GitHub Actions, GitLab CI, or Forgejo Actions, the build can usually detect the provider, repository, branch, and instance URL from environment variables. If repository details are not available, the generated public file leaves them empty and the app can ask for them during setup.

## Public File

The generated `/inkstead-writer.json` file has this shape:

```json
{
  "branch": "main",
  "categories": ["Notes", "Photos"],
  "mediaPath": "content/media",
  "owner": "owner",
  "postsPath": "content/posts",
  "provider": "github",
  "repo": "site",
  "siteName": "My Website",
  "syndicationProviders": ["mastodon"],
  "version": "2.0.0"
}
```

The native app uses this file to understand the site before it asks you to authenticate with the backing repository provider. Authentication happens in the app; Inkstead Writer never writes access tokens into the built website.
