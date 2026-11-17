"""Regenerate dmg-layout.dsstore with ds_store==1.3.3 (authoring only).

Normal packaging copies the committed file and requires no Python packages.
"""
from pathlib import Path

from ds_store import DSStore


def generate(output):
    with DSStore.open(str(output), "w+") as store:
        store["."]["vSrn"] = ("long", 1)
        store["."]["icvl"] = ("type", b"icnv")
        store["."]["bwsp"] = {
            "WindowBounds": "{{10, 60}, {560, 340}}",
            "ShowToolbar": False,
            "ShowStatusBar": False,
            "ShowTabView": False,
            "ShowPathbar": False,
            "ShowSidebar": False,
            "ContainerShowSidebar": False,
            "PreviewPaneVisibility": False,
        }
        store["."]["icvp"] = {
            "viewOptionsVersion": 1,
            "iconSize": 100.0,
            "textSize": 16.0,
            "arrangeBy": "none",
            "labelOnBottom": True,
            "showIconPreview": True,
            "showItemInfo": False,
            "gridOffsetX": 0.0,
            "gridOffsetY": 0.0,
            "gridSpacing": 100.0,
            "scrollPositionX": 0.0,
            "scrollPositionY": 0.0,
            "backgroundType": 0,
            "backgroundColorRed": 1.0,
            "backgroundColorGreen": 1.0,
            "backgroundColorBlue": 1.0,
        }
        store["AropytEditor.app"]["Iloc"] = (140, 170)
        store["Applications"]["Iloc"] = (420, 170)


if __name__ == "__main__":
    generate(Path(__file__).with_name("dmg-layout.dsstore"))
