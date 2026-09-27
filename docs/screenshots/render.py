#!/usr/bin/env python3
"""Synthetic OhmTabs gallery frames. Solid theme colours, no live desktop."""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = Path(__file__).resolve().parent
ROOT = OUT.parent.parent
PREVIEW = ROOT / "preview.png"

BG = (11, 15, 20)
SURFACE = (28, 35, 44)
STRIP = (36, 46, 56)
PILL = (22, 29, 38, 210)
ACCENT = (56, 200, 232)
TEXT = (200, 214, 220)
MUTED = (122, 136, 148)
INK = (14, 20, 26)
DOT = (56, 200, 232)
WIN = (18, 24, 31)
BORDER = (56, 200, 232)

FONT = "/usr/share/fonts/noto/NotoSans-Regular.ttf"
FONTB = "/usr/share/fonts/noto/NotoSans-SemiBold.ttf"
if not Path(FONTB).exists():
    FONTB = FONT


def font(size, bold=False):
    return ImageFont.truetype(FONTB if bold else FONT, size)


def new(w, h, color=BG):
    return Image.new("RGBA", (w, h), color + ((255,) if len(color) == 3 else ()))


def rr(draw, box, r, fill=None, outline=None, width=1):
    draw.rounded_rectangle(box, radius=r, fill=fill, outline=outline, width=width)


def icon_tile(draw, cx, cy, r, letter, fill, ink=INK):
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=fill)
    f = font(int(r * 0.95), bold=True)
    bbox = draw.textbbox((0, 0), letter, font=f)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    draw.text((cx - tw / 2 - bbox[0], cy - th / 2 - bbox[1] - 1), letter, font=f, fill=ink)


def title_strip(im, x, y, w, h, title="App window"):
    d = ImageDraw.Draw(im)
    rr(d, (x, y, x + w, y + h), 0, fill=STRIP)
    f = font(16)
    bbox = d.textbbox((0, 0), title, font=f)
    tw = bbox[2] - bbox[0]
    d.text((x + (w - tw) / 2, y + (h - 20) / 2), title, font=f, fill=ACCENT)
    # − □ ×
    right = x + w - 18
    for glyph, dx in (("×", 0), ("□", 28), ("−", 56)):
        d.text((right - dx - 12, y + (h - 18) / 2), glyph, font=font(15), fill=ACCENT)


def pill_dock(im, cy, icons, hover_i=None, hover_label=None):
    d = ImageDraw.Draw(im)
    n = len(icons)
    gap = 14
    r = 18
    inner = n * (r * 2) + (n - 1) * gap
    pad_x, pad_y = 22, 12
    w = inner + pad_x * 2
    h = r * 2 + pad_y * 2
    x = (im.width - w) // 2
    y = cy - h // 2
    # glass pill
    layer = Image.new("RGBA", im.size, (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    rr(ld, (x, y, x + w, y + h), h // 2, fill=PILL, outline=ACCENT + (180,), width=2)
    im.alpha_composite(layer)
    d = ImageDraw.Draw(im)
    for i, (letter, fill) in enumerate(icons):
        cx = x + pad_x + r + i * (r * 2 + gap)
        cyi = y + h // 2
        if hover_i == i:
            icon_tile(d, cx, cyi - 6, r + 4, letter, fill)
            if hover_label:
                card_w, card_h = 92, 28
                cx0 = cx - card_w // 2
                cy0 = y - card_h - 10
                rr(d, (cx0, cy0, cx0 + card_w, cy0 + card_h), 10, fill=(22, 29, 38, 230), outline=ACCENT, width=1)
                f = font(12, bold=True)
                bbox = d.textbbox((0, 0), hover_label, font=f)
                tw = bbox[2] - bbox[0]
                d.text((cx - tw / 2, cy0 + 6), hover_label, font=f, fill=TEXT)
        else:
            icon_tile(d, cx, cyi, r, letter, fill)
        # running dot
        d.ellipse((cx - 2, y + h - 8, cx + 2, y + h - 4), fill=DOT)
    return x, y, w, h


def desktop():
    im = new(1280, 720)
    d = ImageDraw.Draw(im)
    # fake window
    wx, wy, ww, wh = 160, 70, 960, 520
    rr(d, (wx, wy, wx + ww, wy + wh), 10, fill=WIN, outline=(40, 52, 64), width=1)
    title_strip(im, wx, wy, ww, 42, "Terminal")
    d = ImageDraw.Draw(im)
    d.text((wx + 28, wy + 70), "$  ", font=font(18), fill=MUTED)
    d.text((wx + 56, wy + 70), "ohmtabs status", font=font(18), fill=ACCENT)
    icons = [("T", (120, 200, 180)), ("F", (90, 160, 210)), ("B", (210, 140, 90)), ("N", (180, 120, 200)), ("C", (56, 200, 232))]
    pill_dock(im, 660, icons, hover_i=4, hover_label="Chat")
    cap = "Diagram — not a live desktop"
    f = font(12)
    bbox = d.textbbox((0, 0), cap, font=f)
    d.text((24, 720 - 28), cap, font=f, fill=MUTED)
    return im.convert("RGB")


def strip_only():
    im = new(1240, 42, STRIP)
    title_strip(im, 0, 0, 1240, 42, "App window")
    return im.convert("RGB")


def taskbar_only():
    im = new(720, 90)
    icons = [("T", (120, 200, 180)), ("F", (90, 160, 210)), ("B", (210, 140, 90)), ("N", (180, 120, 200)), ("C", (56, 200, 232))]
    pill_dock(im, 45, icons)
    return im.convert("RGB")


def hover_card():
    im = new(720, 140)
    icons = [("T", (120, 200, 180)), ("F", (90, 160, 210)), ("B", (210, 140, 90)), ("C", (56, 200, 232))]
    pill_dock(im, 90, icons, hover_i=3, hover_label="Chat")
    return im.convert("RGB")


def alttab():
    im = new(900, 280)
    d = ImageDraw.Draw(im)
    cards = [("Terminal", True), ("Files", False), ("Browser", False), ("Notes", False)]
    n = len(cards)
    cw, ch, gap = 170, 150, 18
    total = n * cw + (n - 1) * gap
    x0 = (im.width - total) // 2
    y0 = 50
    d.text((im.width // 2 - 70, 16), "Alt+Tab", font=font(16, bold=True), fill=MUTED)
    for i, (name, on) in enumerate(cards):
        x = x0 + i * (cw + gap)
        fill = (28, 40, 50) if on else (22, 29, 38)
        outline = ACCENT if on else (50, 62, 74)
        rr(d, (x, y0, x + cw, y0 + ch), 16, fill=fill, outline=outline, width=2 if on else 1)
        icon_tile(d, x + cw // 2, y0 + 58, 28, name[0], ACCENT if on else (90, 110, 120), ink=INK)
        f = font(14, bold=True)
        bbox = d.textbbox((0, 0), name, font=f)
        tw = bbox[2] - bbox[0]
        d.text((x + (cw - tw) / 2, y0 + 108), name, font=f, fill=TEXT if on else MUTED)
    return im.convert("RGB")


def settings_card():
    W, H = 420, 640
    im = new(W, H, (16, 22, 28))
    d = ImageDraw.Draw(im)
    rr(d, (8, 8, W - 8, H - 8), 18, fill=(22, 29, 38), outline=ACCENT, width=2)
    d.text((28, 24), "Dock Settings", font=font(18, bold=True), fill=TEXT)
    d.text((W - 44, 24), "✕", font=font(16), fill=TEXT)

    rows = [
        ("Icon size", "38 px", None),
        ("Auto-hide", None, False),
        ("Position", "Bottom", None),
        ("Full length", None, False),
        ("Corner shape", "Pill", None),
        ("Icon magnify", None, True),
        ("Apps button", None, True),
        ("Running apps", None, True),
        ("Workspaces", None, False),
        ("Active window", None, False),
        ("Status chips", None, False),
        ("Icon name on hover", None, True),
        ("OhmTabs", None, True),
        ("Omarchy bar controls", None, False),
    ]
    y = 70
    for title, value, on in rows:
        d.text((28, y), title, font=font(14, bold=True), fill=TEXT)
        if value:
            d.text((W - 28 - d.textbbox((0, 0), value, font=font(12))[2], y + 2), value, font=font(12), fill=ACCENT)
        elif on is not None:
            # toggle
            tw, th = 42, 22
            tx, ty = W - 28 - tw, y
            fill = ACCENT if on else (50, 60, 70)
            rr(d, (tx, ty, tx + tw, ty + th), 11, fill=fill)
            kx = tx + tw - 12 if on else tx + 12
            d.ellipse((kx - 8, ty + 3, kx + 8, ty + 19), fill=INK if on else TEXT)
        y += 38
    return im.convert("RGB")


def preview():
    im = new(1280, 800)
    d = ImageDraw.Draw(im)
    d.text((48, 36), "OhmTabs", font=font(28, bold=True), fill=TEXT)
    d.text((48, 76), "Title strips · pill taskbar · Alt+Tab for Omarchy", font=font(16), fill=MUTED)
    # window
    wx, wy, ww, wh = 80, 130, 1120, 500
    rr(d, (wx, wy, wx + ww, wy + wh), 12, fill=WIN, outline=(40, 52, 64), width=1)
    title_strip(im, wx, wy, ww, 44, "Terminal")
    d = ImageDraw.Draw(im)
    d.text((wx + 32, wy + 80), "$ ohmtabs status", font=font(18), fill=ACCENT)
    # mini alt-tab overlay inside window
    cards = [("Term", True), ("Files", False), ("Web", False)]
    cx0, cy0 = wx + 280, wy + 200
    for i, (name, on) in enumerate(cards):
        x = cx0 + i * 180
        rr(d, (x, cy0, x + 150, cy0 + 130), 14, fill=(28, 40, 50) if on else (22, 29, 38), outline=ACCENT if on else (50, 62, 74), width=2 if on else 1)
        icon_tile(d, x + 75, cy0 + 50, 22, name[0], ACCENT if on else (90, 110, 120))
        f = font(13, bold=True)
        bbox = d.textbbox((0, 0), name, font=f)
        d.text((x + 75 - (bbox[2] - bbox[0]) / 2, cy0 + 90), name, font=f, fill=TEXT)
    icons = [("T", (120, 200, 180)), ("F", (90, 160, 210)), ("B", (210, 140, 90)), ("N", (180, 120, 200)), ("C", (56, 200, 232))]
    pill_dock(im, 730, icons, hover_i=0, hover_label="Terminal")
    d = ImageDraw.Draw(im)
    d.text((48, 770), "Diagram — not a live desktop", font=font(12), fill=MUTED)
    return im.convert("RGB")


def save_rgb(im, path, size=None):
    if size:
        im = im.resize(size, Image.Resampling.LANCZOS)
    im = im.convert("RGB")
    im.save(path, "PNG", optimize=True)
    print("wrote", path, im.size)


def main():
    save_rgb(desktop(), OUT / "desktop.png")
    save_rgb(strip_only(), OUT / "title-strip.png")
    save_rgb(taskbar_only(), OUT / "taskbar.png")
    save_rgb(hover_card(), OUT / "hover.png")
    save_rgb(alttab(), OUT / "alttab.png")
    save_rgb(settings_card(), OUT / "settings.png")
    save_rgb(preview(), PREVIEW)
    # drawer leftover: keep a small generic overlay
    im = new(560, 220)
    d = ImageDraw.Draw(im)
    rr(d, (12, 12, 548, 208), 16, fill=(22, 29, 38), outline=ACCENT, width=2)
    d.text((32, 28), "Minimized windows", font=font(16, bold=True), fill=TEXT)
    for i, name in enumerate(["Terminal  ·  workspace 1", "Notes  ·  workspace 2"]):
        y = 72 + i * 48
        rr(d, (32, y, 528, y + 40), 10, fill=(28, 36, 46))
        d.text((48, y + 10), name, font=font(14), fill=TEXT)
    save_rgb(im, OUT / "drawer.png")


if __name__ == "__main__":
    main()
