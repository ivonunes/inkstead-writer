# Bluesky

If you have a Bluesky account, Inkstead Writer can post to it whenever you publish. Connecting takes two settings: who you are and an app password that lets Inkstead Writer post for you.

Inkstead Writer reads two environment variables:

| Variable | What it is |
| --- | --- |
| `BLUESKY_IDENTIFIER` | Usually your handle, such as `example.com` or `you.bsky.social` |
| `BLUESKY_APP_PASSWORD` | An app password created for Inkstead Writer |

Set them in your site's `.env` file for local publishing, or as CI secrets or variables.

## Creating an app password

Use an app password rather than your main account password. Create one in Bluesky under Settings, then Privacy and Security, then App Passwords.

## What gets posted

Bluesky posts are limited to 300 characters. When a titled post would run over, Inkstead Writer shortens the title and keeps the link to your site intact.

Photo notes embed up to four images.

See [Syndication](index.md) for how posts opt in and how results are recorded.
