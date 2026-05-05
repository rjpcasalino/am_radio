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
            # Two things break xcodebuild inside a Nix shell on macOS:
            #
            # 1. DEVELOPER_DIR is unset — /usr/bin/xcodebuild is an xcrun shim
            #    that needs DEVELOPER_DIR to locate the real toolchain inside
            #    Xcode.app.
            #
            # 2. Nix's clang wrapper (included via buildInputs) sets SDKROOT to
            #    a Nix-store SDK path.  xcrun then searches for tools under that
            #    path rather than under Xcode.app, so it reports
            #    "tool 'xcodebuild' not found" even after DEVELOPER_DIR is set.
            #    Unsetting SDKROOT lets xcrun fall back to the Xcode SDK.
            if [[ "$(uname)" == "Darwin" ]]; then
              export DEVELOPER_DIR="$(xcode-select -p 2>/dev/null \
                || echo '/Applications/Xcode.app/Contents/Developer')"
              export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
              unset SDKROOT
              echo "Xcode developer dir: $DEVELOPER_DIR"
            fi

            # ── macOS: fix ios directory permissions ────────────────────────
            # flutter create --platforms ios creates some workspace files with
            # mode 444 (read-only).  CocoaPods needs to rewrite those files
            # during pod install, so ensure everything under ios/ is user-writable.
            if [[ "$(uname)" == "Darwin" && -d "$PWD/mobile/ios" ]]; then
              chmod -R u+w "$PWD/mobile/ios" 2>/dev/null || true
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
