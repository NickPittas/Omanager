#!/usr/bin/env python3
"""Data and Hyprland-rule backend for the Omanager Quickshell panel."""

from __future__ import annotations

import configparser
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
from dataclasses import asdict, dataclass
from pathlib import Path

CONFIG = Path.home() / ".config/omarchy/omanager.json"
HYPR_CONFIG = Path.home() / ".config/hypr/omanager.lua"


@dataclass(frozen=True)
class Application:
    id: str
    name: str
    icon: str = ""
    wm_class: str = ""
    exec: str = ""

    @property
    def uses_terminal(self) -> bool:
        try:
            executable = Path(shlex.split(self.exec)[0]).name.lower()
        except (ValueError, IndexError):
            return False
        return executable in {"ghostty", "alacritty", "kitty", "foot", "wezterm", "konsole", "xterm"}


def data_dirs() -> list[Path]:
    home = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")).expanduser()
    configured = os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":")
    candidates = [
        home,
        Path.home() / ".local/share/flatpak/exports/share",
        Path("/var/lib/flatpak/exports/share"),
        *(Path(part).expanduser() for part in configured if part),
    ]
    result, seen = [], set()
    for path in candidates:
        key = os.path.abspath(path)
        if key not in seen:
            seen.add(key)
            result.append(path)
    return result


def discover_apps(dirs: list[Path] | None = None) -> list[Application]:
    """Find visible desktop entries, honoring XDG directory precedence."""
    seen: set[str] = set()
    apps = []
    for data_dir in dirs if dirs is not None else data_dirs():
        root = data_dir / "applications"
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("*.desktop")):
            desktop_id = path.relative_to(root).as_posix().replace("/", "-")
            if desktop_id in seen:
                continue
            seen.add(desktop_id)
            parser = configparser.ConfigParser(interpolation=None, strict=False)
            parser.optionxform = str
            try:
                with path.open(encoding="utf-8") as file:
                    parser.read_file(file)
                entry = parser["Desktop Entry"]
            except (OSError, UnicodeError, configparser.Error, KeyError):
                continue
            if entry.get("Type", "Application") != "Application":
                continue
            if entry.get("Hidden", "false").lower() == "true":
                continue
            if entry.get("NoDisplay", "false").lower() == "true":
                continue
            name = entry.get("Name", "").strip()
            if name:
                apps.append(Application(
                    desktop_id,
                    name,
                    entry.get("Icon", "").strip(),
                    entry.get("StartupWMClass", "").strip(),
                    entry.get("Exec", "").strip(),
                ))
    return sorted(apps, key=lambda app: (app.name.casefold(), app.id.casefold()))


def load_settings() -> dict:
    if not CONFIG.exists():
        return {"version": 1, "apps": {}}
    try:
        value = json.loads(CONFIG.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"Can't read Omanager settings: {error}") from error
    if not isinstance(value, dict) or not isinstance(value.get("apps", {}), dict):
        raise ValueError("Invalid Omanager settings file")
    value.setdefault("version", 1)
    value.setdefault("apps", {})
    if any(not isinstance(key, str) or not isinstance(item, dict) for key, item in value["apps"].items()):
        raise ValueError("Invalid application entry in Omanager settings")
    return value


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent, text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as file:
            file.write(content)
            file.flush()
            os.fsync(file.fileno())
        os.replace(temporary, path)
    except Exception:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def class_regex(value: str) -> str:
    if not value.strip() or any(ord(char) < 32 for char in value):
        raise ValueError("Window class/title must be non-empty and contain no control characters")
    metacharacters = set(r"\\.^$|?*+()[]{}")
    return "^" + "".join("\\" + char if char in metacharacters else char for char in value) + "$"


def lua_quote(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    escaped = escaped.replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")
    return f'"{escaped}"'


def _pair(value: object, field: str, minimum: int, maximum: int) -> list[int] | None:
    if value is None or value == []:
        return None
    if not isinstance(value, list) or len(value) != 2 or any(type(part) is not int for part in value):
        raise ValueError(f"{field} must contain two integers")
    if any(part < minimum or part > maximum for part in value):
        raise ValueError(f"{field} values must be between {minimum} and {maximum}")
    return value


def _rule_options(item: dict, mode: str) -> dict:
    options = {}
    for key in ("maximize", "fullscreen", "pin", "workspace_silent"):
        default = key == "workspace_silent"
        value = item.get(key, default)
        if type(value) is not bool:
            raise ValueError(f"{key} must be a boolean")
        options[key] = value
    options["size"] = _pair(item.get("size"), "size", 1, 16384)
    options["move"] = _pair(item.get("move"), "position", 0, 32767)
    workspace = item.get("workspace", "")
    if not isinstance(workspace, str):
        raise ValueError("workspace must be text")
    workspace = workspace.strip()
    if workspace and not re.fullmatch(r"(?:[1-9][0-9]{0,3}|[A-Za-z][A-Za-z0-9_.:-]{0,63})", workspace):
        raise ValueError("workspace must be a positive number or a simple workspace name")
    options["workspace"] = workspace
    if mode == "default" and (options["pin"] or options["size"] or options["move"]):
        raise ValueError("Pinning, size, and position require the floating layout")
    return options


def render_lua(settings: dict) -> str:
    lines = ["-- Generated by Omanager. Configure through the Omarchy panel."]
    for _desktop_id, item in sorted(settings.get("apps", {}).items()):
        class_name = item.get("class", "")
        initial_title = item.get("initial_title", "")
        mode = item.get("mode", "default")
        if not isinstance(class_name, str) or not class_name or mode not in {"default", "floating", "floating-center"}:
            continue
        options = _rule_options(item, mode)
        has_options = any((options["maximize"], options["fullscreen"], options["pin"], options["size"], options["move"], options["workspace"]))
        if mode == "default" and not has_options:
            continue
        match = [f"class = {lua_quote(class_regex(class_name))}"]
        if isinstance(initial_title, str) and initial_title:
            match.append(f"initial_title = {lua_quote(class_regex(initial_title))}")
        floating = mode in {"floating", "floating-center"}
        rules = ["float = true"] if floating else ["tile = true"]
        if mode == "floating-center" and not options["move"]:
            rules.append("center = true")
        if options["pin"]:
            rules.append("pin = true")
        for key in ("size", "move"):
            pair = options[key]
            if pair:
                rules.append(f"{key} = {{ {pair[0]}, {pair[1]} }}")
        if options["maximize"]:
            rules.append("maximize = true")
        if options["fullscreen"]:
            rules.append("fullscreen = true")
        if options["workspace"]:
            workspace = options["workspace"] + (" silent" if options["workspace_silent"] else "")
            rules.append(f"workspace = {lua_quote(workspace)}")
        lines.append(f"o.window({{ {', '.join(match)} }}, {{ {', '.join(rules)} }})")
    return "\n".join(lines) + "\n"


def save_settings(settings: dict) -> None:
    lua = render_lua(settings)
    atomic_write(CONFIG, json.dumps(settings, ensure_ascii=False, indent=2) + "\n")
    atomic_write(HYPR_CONFIG, lua)


def list_apps() -> dict:
    settings = load_settings()["apps"]
    apps = []
    for app in discover_apps():
        row = asdict(app)
        row["uses_terminal"] = app.uses_terminal
        row["setting"] = settings.get(app.id, {})
        apps.append(row)
    return {"ok": True, "apps": apps}


def list_windows() -> dict:
    result = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True, check=True)
    clients = json.loads(result.stdout)
    windows = [{
        "address": str(client.get("address", "")),
        "class": str(client.get("class", "")).strip(),
        "title": str(client.get("title", "")).strip(),
        "initial_title": str(client.get("initialTitle", "")).strip(),
        "floating": bool(client.get("floating", False)),
        "workspace": str((client.get("workspace") or {}).get("name", "")),
    } for client in clients if client.get("address") and client.get("class")]
    windows.sort(key=lambda window: (window["title"].casefold(), window["class"].casefold()))
    return {"ok": True, "windows": windows}


def save_app(payload: dict) -> dict:
    if not isinstance(payload, dict):
        raise ValueError("Invalid save request")
    apps = {app.id: app for app in discover_apps()}
    desktop_id = str(payload.get("id", ""))
    app = apps.get(desktop_id)
    if app is None:
        raise ValueError("That application is no longer installed")
    mode = str(payload.get("mode", "default"))
    if mode not in {"default", "floating", "floating-center"}:
        raise ValueError("Unknown window behavior")
    options = _rule_options(payload, mode)
    settings = load_settings()
    has_options = any((options["maximize"], options["fullscreen"], options["pin"], options["size"], options["move"], options["workspace"]))
    if mode == "default" and not has_options:
        settings["apps"].pop(desktop_id, None)
    else:
        class_name = str(payload.get("class", "") or app.wm_class).strip()
        initial_title = str(payload.get("initial_title", "")).strip()
        class_regex(class_name)
        if initial_title:
            class_regex(initial_title)
        settings["apps"][desktop_id] = {
            "name": app.name,
            "class": class_name,
            "initial_title": initial_title,
            "mode": mode,
            **options,
        }
    save_settings(settings)
    result = subprocess.run(["hyprctl", "reload"], capture_output=True, text=True, check=False)
    return {"ok": result.returncode == 0, "message": "Saved and reloaded" if result.returncode == 0 else "Saved; Hyprland reload failed"}


def main(argv: list[str]) -> int:
    try:
        if argv == ["apps"]:
            response = list_apps()
        elif argv == ["windows"]:
            response = list_windows()
        elif len(argv) == 2 and argv[0] == "save":
            response = save_app(json.loads(argv[1]))
        else:
            raise ValueError("Invalid Omanager command")
    except (OSError, ValueError, json.JSONDecodeError, subprocess.CalledProcessError) as error:
        response = {"ok": False, "error": str(error)}
    print(json.dumps(response, ensure_ascii=False))
    return 0 if response.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
