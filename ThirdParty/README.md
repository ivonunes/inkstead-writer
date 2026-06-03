# Vendored Image Dependencies

Inkstead vendors its image codec stack so release builds are not broken by
upstream package or toolchain drift. These packages are local forks of the
upstream projects.

| Path | Upstream | Version / revision | License |
| --- | --- | --- | --- |
| `swift-jpeg` | `https://github.com/tayloraswift/swift-jpeg` | `2.1.0` / `c7aa48486cd8920120dd69cda5de62aeb93e1708` | Apache 2.0 |
| `swift-png` | `https://github.com/tayloraswift/swift-png` | `4.5.1` / `8a0bcd4df5e4b307c804937776a56dd6ecdf6396` | Apache 2.0 |
| `libwebp` | `https://github.com/the-swift-collective/libwebp.git` | `1.4.1` / `5f745a17b9a5c2a4283f17c2cde4517610ab5f99` | BSD-3-Clause |
| `h` | `https://github.com/rarestype/h` | `1.0.1` / `aa3626829160917d4378330617971977cbd78f5b` | Apache 2.0 |

Local changes:

- Package manifests are pruned to library targets used by Inkstead.
- `swift-jpeg` has Swift 6.3 compatibility patches for concurrency diagnostics
  that affect error enums containing key-path selector values.
- `h` has an availability-version spelling fix for watchOS.
- `libwebp` has a narrow Clang diagnostic suppression for an upstream
  `sharpyuv` macro redefinition warning.
