{
  description = "am_radio — internet radio player + mobile app dev environment";

  inputs = {
    nixpkgs.url     = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        # ── CLI dev shell (Perl + mpv) ─────────────────────────────────────
        devShells.default = pkgs.mkShell {
          name = "am-radio-cli";
          buildInputs = with pkgs; [
            perl
            mpv
            curl
            ffmpeg   # provides ffprobe
          ];
          shellHook = ''
            echo "am_radio CLI dev shell"
            echo "  perl am_radio.pl -h"
          '';
        };

        # ── Mobile dev shell (Flutter for Linux + Android) ─────────────────
        devShells.mobile = pkgs.mkShell {
          name = "am-radio-mobile";
          buildInputs = with pkgs; [
            # Flutter SDK (targets Linux desktop + Android)
            flutter

            # Linux desktop runner dependencies
            cmake
            ninja
            clang
            pkg-config
            gtk3
            glib
            pcre2

            # Audio backend used by the Linux app (mpv subprocess)
            mpv

            # Network / tooling
            curl
            git

            # Useful extras
            jq
          ];

          shellHook = ''
            echo ""
            echo "╔══════════════════════════════════════════╗"
            echo "║   am_radio — mobile dev shell (Flutter)  ║"
            echo "╚══════════════════════════════════════════╝"

            # ── macOS: restore Xcode toolchain ─────────────────────────────
            # Nix resets the environment, which breaks the /usr/bin/xcodebuild
            # shim that macOS ships.  That shim needs DEVELOPER_DIR to locate
            # the real xcodebuild inside Xcode.app.
            if [[ "$(uname)" == "Darwin" ]]; then
              XCODE_DEV="$(xcode-select -p 2>/dev/null || echo '/Applications/Xcode.app/Contents/Developer')"
              export DEVELOPER_DIR="$XCODE_DEV"
              export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
              echo "Xcode developer dir: $DEVELOPER_DIR"
            fi

            # Bootstrap Flutter platform directories on first entry.
            # 'flutter create . --platforms linux,android' is idempotent —
            # it only adds missing files and never overwrites existing ones.
            if [ ! -d "$PWD/mobile/linux/runner" ]; then
              echo ""
              echo "Bootstrapping Flutter platform directories …"
              (cd "$PWD/mobile" && flutter create . \
                --platforms linux,android \
                --project-name am_radio \
                --org com.example \
                --description "Internet radio player" \
                2>&1) || true
              echo "Done."
            fi

            echo ""
            echo "Quick start:"
            echo "  cd mobile"
            echo "  flutter pub get"
            echo "  flutter run -d linux"
            echo ""
            echo "Android (requires ANDROID_HOME):"
            echo "  flutter run -d android"
            echo ""
            echo "iOS (macOS only — iPhone via USB-C):"
            echo "  flutter create . --platforms ios   # first time only"
            echo "  cd ios && pod install && cd .."
            echo "  flutter run"
            echo ""
          '';
        };
      }
    );
}
