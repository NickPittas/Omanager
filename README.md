# Omanager

A native Omarchy bar widget for per-application Hyprland window behavior. Search installed apps, select a live window, and configure normal tiling or floating, centering, maximize/fullscreen, size and position, workspace assignment, and pinning. Pinning, size, and position use floating windows.

## Install

On Omarchy, install and enable with the built-in plugin command:

```sh
omarchy plugin add https://github.com/NickPittas/Omanager.git --enable
```

Omarchy validates the plugin and asks for confirmation before installing code that runs unsandboxed in the shell. Review the repository before approving.

Update or remove it later:

```sh
omarchy plugin update npittas.omanager
omarchy plugin remove npittas.omanager
```

## Requirements and license

Requires Omarchy Shell with plugin support, Hyprland, and Python 3. It has no additional Python package dependencies. Licensed under MIT; see [LICENSE](LICENSE).

## Use

Open Omanager from the bar, select an app, and choose a live window to identify it safely (or enter its window class manually if it is not running). Save writes app settings to `~/.config/omarchy/omanager.json`, generates Hyprland rules in `~/.config/hypr/omanager.lua`, and adds `require("hypr.omanager")` to `~/.config/hypr/hyprland.lua` on first save. Rules apply to newly opened matching windows. Omanager does not modify app launchers or Ghostty startup.

Workspace placement can be silent (keep the current workspace active) or switch to the assigned workspace. Size and position are monitor-local pixels.

## Development checks

```sh
python3 -m unittest discover -s .
omarchy plugin validate .
qmllint -I /usr/share/omarchy/shell Panel.qml
```
