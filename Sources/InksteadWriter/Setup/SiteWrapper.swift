import Foundation

public enum SiteWrapper {
    public static let path = InksteadWriterMetadata.executableName

    public static var script: String {
        """
        #!/bin/sh
        set -eu

        SCRIPT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
        REPOSITORY="ivonunes/inkstead-writer"

        detect_platform() {
          SYSTEM="$(uname -s)"
          MACHINE="$(uname -m)"

          case "$SYSTEM" in
            Darwin) OS="macos" ;;
            Linux) OS="linux" ;;
            *)
              echo "Unsupported system: $SYSTEM" >&2
              exit 1
              ;;
          esac

          case "$MACHINE" in
            x86_64|amd64) ARCH="x86_64" ;;
            arm64) ARCH="arm64" ;;
            aarch64)
              if [ "$OS" = "linux" ]; then
                ARCH="aarch64"
              else
                ARCH="arm64"
              fi
              ;;
            *)
              echo "Unsupported architecture: $MACHINE" >&2
              exit 1
              ;;
          esac
        }

        find_site_root() {
          if [ -f "$SCRIPT_ROOT/inkstead-writer.json" ] || [ -f "$SCRIPT_ROOT/inkstead.json" ] || [ -f "$SCRIPT_ROOT/site.config.ts" ]; then
            printf '%s\\n' "$SCRIPT_ROOT"
            return 0
          fi

          DIR="$(pwd -P)"
          while [ "$DIR" != "/" ]; do
            if [ -f "$DIR/inkstead-writer.json" ] || [ -f "$DIR/inkstead.json" ] || [ -f "$DIR/site.config.ts" ]; then
              printf '%s\\n' "$DIR"
              return 0
            fi
            DIR="$(dirname -- "$DIR")"
          done
          return 1
        }

        fetch_to_file() {
          URL="$1"
          OUTPUT="$2"
          if command -v curl >/dev/null 2>&1; then
            curl -fsSL "$URL" -o "$OUTPUT"
          elif command -v wget >/dev/null 2>&1; then
            wget -qO "$OUTPUT" "$URL"
          else
            echo "curl or wget is required to download Inkstead Writer." >&2
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
            echo "curl or wget is required to download Inkstead Writer." >&2
            exit 1
          fi
        }

        cache_root() {
          if [ -n "${INKSTEAD_WRITER_CACHE_DIR:-}" ]; then
            printf '%s\\n' "$INKSTEAD_WRITER_CACHE_DIR"
          elif [ -n "${INKSTEAD_CACHE_DIR:-}" ]; then
            printf '%s\\n' "$INKSTEAD_CACHE_DIR"
          elif [ "$OS" = "macos" ]; then
            printf '%s\\n' "$HOME/Library/Caches/inkstead-writer"
          else
            printf '%s\\n' "${XDG_CACHE_HOME:-$HOME/.cache}/inkstead-writer"
          fi
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
          printf '%s\\n' "$CHECKSUM"
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

        acquire_lock() {
          LOCK="$1"
          ATTEMPTS=0
          while ! mkdir "$LOCK" 2>/dev/null; do
            ATTEMPTS=$((ATTEMPTS + 1))
            if [ "$ATTEMPTS" -ge 120 ]; then
              echo "Timed out waiting for another Inkstead Writer download to finish." >&2
              exit 1
            fi
            sleep 1
          done
        }

        release_lock() {
          LOCK="$1"
          rmdir "$LOCK" 2>/dev/null || true
        }

        latest_version() {
          JSON="$(fetch_stdout "https://api.github.com/repos/$REPOSITORY/releases/latest")"
          TAG="$(printf '%s\\n' "$JSON" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\\([^"]*\\)".*/\\1/p' | head -n 1)"
          TAG="${TAG#v}"
          if [ -z "$TAG" ]; then
            echo "Could not determine latest Inkstead Writer release." >&2
            exit 1
          fi
          printf '%s\\n' "$TAG"
        }

        site_version() {
          ROOT="$1"
          COMMAND="$2"
          VERSION=""

          if [ -f "$ROOT/inkstead-writer.json" ]; then
            VERSION="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\\([^"]*\\)".*/\\1/p' "$ROOT/inkstead-writer.json" | head -n 1)"
          elif [ -f "$ROOT/inkstead.json" ]; then
            VERSION="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\\([^"]*\\)".*/\\1/p' "$ROOT/inkstead.json" | head -n 1)"
          fi

          if [ -n "$VERSION" ]; then
            printf '%s\\n' "$VERSION"
            return 0
          fi

          case "$COMMAND" in
            migrate|update|cache)
              latest_version
              return 0
              ;;
          esac

          cat >&2 <<'EOF'
        This Inkstead Writer site does not record an Inkstead Writer version yet.

        Run one of these first:
          inkstead-writer update
          inkstead-writer migrate
        EOF
          exit 1
        }

        download_binary() {
          VERSION="$1"
          CACHE_ROOT="$2"
          VERSION_CACHE="$CACHE_ROOT/v$VERSION"
          CACHE="$VERSION_CACHE/$OS-$ARCH"
          BIN="$CACHE/inkstead-writer"

          if [ ! -x "$BIN" ]; then
            mkdir -p "$VERSION_CACHE"
            LOCK="$VERSION_CACHE/$OS-$ARCH.lock"
            acquire_lock "$LOCK"
            trap 'release_lock "$LOCK"' 0 1 2 15

            if [ ! -x "$BIN" ]; then
              mkdir -p "$CACHE"
              ASSET="inkstead-writer-v$VERSION-$OS-$ARCH.tar.gz"
              URL="https://github.com/$REPOSITORY/releases/download/v$VERSION/$ASSET"
              TMP="$CACHE/$ASSET.$$"

              echo "Downloading Inkstead Writer $VERSION for $OS/$ARCH..." >&2
              fetch_to_file "$URL" "$TMP"
              CHECKSUM="$(checksum_for_asset "$VERSION" "$ASSET")"
              verify_checksum "$TMP" "$CHECKSUM"
              tar -xzf "$TMP" -C "$CACHE"
              rm -f "$TMP"
              chmod +x "$BIN"
            fi

            release_lock "$LOCK"
            trap - 0 1 2 15
          fi

          printf '%s\\n' "$BIN"
        }

        detect_platform

        case "${1:-}" in
          --help|-h|help)
            cat <<'EOF'
        Inkstead Writer launcher

        Usage:
          inkstead-writer init my-site
          ./inkstead-writer <command>

        Commands:
          build        Build the current site
          cache        List or clean downloaded Inkstead Writer binaries
          deploy       Deploy an already-built site
          dev          Build and serve the site locally
          doctor       Check site setup
          init         Create a new site
          migrate      Apply site migrations
          new          Create a new article or note
          publish      Build, deploy, syndicate, and redeploy if needed
          requirements Print required environment variables
          syndicate    Publish posts to configured syndication providers
          theme        Check, format, eject, or serve theme tooling
          update       Download the latest Inkstead Writer and migrate the site
          version      Print the Inkstead Writer site format version
        EOF
            exit 0
            ;;
        esac

        if [ "${1:-}" = "init" ]; then
          VERSION="$(latest_version)"
          BIN="$(download_binary "$VERSION" "$(cache_root)")"
          exec "$BIN" "$@"
        fi

        if ROOT="$(find_site_root)"; then
          VERSION="$(site_version "$ROOT" "${1:-}")"
          BIN="$(download_binary "$VERSION" "$(cache_root)")"
          cd "$ROOT"
          exec "$BIN" "$@"
        fi

        if [ "${1:-}" = "cache" ]; then
          VERSION="$(latest_version)"
          BIN="$(download_binary "$VERSION" "$(cache_root)")"
          exec "$BIN" "$@"
        fi

        cat >&2 <<'EOF'
        This Inkstead Writer launcher is not inside an Inkstead Writer site.

        To create a site:
          inkstead-writer init my-site

        Inside an existing site:
          inkstead-writer build
          ./inkstead-writer build
        EOF
        exit 1
        """
    }
}
