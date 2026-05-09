{
  description = "am_radio — internet radio player + mobile app dev environment";

  inputs = {
    nixpkgs.url     = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        # 1. We must import nixpkgs to pass the configuration
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            android_sdk.accept_license = true;
          };
        };

        # 2. Compose the Android SDK with required Flutter/Gradle components
        # This replaces the generic androidPkgs.androidsdk with a customized bundle
        androidComposition = pkgs.androidenv.composeAndroidPackages {
          includeNDK = true;
          ndkVersions = [ "28.2.13676358" ];
          # Add 35.0.0 here:
          buildToolsVersions = [ "33.0.1" "34.0.0" "35.0.0" ];
          # Add 36 here (and 35 just to be safe):
          platformVersions = [ "33" "34" "35" "36" ];
          abiVersions = [ "armeabi-v7a" "arm64-v8a" "x86_64" ];
          cmakeVersions = ["3.22.1"];
        };
        
        androidSdk = androidComposition.androidsdk;

        # Create a deployment script for Android
        deployAndroid = pkgs.writeShellScriptBin "deploy-android" ''
          export PATH="${pkgs.lib.makeBinPath [ pkgs.flutter androidSdk pkgs.coreutils pkgs.gnugrep pkgs.gawk pkgs.gnused ]}:$PATH"
          export ANDROID_HOME="${androidSdk}/libexec/android-sdk"
          export ANDROID_SDK_ROOT="${androidSdk}/libexec/android-sdk"
          exec ${pkgs.bash}/bin/bash ${./deploy-android.sh} "$@"
        '';
      in
      {
        # Nix app for deploying to Android
        apps.deploy-android = {
          type = "app";
          program = "${deployAndroid}/bin/deploy-android";
        };

        devShells.default = pkgs.mkShell {
          name = "am-radio-cli";
          buildInputs = with pkgs; [
            perl
            mpv
            curl
            ffmpeg
          ];
        };

        devShells.mobile = pkgs.mkShell {
          name = "am-radio-mobile";
          
          # Use 'packages' instead of 'buildInputs'
          packages = with pkgs; [
            flutter
            androidSdk
            jdk17 # Flutter currently prefers JDK 17
            cmake

            # Audio/Tools
            mpv
            curl
            git
            jq
          # Linux desktop runner dependencies — these packages' Nix setup hooks
          # inject NIX_LDFLAGS / NIX_CC / NIX_BINTOOLS which Xcode's Apple linker
          # rejects.  Only include them on Linux where they are actually needed.
          ] ++ lib.optionals pkgs.stdenv.isLinux [
            ninja
            clang
            pkg-config
            gtk3
            glib
            pcre2
          ];

          # 3. Export variables so Flutter/Gradle knows where things are
          env = {
            ANDROID_HOME = "${androidSdk}/libexec/android-sdk";
            ANDROID_SDK_ROOT = "${androidSdk}/libexec/android-sdk";
            ANDROID_NDK_HOME = "${androidSdk}/libexec/android-sdk/ndk/28.2.13676358";
            JAVA_HOME = pkgs.jdk17.home;
          # google-chrome is only available via nixpkgs on Linux; on macOS use
          # the system-installed Chrome.
          } // lib.optionalAttrs pkgs.stdenv.isLinux {
            CHROME_EXECUTABLE = "${pkgs.google-chrome}/bin/google-chrome";
          };

          shellHook = ''
            echo "╔══════════════════════════════════════════╗"
            echo "║   am_radio — mobile dev shell (Flutter)  ║"
            echo "╚══════════════════════════════════════════╝"

            # macOS toolchain fixes
            if [[ "$(uname)" == "Darwin" ]]; then
              export DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || echo '/Applications/Xcode.app/Contents/Developer')"
              export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
              # Belt-and-suspenders: clear any residual Nix toolchain variables
              # that would confuse Xcode / Apple ld.
              unset SDKROOT NIX_LDFLAGS NIX_CFLAGS_COMPILE \
                    NIX_CC NIX_BINTOOLS \
                    NIX_CC_WRAPPER_TARGET_HOST \
                    NIX_BINTOOLS_WRAPPER_TARGET_HOST \
                    NIX_ENFORCE_NO_NATIVE NIX_HARDENING_ENABLE \
                    ZERO_AR_DATE 2>/dev/null || true
            fi

            # Bootstrap Flutter platforms
            if [ ! -d "$PWD/mobile/linux/runner" ]; then
              echo "Bootstrapping Flutter platform directories..."
              (cd mobile && flutter create . --platforms linux,android --project-name am_radio) || true
            fi

            # ── Android: allow cleartext HTTP for radio streams ─────────────
            # Android 9+ blocks plain HTTP by default (CleartextNotPermittedException).
            # network_security_config.xml is committed and won't be touched by
            # flutter create, but AndroidManifest.xml is generated fresh, so patch
            # it if the networkSecurityConfig attribute is not already present.
            MANIFEST="$PWD/mobile/android/app/src/main/AndroidManifest.xml"
            NSC_XML="$PWD/mobile/android/app/src/main/res/xml/network_security_config.xml"
            if [ -f "$MANIFEST" ] && ! grep -q 'networkSecurityConfig=' "$MANIFEST"; then
              sed -i 's|<application|<application android:networkSecurityConfig="@xml/network_security_config"|' "$MANIFEST"
              echo "Patched AndroidManifest.xml to allow cleartext HTTP."
            fi
            # Ensure the xml resource file is present (committed version is the
            # source of truth; this is a safety net for edge cases).
            if [ ! -f "$NSC_XML" ]; then
              mkdir -p "$(dirname "$NSC_XML")"
              cat > "$NSC_XML" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <base-config cleartextTrafficPermitted="true" />
</network-security-config>
EOF
            fi

            echo "Android SDK Location: $ANDROID_HOME"
            echo "Run 'flutter doctor' to verify setup."
          '';
        };
      }
    );
}
