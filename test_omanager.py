import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import omanager
from omanager import class_regex, discover_apps, render_lua


class OmanagerTests(unittest.TestCase):
    def test_save_enables_rules_once_without_clobbering_config(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            main = root / "hyprland.lua"
            main.write_text("-- personal config (no final newline)", encoding="utf-8")
            with patch.object(omanager, "HYPR_MAIN", main), patch.object(omanager, "HYPR_CONFIG", root / "omanager.lua"), patch.object(omanager, "CONFIG", root / "settings.json"):
                omanager.save_settings({"apps": {"demo.desktop": {"class": "demo", "mode": "floating"}}})
                omanager.save_settings({"apps": {"demo.desktop": {"class": "demo", "mode": "floating"}}})
                self.assertEqual(main.read_text(encoding="utf-8"), '-- personal config (no final newline)\nrequire("hypr.omanager")\n')
                self.assertIn("float = true", (root / "omanager.lua").read_text(encoding="utf-8"))

    def test_discovery_respects_precedence_and_hidden_entries(self):
        with tempfile.TemporaryDirectory() as temporary:
            user = Path(temporary) / "user"
            system = Path(temporary) / "system"
            user_apps = user / "applications"
            system_apps = system / "applications"
            user_apps.mkdir(parents=True)
            system_apps.mkdir(parents=True)
            (user_apps / "demo.desktop").write_text(
                "[Desktop Entry]\nType=Application\nName=User Demo\nExec=demo\n", encoding="utf-8"
            )
            (system_apps / "demo.desktop").write_text(
                "[Desktop Entry]\nType=Application\nName=System Demo\nExec=demo\n", encoding="utf-8"
            )
            (user_apps / "hidden.desktop").write_text(
                "[Desktop Entry]\nType=Application\nName=Hidden\nHidden=true\n", encoding="utf-8"
            )
            apps = discover_apps([user, system])
            self.assertEqual([(app.id, app.name) for app in apps], [("demo.desktop", "User Demo")])

    def test_lua_rule_anchors_and_escapes_class(self):
        self.assertEqual(class_regex("org.example.App"), r"^org\.example\.App$")
        lua = render_lua({"apps": {"demo.desktop": {
            "class": "com.mitchellh.ghostty",
            "initial_title": "Omanager-NukeX-17.1",
            "mode": "floating-center",
        }}})
        self.assertIn(r'class = "^com\\.mitchellh\\.ghostty$"', lua)
        self.assertIn(r'initial_title = "^Omanager-NukeX-17\\.1$"', lua)
        self.assertIn("float = true, center = true", lua)

    def test_lua_rules_include_floating_and_workspace_options(self):
        lua = render_lua({"apps": {"demo.desktop": {
            "class": "demo",
            "mode": "floating",
            "pin": True,
            "size": [900, 700],
            "move": [30, 40],
            "maximize": True,
            "fullscreen": True,
            "workspace": "3",
            "workspace_silent": False,
        }}})
        self.assertIn('float = true, pin = true, size = { 900, 700 }, move = { 30, 40 }, maximize = true, fullscreen = true, workspace = "3"', lua)

    def test_tiled_rules_and_invalid_options(self):
        lua = render_lua({"apps": {"demo.desktop": {
            "class": "demo",
            "mode": "default",
            "maximize": True,
            "workspace": "4",
        }}})
        self.assertIn('tile = true, maximize = true, workspace = "4 silent"', lua)
        with self.assertRaises(ValueError):
            render_lua({"apps": {"demo.desktop": {
                "class": "demo",
                "mode": "floating",
                "workspace": '3", pin = true',
            }}})
        with self.assertRaises(ValueError):
            render_lua({"apps": {"demo.desktop": {
                "class": "demo",
                "mode": "floating",
                "size": [0, 700],
            }}})


if __name__ == "__main__":
    unittest.main()
