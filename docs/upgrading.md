# Upgrading

Inkstead sites depend on the single `inkstead` package.

Upgrade with:

```bash
npm install inkstead@latest
```

Then run:

```bash
npm run doctor
npm run build
```

If you use custom templates, check your theme against the current [Themes](/themes/) context values after major upgrades.
