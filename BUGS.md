## What's up, Doc?

`--resize` does not work under sway in Wayland

* Aug 14 06:51:50 zits /nix/store/8hkhq8rxw0jkb3n63lm4x87h153rdmrg-gdm-50.2/libexec/gdm-wayland-session[719332]: warn: csi.c:1273: unimplemented: resize window in chars

**Status:** The xterm `\e[8;rows;cols;t` escape sequence is not implemented by Wayland compositors (including Sway). `--resize` will now emit a warning when it has no effect instead of silently failing. Workaround: manually resize your terminal to at least 67x22 before launching with `-t`.
