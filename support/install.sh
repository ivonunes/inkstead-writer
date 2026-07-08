#!/bin/sh
set -eu

REPOSITORY="${INKSTEAD_WRITER_REPOSITORY:-ivonunes/inkstead-writer}"
INSTALL_DIR="${INKSTEAD_WRITER_INSTALL_DIR:-/usr/local/bin}"
VERSION="${INKSTEAD_WRITER_VERSION:-latest}"
BIN_NAME="inkstead-writer"

usage() {
  cat <<'EOF'
Inkstead Writer installer

Usage:
  curl -fsSL https://install.inkstead.app | sh
  curl -fsSL https://install.inkstead.app | sh -s -- --dir "$HOME/.local/bin"

Options:
  --dir DIR          Install directory. Defaults to /usr/local/bin.
  --version VERSION  Install launcher from a specific Inkstead Writer release.
  --repository REPO  GitHub repository. Defaults to ivonunes/inkstead-writer.
  --help             Show this help.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dir)
      shift
      if [ "$#" -eq 0 ]; then
        echo "--dir requires a value." >&2
        exit 1
      fi
      INSTALL_DIR="$1"
      ;;
    --version)
      shift
      if [ "$#" -eq 0 ]; then
        echo "--version requires a value." >&2
        exit 1
      fi
      VERSION="${1#v}"
      ;;
    --repository)
      shift
      if [ "$#" -eq 0 ]; then
        echo "--repository requires a value." >&2
        exit 1
      fi
      REPOSITORY="$1"
      ;;
    --help|-h|help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

fetch_to_file() {
  URL="$1"
  OUTPUT="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$URL" -o "$OUTPUT"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$OUTPUT" "$URL"
  else
    echo "curl or wget is required to install Inkstead Writer." >&2
    exit 1
  fi
}

fetch_stdout() {
  URL="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$URL"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO - "$URL"
  else
    echo "curl or wget is required to install Inkstead Writer." >&2
    exit 1
  fi
}

latest_version() {
  JSON="$(fetch_stdout "https://api.github.com/repos/$REPOSITORY/releases/latest")"
  TAG="$(printf '%s\n' "$JSON" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
  TAG="${TAG#v}"
  if [ -z "$TAG" ]; then
    echo "Could not determine latest Inkstead Writer release." >&2
    exit 1
  fi
  printf '%s\n' "$TAG"
}

checksum_for_asset() {
  VERSION="$1"
  ASSET="$2"
  SUMS_URL="https://github.com/$REPOSITORY/releases/download/v$VERSION/inkstead-writer-v$VERSION-SHA256SUMS"
  CHECKSUM="$(fetch_stdout "$SUMS_URL" | awk -v asset="$ASSET" '$2 == asset { print $1; exit }')"
  if [ -z "$CHECKSUM" ]; then
    echo "Could not find checksum for $ASSET in Inkstead Writer $VERSION." >&2
    exit 1
  fi
  printf '%s\n' "$CHECKSUM"
}

verify_checksum() {
  FILE="$1"
  EXPECTED="$2"
  if command -v shasum >/dev/null 2>&1; then
    ACTUAL="$(shasum -a 256 "$FILE" | awk '{ print $1 }')"
  elif command -v sha256sum >/dev/null 2>&1; then
    ACTUAL="$(sha256sum "$FILE" | awk '{ print $1 }')"
  else
    echo "shasum or sha256sum is required to verify Inkstead Writer downloads." >&2
    exit 1
  fi

  if [ "$ACTUAL" != "$EXPECTED" ]; then
    echo "Checksum verification failed for $FILE." >&2
    echo "Expected $EXPECTED but got $ACTUAL." >&2
    exit 1
  fi
}

install_file() {
  SOURCE="$1"
  TARGET="$2"
  TARGET_DIR="$(dirname -- "$TARGET")"

  if mkdir -p "$TARGET_DIR" 2>/dev/null && [ -w "$TARGET_DIR" ]; then
    if command -v install >/dev/null 2>&1; then
      install -m 755 "$SOURCE" "$TARGET"
    else
      cp "$SOURCE" "$TARGET"
      chmod 755 "$TARGET"
    fi
    return 0
  fi

  if command -v sudo >/dev/null 2>&1; then
    sudo mkdir -p "$TARGET_DIR"
    if command -v install >/dev/null 2>&1; then
      sudo install -m 755 "$SOURCE" "$TARGET"
    else
      sudo cp "$SOURCE" "$TARGET"
      sudo chmod 755 "$TARGET"
    fi
    return 0
  fi

  echo "Cannot write to $TARGET_DIR." >&2
  echo "Run again with --dir pointing at a writable directory, or install with sudo." >&2
  exit 1
}

if [ "$VERSION" = "latest" ]; then
  VERSION="$(latest_version)"
fi

TMPDIR_ROOT="${TMPDIR:-/tmp}"
TMPDIR_PATH="$(mktemp -d "$TMPDIR_ROOT/inkstead-writer-install.XXXXXX")"
cleanup() {
  rm -rf "$TMPDIR_PATH"
}
trap cleanup 0 1 2 15

ASSET="$BIN_NAME-v$VERSION"
LAUNCHER="$TMPDIR_PATH/$BIN_NAME"
ASSET_URL="https://github.com/$REPOSITORY/releases/download/v$VERSION/$ASSET"

echo "Downloading Inkstead Writer launcher $VERSION..." >&2
fetch_to_file "$ASSET_URL" "$LAUNCHER"
verify_checksum "$LAUNCHER" "$(checksum_for_asset "$VERSION" "$ASSET")"
chmod +x "$LAUNCHER"

install_file "$LAUNCHER" "$INSTALL_DIR/$BIN_NAME"

cat <<EOF
Installed Inkstead Writer launcher $VERSION to $INSTALL_DIR/$BIN_NAME.

Create a site:
  inkstead-writer init my-site
EOF
