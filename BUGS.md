## What's up, Doc?

`--resize` does not work under Sway/Hyprland in Wayland

* Aug 14 06:51:50 zits /nix/store/8hkhq8rxw0jkb3n63lm4x87h153rdmrg-gdm-50.2/libexec/gdm-wayland-session[719332]: warn: csi.c:1273: unimplemented: resize window in chars

**Status:** Fixed. The xterm `\e[8;rows;cols;t` escape is not implemented by Wayland compositors. When `--resize` is used and the escape has no effect, `am_radio` now falls back to compositor-specific sizing: `swaymsg resize set` for Sway (if `SWAYSOCK` is set), and `hyprctl dispatch resizeactive exact ...` for Hyprland (if `HYPRLAND_INSTANCE_SIGNATURE` is set). In tiled Hyprland layouts, the active terminal window is temporarily floated so the resize can take effect. Window size is restored on exit. If neither method works, a warning is printed and the TUI launches anyway if the terminal is already large enough.
