# Syndication

Syndication is optional. Choose services during `inkstead-writer init`, or add them later in `inkstead-writer.json` when you want Inkstead Writer to publish posts to social platforms as part of `./inkstead-writer publish`.

The site-level configuration lists the enabled providers:

```json
{
  "syndication": {
    "providers": ["mastodon", "bluesky"]
  }
}
```

Provider names are `mastodon`, `bluesky`, `pixelfed`, `flickr`, and `buffer`. Enabled providers are offered as defaults when you create posts and are checked by `doctor` and `requirements`.

Buffer reaches several networks from one account, so its targets name the network too, as `buffer:x` or `buffer:linkedin`. See the [Buffer guide](/syndication/buffer/).

Each post still opts in individually. Add `syndicate` to a post:

```yaml
syndicate:
  - provider-name
```

Titled posts syndicate as title plus canonical URL. Untitled notes syndicate as native social posts. Untitled photo notes syndicate as native social posts with attached photos when the selected provider supports media uploads.

For photo notes, Inkstead Writer prepares temporary optimised copies when a service has image size or dimension limits. Your original files stay unchanged.

After each attempt, Inkstead Writer writes the result back to the post under `syndication`, so the post records what happened. Successful targets are marked `published`, failed targets record the error, and recorded targets are never attempted again automatically. Syndication failures are logged but do not fail `publish` or your CI pipeline.

To retry a failed target, fix the cause, then delete that provider's entry from the post's `syndication` block and publish again.

Example results:

```yaml
syndication:
  provider-name:
    status: published
    url: https://social.example/you/123
```

```yaml
syndication:
  provider-name:
    status: failed
    error: "provider-name returned 403: ..."
```

`./inkstead-writer publish` deploys the website before syndication runs so canonical links are already live.

Provider guides:

- [Bluesky](/syndication/bluesky/)
- [Buffer](/syndication/buffer/)
- [Mastodon](/syndication/mastodon/)
- [Pixelfed](/syndication/pixelfed/)
- [Flickr](/syndication/flickr/)
