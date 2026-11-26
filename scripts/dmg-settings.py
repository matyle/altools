# dmgbuild settings for build/Altools.dmg. Called by scripts/build-app.sh with
# -D app=<path to Altools.app> -D background=<path to the background PNG>.
import os

app = defines["app"]  # noqa: F821 (dmgbuild provides `defines`)
files = [app]
symlinks = {"Applications": "/Applications"}
icon_locations = {os.path.basename(app): (140, 190), "Applications": (400, 190)}
background = defines["background"]  # noqa: F821
window_rect = ((200, 200), (540, 380))
icon_size = 112
text_size = 13
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
default_view = "icon-view"
format = "UDZO"
filesystem = "HFS+"
