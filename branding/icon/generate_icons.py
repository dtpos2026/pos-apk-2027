import sys, os
from PIL import Image
import numpy as np
src="/root/.claude/uploads/7d752d48-b39d-555c-8e86-fbd844d93a0d/666e925b-image.jpg"
im=Image.open(src).convert("RGB")
a=np.asarray(im).astype(float)
bg=np.median(a[:200,:200].reshape(-1,3),axis=0)
print("bg",bg, "#%02X%02X%02X"%tuple(int(x) for x in bg))
lum=a.mean(axis=2)
lo=lum[:200,:200].mean()
alpha=np.clip((lum-lo)/(255-lo),0,1)
# mark region only (exclude text, x>520)
m=alpha.copy(); m[:, 540:]=0
ys,xs=np.where(m>0.5); x0,x1,y0,y1=xs.min(),xs.max(),ys.min(),ys.max()
print(x0,x1,y0,y1)
mark=m[y0-2:y1+3, x0-2:x1+3]
S=4096
def render(canvas, frac, bgcol=None, color=(255,255,255)):
    h,w=mark.shape; s=canvas*frac/max(h,w)
    mk=Image.fromarray((mark*255).astype("uint8")).resize((round(w*s),round(h*s)),Image.LANCZOS)
    base=Image.new("RGBA",(canvas,canvas),(0,0,0,0) if bgcol is None else bgcol+(255,))
    layer=Image.new("RGBA",mk.size,color+(255,)); layer.putalpha(mk)
    base.alpha_composite(layer,((canvas-mk.width)//2,(canvas-mk.height)//2))
    return base
P=(0x3D,0x09,0x6D)
out="branding/icon"
render(1024,0.50,P).convert("RGB").save(f"{out}/dt_food_pos_icon_1024.png")          # store/legacy
render(1024,0.40,None).save(f"{out}/ic_launcher_foreground.png")                       # adaptive fg (safe zone)
Image.new("RGB",(1024,1024),P).save(f"{out}/ic_launcher_background.png")
render(1024,0.40,None,(0,0,0)).save(f"{out}/ic_launcher_monochrome.png")
# Android mipmaps
dens={"mdpi":48,"hdpi":72,"xhdpi":96,"xxhdpi":144,"xxxhdpi":192}
fg=render(1024,0.40,None); full=render(1024,0.50,P)
for d,px in dens.items():
    r=f"android-res/mipmap-{d}"; os.makedirs(r,exist_ok=True)
    full.convert("RGB").resize((px,px),Image.LANCZOS).save(f"{r}/ic_launcher.png")
    # round
    ic=full.resize((px*4,px*4),Image.LANCZOS)
    mask=Image.new("L",ic.size,0)
    from PIL import ImageDraw
    ImageDraw.Draw(mask).ellipse((0,0,ic.size[0]-1,ic.size[1]-1),fill=255); ic.putalpha(mask)
    ic.resize((px,px),Image.LANCZOS).save(f"{r}/ic_launcher_round.png")
    fpx=round(px*108/48)
    fg.resize((fpx,fpx),Image.LANCZOS).save(f"{r}/ic_launcher_foreground.png")
    render(1024,0.40,None,(0,0,0)).resize((fpx,fpx),Image.LANCZOS).save(f"{r}/ic_launcher_monochrome.png")
render(512,0.50,P).convert("RGB").save(f"{out}/playstore_512.png")
# preview sheet
sheet=Image.new("RGB",(1400,520),(235,235,240))
sq=full.resize((400,400),Image.LANCZOS).convert("RGB")
from PIL import ImageDraw
rr=Image.new("L",(400,400),0); ImageDraw.Draw(rr).rounded_rectangle((0,0,399,399),90,fill=255)
ci=Image.new("L",(400,400),0); ImageDraw.Draw(ci).ellipse((0,0,399,399),fill=255)
sheet.paste(sq,(40,60),rr); sheet.paste(sq,(500,60),ci)
for i,s in enumerate((144,96,48)):
    sheet.paste(sq.resize((s,s),Image.LANCZOS),(960+i*150 if i<2 else 1260,60),Image.new("L",(s,s),255) if False else None)
sheet.save(f"{out}/preview.png")
