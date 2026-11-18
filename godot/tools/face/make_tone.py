# Turn any portrait (or a halftone of one) into scripts/FaceTone.gd:   python tools/face/make_tone.py portrait.png
import sys, io, base64
from PIL import Image, ImageFilter
im = Image.open(sys.argv[1]).convert("L").filter(ImageFilter.GaussianBlur(5)).resize((120, 180), Image.LANCZOS)
lo, hi = min(im.getdata()), max(im.getdata())
im = im.point(lambda v: int(255 * max(0, min(1, (v - lo) / max(1, hi - lo)))))
buf = io.BytesIO()
im.save(buf, "PNG", optimize=True)
src = open("scripts/FaceTone.gd").read()
i = src.index('const PNG_B64 := "') + len('const PNG_B64 := "')
j = src.index('"', i)
open("scripts/FaceTone.gd", "w").write(src[:i] + base64.b64encode(buf.getvalue()).decode() + src[j:])
