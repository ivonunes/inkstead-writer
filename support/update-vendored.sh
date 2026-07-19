#!/usr/bin/env bash
#
# update-vendored.sh
#
# Checks the upstreams of the vendored ThirdParty/ codecs and applies any newer
# release in place, printing one "name: old -> new" line per update. Prints
# nothing when everything is current. The weekly update-vendored.yml workflow
# runs this and turns the resulting diff into a PR; running it locally works
# the same way (inspect the result with git diff).
#
# Each import replaces the upstream files wholesale, then restores the local
# overlay (generated configuration headers, the libjpeg-turbo bit-depth
# wrappers) and reapplies the in-tree edits recorded in ThirdParty/patches/.
# The version/checksum table in ThirdParty/README.md is the record of what is
# vendored and is updated with each import.
set -euo pipefail
cd "$(dirname "$0")/.."

README=ThirdParty/README.md

# newer CURRENT CANDIDATE — true when CANDIDATE is a newer version
newer() {
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" = "$2" ]
}

# latest_tag REPO-URL FILTER-REGEX — highest matching tag
latest_tag() {
  git ls-remote --tags "$1" | sed 's|.*refs/tags/||' | grep -E "$2" | sort -V | tail -n1
}

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# current_version NAME — the version cell of NAME's row in the README table
current_version() {
  awk -v name="$1" 'index($0, "| `" name "` |") == 1 { split($0, c, "`"); print c[6]; exit }' "$README"
}

# update_row NAME URL VERSION HASH — rewrite NAME's row, keeping the licence cell
update_row() {
  awk -v name="$1" -v url="$2" -v ver="$3" -v hash="$4" '
    index($0, "| `" name "` |") == 1 {
      n = split($0, c, "|")
      printf "| `%s` | `%s` | `%s` / `%s` |%s|\n", name, url, ver, hash, c[n-1]
      next
    }
    { print }
  ' "$README" > "$README.tmp" && mv "$README.tmp" "$README"
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- libjpeg-turbo -----------------------------------------------------------
# Imported from the official release tarball (not the git archive; the recorded
# checksum is the tarball's). Micro versions >= 90 are upstream's betas.
URL=https://github.com/libjpeg-turbo/libjpeg-turbo
CURRENT="$(current_version libjpeg-turbo)"
LATEST="$(git ls-remote --tags "$URL" | sed 's|.*refs/tags/||' \
  | grep -E '^[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$' | awk -F. '$3 < 90' | sort -V | tail -n1)"
if newer "$CURRENT" "$LATEST"; then
  curl -fsSL "$URL/releases/download/$LATEST/libjpeg-turbo-$LATEST.tar.gz" -o "$TMP/jpeg.tar.gz"
  tar -xzf "$TMP/jpeg.tar.gz" -C "$TMP"
  DST=ThirdParty/libjpeg-turbo/libjpeg-turbo
  mkdir -p "$TMP/overlay"
  cp "$DST/src/jconfig.h" "$DST/src/jconfigint.h" "$TMP/overlay/"
  rm -rf "$DST/src"
  cp -R "$TMP/libjpeg-turbo-$LATEST/src" "$DST/src"
  cp "$TMP/overlay/jconfig.h" "$TMP/overlay/jconfigint.h" "$DST/src/"
  # jversion.h changes shape between releases, so regenerate it from the new
  # template rather than preserving the old generated copy
  sed "s/@COPYRIGHT_YEAR@/1991-$(date +%Y)/g" "$DST/src/jversion.h.in" > "$DST/src/jversion.h"
  cp "$DST/src/turbojpeg.h" "$DST/include/turbojpeg.h"
  git apply ThirdParty/patches/libjpeg-turbo-disable-png.patch
  sed -i.bak "s/let version = \"$CURRENT\"/let version = \"$LATEST\"/" \
    ThirdParty/libjpeg-turbo/Sources/JPEGTurbo/JPEGTurbo.swift
  rm ThirdParty/libjpeg-turbo/Sources/JPEGTurbo/JPEGTurbo.swift.bak
  # the generated headers bake the release version in
  NUMBER="$(printf '%s' "$LATEST" | awk -F. '{ printf "%d%03d%03d", $1, $2, $3 }')"
  sed -i.bak \
    -e "s/$CURRENT/$LATEST/g" \
    -e "s/LIBJPEG_TURBO_VERSION_NUMBER  [0-9]*/LIBJPEG_TURBO_VERSION_NUMBER  $NUMBER/" \
    "$DST/src/jconfig.h" "$DST/src/jconfigint.h"
  rm "$DST/src/jconfig.h.bak" "$DST/src/jconfigint.h.bak"
  update_row libjpeg-turbo "$URL" "$LATEST" "$(sha256 "$TMP/jpeg.tar.gz")"
  echo "libjpeg-turbo: $CURRENT -> $LATEST"
fi

# --- libspng -----------------------------------------------------------------
URL=https://github.com/randy408/libspng
CURRENT="$(current_version libspng)"
LATEST="$(latest_tag "$URL" '^v[0-9]+\.[0-9]+\.[0-9]+$' | sed 's/^v//')"
if newer "$CURRENT" "$LATEST"; then
  curl -fsSL "$URL/archive/refs/tags/v$LATEST.tar.gz" -o "$TMP/spng.tar.gz"
  tar -xzf "$TMP/spng.tar.gz" -C "$TMP"
  DST=ThirdParty/libspng/libspng
  cp "$TMP/libspng-$LATEST/spng/spng.c" "$TMP/libspng-$LATEST/spng/spng.h" "$DST/spng/"
  cp "$TMP/libspng-$LATEST/spng/spng.h" "$DST/include/spng.h"
  git apply ThirdParty/patches/libspng-miniz-pragma.patch
  update_row libspng "$URL" "$LATEST" "$(sha256 "$TMP/spng.tar.gz")"
  echo "libspng: $CURRENT -> $LATEST"
fi

# --- miniz -------------------------------------------------------------------
# libspng's DEFLATE backend. miniz_export.h is generated locally and kept.
URL=https://github.com/richgel999/miniz
CURRENT="$(current_version miniz)"
LATEST="$(latest_tag "$URL" '^[0-9]+\.[0-9]+\.[0-9]+$')"
if newer "$CURRENT" "$LATEST"; then
  curl -fsSL "$URL/archive/refs/tags/$LATEST.tar.gz" -o "$TMP/miniz.tar.gz"
  tar -xzf "$TMP/miniz.tar.gz" -C "$TMP"
  DST=ThirdParty/libspng/libspng/miniz
  for f in "$DST"/*.c "$DST"/*.h; do
    NAME="$(basename "$f")"
    [ "$NAME" = miniz_export.h ] && continue
    cp "$TMP/miniz-$LATEST/$NAME" "$f"
  done
  update_row miniz "$URL" "$LATEST" "$(sha256 "$TMP/miniz.tar.gz")"
  echo "miniz: $CURRENT -> $LATEST"
fi

# --- libwebp -----------------------------------------------------------------
# Tracks webmproject/libwebp directly (the original import came through the
# swift-collective packaging fork, which pins the same tree as a submodule).
URL=https://github.com/webmproject/libwebp
CURRENT="$(current_version libwebp)"
LATEST="$(latest_tag "$URL" '^v[0-9]+\.[0-9]+\.[0-9]+$' | sed 's/^v//')"
if newer "$CURRENT" "$LATEST"; then
  curl -fsSL "$URL/archive/refs/tags/v$LATEST.tar.gz" -o "$TMP/webp.tar.gz"
  tar -xzf "$TMP/webp.tar.gz" -C "$TMP"
  DST=ThirdParty/libwebp/libwebp
  # src/module.modulemap is local (from the packaging fork): it limits the
  # module to the public webp/ headers, whose internal includes would not
  # resolve under SwiftPM's generated whole-directory umbrella
  cp "$DST/src/module.modulemap" "$TMP/module.modulemap"
  rm -rf "$DST/src" "$DST/sharpyuv"
  cp -R "$TMP/libwebp-$LATEST/src" "$DST/src"
  cp -R "$TMP/libwebp-$LATEST/sharpyuv" "$DST/sharpyuv"
  cp "$TMP/module.modulemap" "$DST/src/module.modulemap"
  git apply ThirdParty/patches/libwebp-sharpyuv-pragma.patch
  update_row libwebp "$URL" "$LATEST" "$(sha256 "$TMP/webp.tar.gz")"
  echo "libwebp: $CURRENT -> $LATEST"
fi
