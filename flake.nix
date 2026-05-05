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
      in
      {
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

            # Linux desktop runner dependencies
            cmake
            ninja
            clang
            pkg-config
            gtk3
            glib
            pcre2

            # Audio/Tools
            mpv
            curl
            git
            jq
          ];

          # 3. Export variables so Flutter/Gradle knows where things are
          env = {
            ANDROID_HOME = "${androidSdk}/libexec/android-sdk";
            ANDROID_SDK_ROOT = "${androidSdk}/libexec/android-sdk";
            ANDROID_NDK_HOME = "${androidSdk}/libexec/android-sdk/ndk/28.2.13676358";
            JAVA_HOME = pkgs.jdk17.home;
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
              unset SDKROOT
            fi

            # Bootstrap Flutter platforms
            if [ ! -d "$PWD/mobile/linux/runner" ]; then
              echo "Bootstrapping Flutter platform directories..."
              (cd mobile && flutter create . --platforms linux,android --project-name am_radio) || true
            fi
            
            echo "Android SDK Location: $ANDROID_HOME"
            echo "Run 'flutter doctor' to verify setup."
          '';
        };
      }
    );
}
