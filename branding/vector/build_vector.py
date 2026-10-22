"""Write the SVG masters and the render job list. Run: python3 -I build_vector.py <repo_root>"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dt_art as A

root = sys.argv[1]
V = f"{root}/branding/vector"
files = {"icon.svg": A.icon_svg(), "icon_round.svg": A.icon_svg(True), "foreground.svg": A.foreground_svg(),
         "background.svg": A.background_svg(), "monochrome.svg": A.monochrome_svg()}
for n, s in files.items():
    open(f"{V}/{n}", "w").write(s)

jobs = [
    {"svg": f"{V}/icon.svg", "out": f"{root}/branding/icon/dt_food_pos_icon_1024.png", "size": 1024},
    {"svg": f"{V}/icon.svg", "out": f"{root}/branding/icon/playstore_512.png", "size": 512},
    {"svg": f"{V}/foreground.svg", "out": f"{root}/branding/icon/ic_launcher_foreground.png", "size": 1024, "transparent": True},
    {"svg": f"{V}/foreground.svg", "out": f"{root}/branding/icon/art_foreground_2048.png", "size": 2048, "transparent": True},
    {"svg": f"{V}/monochrome.svg", "out": f"{root}/branding/icon/ic_launcher_monochrome.png", "size": 1024, "transparent": True},
    {"svg": f"{V}/background.svg", "out": f"{root}/branding/icon/ic_launcher_background.png", "size": 1024},
]
for d, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
    r, fp = f"{root}/android-res/mipmap-{d}", round(px * 108 / 48)
    jobs += [{"svg": f"{V}/icon.svg", "out": f"{r}/ic_launcher.png", "size": px},
             {"svg": f"{V}/icon_round.svg", "out": f"{r}/ic_launcher_round.png", "size": px, "transparent": True},
             {"svg": f"{V}/foreground.svg", "out": f"{r}/ic_launcher_foreground.png", "size": fp, "transparent": True},
             {"svg": f"{V}/monochrome.svg", "out": f"{r}/ic_launcher_monochrome.png", "size": fp, "transparent": True},
             {"svg": f"{V}/background.svg", "out": f"{r}/ic_launcher_background.png", "size": fp}]
open(f"{V}/mark_white.svg", "w").write(
    f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="-1 0 340 340" width="1024" height="1024"><defs/>{A.mark_svg_raw("#FFFFFF")}</svg>')
jobs.append({"svg": f"{V}/mark_white.svg", "out": f"{root}/branding/animation/dt_mark_white.png", "size": 128, "transparent": True})
json.dump(jobs, open(f"{V}/render_jobs.json", "w"), indent=1)
print(len(jobs), "render jobs")
