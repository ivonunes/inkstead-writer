# Vendored Image Dependencies

Inkstead vendors its image codec stack so release builds are not broken by
upstream package or toolchain drift. These packages are local forks of the
upstream projects.

| Path | Upstream | Version / revision | License |
| --- | --- | --- | --- |
| `libjpeg-turbo` | `https://github.com/libjpeg-turbo/libjpeg-turbo` | `3.2.0` / `6f30092cef9fb839779646608f4ee14ae3cbac989c47fa05e841b0841f09878e` | BSD-style |
| `libspng` | `https://github.com/randy408/libspng` | `0.7.4` / `47ec02be6c0a6323044600a9221b049f63e1953faf816903e7383d4dc4234487` | BSD-2-Clause |
| `miniz` | `https://github.com/richgel999/miniz` | `3.1.2` / `98468f8924934b723276680f85238b6c78bf1f8b49b4459cc9b7214a20e2e9fb` | MIT-style |
| `libwebp` | `https://github.com/webmproject/libwebp` | `1.6.0` / `93a852c2b3efafee3723efd4636de855b46f9fe1efddd607e1f42f60fc8f2136` | BSD-3-Clause |

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
