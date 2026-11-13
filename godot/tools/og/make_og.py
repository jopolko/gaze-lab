"""Builds og.png (1200x630), the picture a link preview shows. Real in-game frames (shot_*.jpg) in rounded cards, plus the title and a few features.
    python tools/og/make_og.py   ->  tools/og/og.png
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter, ImageFont

here = os.path.dirname(os.path.abspath(__file__))
W, H = 1200, 630
F = "C:/Windows/Fonts/"


def font(name, size):
    return ImageFont.truetype(F + name, size)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


# ---- background: dusk gradient, a glow, stars
bg = Image.new("RGB", (W, H))
px = bg.load()
top, mid, bot = (14, 10, 40), (58, 22, 92), (150, 40, 120)
for y in range(H):
    t = y / (H - 1)
    c = lerp(top, mid, t / 0.6) if t < 0.6 else lerp(mid, bot, (t - 0.6) / 0.4)
    for x in range(W):
        px[x, y] = c
glow = Image.new("RGB", (W, H), (0, 0, 0))
gd = ImageDraw.Draw(glow)
gd.ellipse((560, 120, 1240, 800), fill=(110, 40, 150))
gd.ellipse((-200, 380, 520, 900), fill=(40, 90, 140))
glow = glow.filter(ImageFilter.GaussianBlur(120))
bg = Image.blend(bg, Image.eval(glow, lambda v: v), 0.55)
random.seed(7)
sd = ImageDraw.Draw(bg)
for _ in range(110):
    x, y, r = random.randint(0, W), random.randint(0, int(H * 0.55)), random.choice((1, 1, 1, 2))
    a = random.randint(90, 220)
    sd.ellipse((x - r, y - r, x + r, y + r), fill=(a, a, 255))

# ---- low-poly mountains along the bottom left, behind the text
mt = Image.new("RGBA", (W, H), (0, 0, 0, 0))
md = ImageDraw.Draw(mt)
md.polygon([(0, 630), (0, 470), (130, 380), (250, 480), (390, 360), (560, 520), (700, 630)], fill=(34, 20, 76, 255))
md.polygon([(0, 630), (0, 540), (110, 470), (230, 560), (330, 500), (470, 600), (520, 630)], fill=(24, 14, 58, 255))
bg = Image.alpha_composite(bg.convert("RGBA"), mt)


def card(path, crop, size, radius=26, border=(255, 120, 230)):
    im = Image.open(path).convert("RGB").crop(crop)
    im = im.resize(size, Image.LANCZOS)
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius, fill=255)
    out = Image.new("RGBA", (size[0] + 12, size[1] + 12), (0, 0, 0, 0))
    d = ImageDraw.Draw(out)
    d.rounded_rectangle((0, 0, size[0] + 11, size[1] + 11), radius + 4, fill=border + (255,))
    out.paste(im, (6, 6), mask)
    return out


def shadowed(base, im, pos, blur=22, off=(0, 14), alpha=170):
    sh = Image.new("RGBA", base.size, (0, 0, 0, 0))
    m = Image.new("L", im.size, 0)
    m.paste(im.split()[3], (0, 0))
    sh.paste((0, 0, 0, alpha), (pos[0] + off[0], pos[1] + off[1]), m)
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    base = Image.alpha_composite(base, sh)
    base.alpha_composite(im, pos)
    return base


# the two real frames (crop away the debug fps label and the little buttons)
big = card(os.path.join(here, "shot_cave.jpg"), (0, 88, 742, 420), (590, 264), border=(120, 255, 230))
small = card(os.path.join(here, "shot_psy.jpg"), (0, 64, 742, 420), (470, 226), border=(255, 130, 230))
bg = shadowed(bg, big.rotate(2.2, resample=Image.BICUBIC, expand=True), (600, 84))
bg = shadowed(bg, small.rotate(-3.0, resample=Image.BICUBIC, expand=True), (700, 372))

d = ImageDraw.Draw(bg)

# ---- logo: a ring (an eye's outline) with two peaks and a dot for the iris, as on the title screen
lx, ly, lr = 118, 108, 56
d.arc((lx - lr, ly - lr, lx + lr, ly + lr), 150, 30 + 360, fill=(235, 238, 250), width=6)
d.polygon([(lx - 40, ly + 32), (lx - 6, ly - 22), (lx + 20, ly + 32)], fill=(235, 238, 250))
d.polygon([(lx + 4, ly + 32), (lx + 24, ly - 4), (lx + 44, ly + 32)], fill=(200, 205, 230))
d.ellipse((lx + 30, ly - 46, lx + 44, ly - 32), outline=(235, 238, 250), width=4)

# ---- title
tf = font("seguibl.ttf", 92)
d.text((45, 176), "DOWNHILL", font=tf, fill=(0, 0, 0, 120))
d.text((41, 172), "DOWNHILL", font=tf, fill=(246, 247, 255))
sf = font("segoeuib.ttf", 40)
d.text((44, 292), "steer with your eyes", font=sf, fill=(255, 190, 245))


# ---- features as chips
def chip(x, y, text, col, f=font("segoeuib.ttf", 27)):
    global bg, d
    w = d.textlength(text, font=f)
    ov = Image.new("RGBA", bg.size, (0, 0, 0, 0))
    od = ImageDraw.Draw(ov)
    od.rounded_rectangle((x, y, x + w + 40, y + 52), 26, fill=(20, 12, 50, 175), outline=col + (255,), width=3)
    bg = Image.alpha_composite(bg, ov)
    d = ImageDraw.Draw(bg)
    d.text((x + 20, y + 7), text, font=f, fill=(250, 250, 255))
    return x + w + 40 + 14


y0 = 362
x = chip(40, y0, "no controller", (120, 255, 230))
x = chip(x, y0, "just a camera", (120, 255, 230))
x = chip(40, y0 + 66, "10 weird realms", (255, 130, 230))
x = chip(40, y0 + 132, "mystery gates", (255, 210, 120))
x = chip(x, y0 + 132, "5 themes", (255, 210, 120))
d.text((44, 568), "the camera never leaves your device", font=font("segoeuii.ttf", 24), fill=(205, 200, 235))

out = bg.convert("RGB")
out.save(os.path.join(here, "og.png"), optimize=True)
print("og.png", out.size, os.path.getsize(os.path.join(here, "og.png")) // 1024, "KB")
