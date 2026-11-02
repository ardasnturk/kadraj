# dmgbuild settings for the Kadraj installer window. Positions must match
# scripts/make-dmg-background.swift.
#   dmgbuild -s scripts/dmg-settings.py -D app=build/Kadraj.app -D background=... Kadraj out.dmg
import os

app = defines["app"]  # noqa: F821 (provided by dmgbuild)
app_name = os.path.basename(app)

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(app, "Contents", "Resources", "AppIcon.icns")

background = defines["background"]  # noqa: F821
# The height adds room for the title bar so the whole 640x400 background shows.
window_rect = ((200, 120), (640, 428))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 112
text_size = 13
icon_locations = {
    app_name: (170, 200),
    "Applications": (470, 200),
}
