# Syndication

When you publish a post, Inkstead Writer can also share it to your social media accounts. This is called syndication: your website stays the post's home, and the social copies link back to it. Syndication is optional, and each post chooses whether to take part.

## Enabling providers

Choose services during `inkstead-writer init`, or add them later to `inkstead-writer.json`. The site-level configuration lists the enabled providers:

```json
{
  "syndication": {
    "providers": ["mastodon", "bluesky"]
  }
}
```

Provider names are `mastodon`, `bluesky`, `pixelfed`, `flickr` and `buffer`. Enabled providers are offered as defaults when you create posts, and the `doctor` and `requirements` commands check that everything they need is in place.

Buffer reaches several networks from one account, so its targets name the network too, as `buffer:x` or `buffer:linkedin`. See the [Buffer guide](buffer.md).

## Opting a post in

Enabling a provider only makes it available; each post still opts in individually. Add a `syndicate` list to a post's frontmatter:

```yaml
syndicate:
  - provider-name
```

When you publish, the post goes to every provider in its list.

## What each post sends

Titled posts go out as the title plus a link to the post on your site. Untitled notes go out as native social posts made from their text. Untitled photo notes go out as native social posts with the photos attached, when the chosen service supports media uploads.

When a service has image size or dimension limits, Inkstead Writer prepares temporary optimised copies of a photo note's images to fit. Your original files stay unchanged.

`./inkstead-writer publish` deploys the site before syndication runs; see [what publishing does](../deployment/index.md#what-publishing-does) for the full order.

## How results are recorded

After each attempt, Inkstead Writer writes the result back into the post's frontmatter under `syndication`, so the post itself records what happened. A successful target looks like this:

```yaml
syndication:
  provider-name:
    status: published
    url: https://social.example/you/123
```

A failed target records the error instead:

```yaml
syndication:
  provider-name:
    status: failed
    error: "provider-name returned 403: ..."
```

Recorded targets are never attempted again automatically, so publishing again will not repost. A syndication failure is logged but does not fail `publish` or your CI pipeline; the rest of your site still goes out.

## Retrying a failed target

Fix the cause, then delete that provider's entry from the post's `syndication` block and publish again.

## Provider guides

- [Bluesky](bluesky.md)
- [Buffer](buffer.md)
- [Mastodon](mastodon.md)
- [Pixelfed](pixelfed.md)
- [Flickr](flickr.md)
