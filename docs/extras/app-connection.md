# App Connection

The Inkstead app can connect to an Inkstead Writer site so it knows which repository to edit, where posts and media live, and which posting categories or syndication providers are available.

You can configure this during `inkstead-writer init`, or add it later in `inkstead-writer.json`.

## Configure

Add a `connection` section:

```json
{
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

If you leave `connection` out of the config, Inkstead Writer still tries to infer useful values during CI builds.

On GitHub Actions, GitLab CI, or Forgejo Actions, the build can usually detect the provider, repository, branch, and instance URL from environment variables. If repository details are not available, the app can ask for them during setup.

## Published Site File

During builds, Inkstead Writer publishes a small public file at:

```text
/inkstead-writer.json
```

It does not contain tokens or secrets. It only contains public setup information for the app.

Example:

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
  "syndicationProviders": ["mastodon"]
}
```

The file also includes a `version` field recording the Inkstead Writer release that built the site.

Authentication happens in the app. Inkstead Writer never writes access tokens into the built website.
