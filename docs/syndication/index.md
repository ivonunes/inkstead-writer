# Syndication

Syndication is optional. Choose services during `inkstead-writer init`, or add them later in `inkstead-writer.json` when you want Inkstead Writer to publish posts to social platforms as part of `./inkstead-writer publish`.

Add `syndicate` to a post:

```yaml
syndicate:
  - provider-name
```

Titled posts syndicate as title plus canonical URL. Untitled notes syndicate as native social posts. Untitled photo notes syndicate as native social posts with attached photos when the selected provider supports media uploads.

For photo notes, Inkstead Writer prepares temporary optimized copies when a service has image size or dimension limits. Your original files stay unchanged.

After a service publishes successfully, Inkstead Writer writes the result back to the post under `syndication`. Future publishes skip anything already marked as published, so the command is safe to run again.

Example result:

```yaml
syndication:
  provider-name:
    status: published
    url: https://social.example/you/123
```

`./inkstead-writer publish` deploys the website before syndication runs so canonical links are already live.
