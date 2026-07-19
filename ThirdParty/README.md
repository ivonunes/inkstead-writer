# Vendored Image Dependencies

Inkstead vendors its image codec stack so release builds are not broken by
upstream package or toolchain drift. These packages are local forks of the
upstream projects.

| Path | Upstream | Version / revision | License |
| --- | --- | --- | --- |
| `libjpeg-turbo` | `https://github.com/libjpeg-turbo/libjpeg-turbo` | `3.1.4.1` / `ecae8008e2cc9ade2f2c1bb9d5e6d4fb73e7c433866a056bd82980741571a022` | BSD-style |
| `libspng` | `https://github.com/randy408/libspng` | `0.7.4` / `47ec02be6c0a6323044600a9221b049f63e1953faf816903e7383d4dc4234487` | BSD-2-Clause |
| `miniz` | `https://github.com/richgel999/miniz` | `2.2.0` / `bd1136d0a1554520dcb527a239655777148d90fd2d51cf02c36540afc552e6ec` | MIT-style |
| `libwebp` | `https://github.com/the-swift-collective/libwebp.git` | `1.4.1` / `5f745a17b9a5c2a4283f17c2cde4517610ab5f99` | BSD-3-Clause |

Local changes:

- Package manifests are pruned to library targets used by Inkstead.
- `libjpeg-turbo` is built as a local SwiftPM C target with generated
  non-SIMD configuration headers from the official source tarball.
  `include/tjcompat.h` is a local shim so the Swift wrapper works across the
  libjpeg-turbo 3.2 `tj3Init` macro change, and the PNG loader/saver added in
  3.2 is disabled (it would pull a second copy of spng into the binary).
- `libspng` is built as a local SwiftPM C target with `miniz` as its
  single-binary DEFLATE backend.
- `libspng` suppresses the upstream `inflateValidate()` pragma for `miniz`
  builds because Inkstead does not use `SPNG_CTX_IGNORE_ADLER32`.
- `libwebp` has a narrow Clang diagnostic suppression for an upstream
  `sharpyuv` macro redefinition warning. Its `src/module.modulemap` is local
  (from the packaging fork); updates track `webmproject/libwebp` directly.

In-tree edits to upstream sources are recorded as patch files in
`ThirdParty/patches/` and reapplied by `support/update-vendored.sh`, which
checks all four upstreams and imports newer releases (the weekly
update-vendored workflow runs it and raises the result as a PR).
