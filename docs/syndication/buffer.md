# Buffer

Buffer is a service that publishes to several social networks from one account. Connecting it to Inkstead Writer once reaches X, LinkedIn, Threads, Facebook, Instagram and Pinterest, without a separate developer account for each.

Mastodon, Bluesky, Pixelfed and Flickr are not offered through Buffer. Inkstead Writer publishes to those directly, and going through Buffer as well would post twice.

## Getting a key

Generate a personal API key in Buffer under Account, then API. Keys are available on every Buffer plan, including the free one. Only organisation owners can create them.

Set it as `BUFFER_API_KEY` alongside your other syndication secrets, in your site's `.env` file for local publishing or as a CI secret or variable.

## Choosing channels

A Buffer target names the network rather than a channel ID, so nothing in your site records an identifier that could go stale:

```json
{
  "syndication": {
    "providers": ["mastodon", "buffer:x", "buffer:linkedin"]
  }
}
```

The channel is resolved at publish time from the key itself, which means a site configured by hand, or restored onto a new machine, keeps working with no extra setup.

If one Buffer organisation holds more than one account on the same network, name the account too. It matches the channel name shown in Buffer:

```json
{
  "syndication": {
    "providers": ["buffer:x@ivonunes", "buffer:x@clientco"]
  }
}
```

Without an account, a target posts to every channel on that network. If a target matches nothing, Inkstead Writer records the failure and moves on; it never falls back to a different channel.

Posts opt in the same way as any other target:

```yaml
syndicate:
  - buffer:x
  - buffer:linkedin
```

## Network names

Use `x`, `linkedin`, `threads`, `facebook`, `instagram` and `pinterest`. Buffer's own name for a network is also accepted, so `buffer:twitter` works and means the same as `buffer:x`.

TikTok, YouTube Shorts and Google Business Profile are not supported. The first two want video, and Google Business Profile publishes by sending a reminder to your phone rather than posting.

## What gets posted

Most networks get the post's title and a link to it, trimmed to the network's limit with the link kept.

LinkedIn gets the post itself: the body first, then the title and the link at the end, because LinkedIn posts are read in place rather than clicked through. Untitled notes are skipped there.

LinkedIn rejects anything over 3,000 characters, so a longer post is cut to fit. The cut lands on a paragraph break where one is close enough, otherwise between words, and the title and link always survive. That is around 500 words; posts longer than that go out as an excerpt.

Instagram and Pinterest carry a picture rather than a link, so only photo notes go to them. The post's first image is used.

Photo notes attach their picture everywhere. Titled articles do not: their link already shows your site's own preview image, and attaching a copy would put the same picture in the post twice. Buffer fetches media from your site by URL; syndication runs after the deploy, so the images are already published.

Everything publishes immediately rather than joining your Buffer queue.

## Instagram

Automatic publishing needs an Instagram Business or Creator account. Personal profiles can only publish by notification, where Buffer pushes a reminder and you finish the post by hand, so they are not usable for syndication.

## Results

Buffer results are recorded per network, nested under `buffer`:

```yaml
syndication:
  buffer:
    x:
      status: published
      id: abc123
    linkedin:
      status: failed
      error: Buffer has no buffer:linkedin channel connected to this key.
```

To retry a network, delete its entry and publish again.

See [Syndication](index.md) for how results work across providers.
