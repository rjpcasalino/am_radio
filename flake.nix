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
          '';
        };
      }
    );
}
