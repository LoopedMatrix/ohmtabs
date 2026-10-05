#!/usr/bin/env python3
"""OhmTabs gallery frames. Solid canvas, glass chrome — no live desktop."""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parent
ROOT = OUT.parent.parent
PREVIEW = ROOT / "preview.png"

# Flat canvas in the current Omarchy-dark family (not the user's wallpaper).
BG = (10, 8, 22)
WIN = (16, 14, 32)
PILL = (14, 9, 29, 220)
ACCENT = (190, 63, 80)
TEXT = (20, 185, 181)
MUTED = (90, 140, 145)
INK = (10, 8, 22)
GLYPH = (200, 230, 230)

FONT = "/usr/share/fonts/noto/NotoSans-Regular.ttf"
FONTB = "/usr/share/fonts/noto/NotoSans-SemiBold.ttf"
if not Path(FONTB).exists():
    FONTB = FONT


def font(size, bold=False):
    return ImageFont.truetype(FONTB if bold else FONT, size)


def new(w, h, color=BG):
    if len(color) == 3:
        color = color + (255,)
    return Image.new("RGBA", (w, h), color)


def rr(draw, box, r, fill=None, outline=None, width=1):
    draw.rounded_rectangle(box, radius=r, fill=fill, outline=outline, width=width)


def glass_pill(im, box, fill=PILL, outline=ACCENT, width=2):
    layer = Image.new("RGBA", im.size, (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    x0, y0, x1, y1 = box
    h = y1 - y0
    ol = outline + ((220,) if len(outline) == 3 else ())
    rr(ld, box, h // 2, fill=fill, outline=ol, width=width)
    im.alpha_composite(layer)


def hamburger(d, x, y, s=14, color=TEXT):
    for i in range(3):
        yy = y + i * (s // 3 + 1)
        d.line((x, yy, x + s, yy), fill=color, width=2)


def win_btns(d, right, cy, color=TEXT):
    f = font(14)
    for glyph, dx in (("×", 0), ("□", 26), ("−", 52)):
        d.text((right - dx - 12, cy - 9), glyph, font=f, fill=color)


def title_strip_pill(im, x, y, w, h, title="App window"):
    glass_pill(im, (x, y, x + w, y + h), fill=PILL, outline=ACCENT, width=2)
    d = ImageDraw.Draw(im)
    hamburger(d, x + 16, y + h // 2 - 6)
    f = font(15, bold=True)
    bbox = d.textbbox((0, 0), title, font=f)
    tw = bbox[2] - bbox[0]
    d.text((x + (w - tw) / 2, y + (h - 20) / 2), title, font=f, fill=TEXT)
    win_btns(d, x + w - 18, y + h // 2)


def symbol(d, kind, cx, cy, r):
    """Geometric glyphs — not letter tiles, not live app brands."""
    col = GLYPH
    if kind == "term":
        d.rounded_rectangle((cx - r + 2, cy - r + 4, cx + r - 2, cy + r - 4), 4, outline=col, width=2)
        d.line((cx - r + 8, cy - 2, cx - 2, cy + 6), fill=col, width=2)
        d.line((cx + 2, cy + 6, cx + r - 8, cy + 6), fill=col, width=2)
    elif kind == "files":
        d.polygon(
            [
                (cx - r + 4, cy - 2),
                (cx - 2, cy - 2),
                (cx + 2, cy - r + 4),
                (cx + r - 4, cy - r + 4),
                (cx + r - 4, cy + r - 4),
                (cx - r + 4, cy + r - 4),
            ],
            outline=col,
        )
        d.line((cx - r + 4, cy - 2, cx + r - 4, cy - 2), fill=col, width=1)
    elif kind == "web":
        d.ellipse((cx - r + 3, cy - r + 3, cx + r - 3, cy + r - 3), outline=col, width=2)
        d.ellipse((cx - r + 8, cy - r + 3, cx + r - 8, cy + r - 3), outline=col, width=1)
        d.line((cx - r + 3, cy, cx + r - 3, cy), fill=col, width=1)
    elif kind == "notes":
        d.rounded_rectangle((cx - r + 5, cy - r + 2, cx + r - 5, cy + r - 2), 3, outline=col, width=2)
        d.line((cx - 4, cy - 4, cx + 4, cy - 4), fill=col, width=1)
        d.line((cx - 4, cy + 2, cx + 4, cy + 2), fill=col, width=1)
    else:
        d.ellipse((cx - r + 3, cy - r + 2, cx + r - 3, cy + r - 8), outline=col, width=2)
        d.polygon([(cx - 4, cy + r - 10), (cx - r + 6, cy + r - 3), (cx + 2, cy + r - 10)], outline=col)


def start_glyph(d, cx, cy, s=9, color=GLYPH):
    g = 2
    cell = s // 2
    origin_x = cx - s - g // 2
    origin_y = cy - s - g // 2
    for i in range(2):
        for j in range(2):
            x0 = origin_x + i * (cell + g)
            y0 = origin_y + j * (cell + g)
            d.rectangle((x0, y0, x0 + cell - 1, y0 + cell - 1), fill=color)


def pill_dock(im, cy, kinds, hover_i=None, hover_label=None, start=True):
    n = len(kinds)
    gap, r = 16, 17
    start_w = (r * 2 + 10) if start else 0
    inner = n * (r * 2) + (n - 1) * gap + start_w
    pad_x, pad_y = 22, 11
    w = inner + pad_x * 2
    h = r * 2 + pad_y * 2
    x = (im.width - w) // 2
    y = cy - h // 2
    glass_pill(im, (x, y, x + w, y + h), fill=PILL, outline=ACCENT, width=2)
    d = ImageDraw.Draw(im)
    ox = x + pad_x
    cyi = y + h // 2
    if start:
        tile = r * 2 + 4
        rr(d, (ox, cyi - tile // 2, ox + tile, cyi + tile // 2), 10, fill=ACCENT)
        start_glyph(d, ox + tile // 2, cyi, s=8, color=GLYPH)
        ox += tile + gap
    for i, kind in enumerate(kinds):
        cx = ox + r + i * (r * 2 + gap)
        if hover_i == i:
            symbol(d, kind, cx, cyi - 5, r + 3)
            if hover_label:
                card_w, card_h = 100, 28
                cx0 = cx - card_w // 2
                cy0 = y - card_h - 8
                rr(d, (cx0, cy0, cx0 + card_w, cy0 + card_h), 12, fill=(14, 9, 29, 235), outline=ACCENT, width=1)
                f = font(12, bold=True)
                bbox = d.textbbox((0, 0), hover_label, font=f)
                tw = bbox[2] - bbox[0]
                d.text((cx - tw / 2, cy0 + 6), hover_label, font=f, fill=TEXT)
        else:
            symbol(d, kind, cx, cyi, r)
    return x, y, w, h


KINDS = ["term", "files", "web", "notes", "chat"]


def desktop():
    im = new(1280, 720)
    d = ImageDraw.Draw(im)
    wx, wy, ww, wh = 150, 80, 980, 500
    rr(d, (wx, wy, wx + ww, wy + wh), 12, fill=WIN, outline=(40, 24, 40), width=1)
    title_strip_pill(im, wx + 8, wy + 8, ww - 16, 40, "Terminal")
    d = ImageDraw.Draw(im)
    d.text((wx + 36, wy + 68), "$  ohmtabs status", font=font(18), fill=TEXT)
    pill_dock(im, 655, KINDS, hover_i=4, hover_label="Chat")
    d = ImageDraw.Draw(im)
    d.text((24, 692), "Diagram — not a live desktop", font=font(12), fill=MUTED)
    return im.convert("RGB")


def strip_only():
    im = new(1240, 56, BG)
    title_strip_pill(im, 8, 8, 1224, 40, "App window")
    return im.convert("RGB")


def taskbar_only():
    im = new(720, 96, BG)
    pill_dock(im, 48, KINDS)
    return im.convert("RGB")


def hover_card():
    im = new(720, 150, BG)
    pill_dock(im, 100, ["term", "files", "web", "chat"], hover_i=3, hover_label="Chat")
    return im.convert("RGB")


def alttab():
    im = new(920, 280, BG)
    d = ImageDraw.Draw(im)
    cards = [
        ("Terminal", "term", True),
        ("Files", "files", False),
        ("Browser", "web", False),
        ("Notes", "notes", False),
    ]
    n = len(cards)
    cw, ch, gap = 180, 156, 18
    total = n * cw + (n - 1) * gap
    x0 = (im.width - total) // 2
    y0 = 52
    d.text((im.width // 2 - 40, 16), "Alt+Tab", font=font(16, bold=True), fill=MUTED)
    for i, (name, kind, on) in enumerate(cards):
        x = x0 + i * (cw + gap)
        fill = (28, 16, 28, 240) if on else (18, 12, 28, 220)
        outline = ACCENT if on else (70, 40, 50)
        rr(d, (x, y0, x + cw, y0 + ch), 18, fill=fill, outline=outline, width=2 if on else 1)
        symbol(d, kind, x + cw // 2, y0 + 58, 28)
        f = font(14, bold=True)
        bbox = d.textbbox((0, 0), name, font=f)
        tw = bbox[2] - bbox[0]
        d.text((x + (cw - tw) / 2, y0 + 112), name, font=f, fill=TEXT if on else MUTED)
    return im.convert("RGB")


def settings_card():
    W, H = 420, 640
    im = new(W, H, BG)
    d = ImageDraw.Draw(im)
    rr(d, (8, 8, W - 8, H - 8), 18, fill=(16, 12, 28), outline=ACCENT, width=2)
    d.text((28, 24), "Dock Settings", font=font(18, bold=True), fill=TEXT)
    d.text((W - 44, 24), "✕", font=font(16), fill=TEXT)
    rows = [
        ("Icon size", "38 px", None),
        ("Auto-hide", None, False),
        ("Position", "Bottom", None),
        ("Full length", None, False),
        ("Corner shape", "Pill", None),
        ("Icon magnify", None, True),
        ("Running apps", None, True),
        ("Workspaces", None, False),
        ("Active window", None, False),
        ("Status chips", None, False),
        ("Icon name on hover", None, True),
        ("Notification badge", None, True),
        ("Omarchy bar controls", None, False),
    ]
    y = 70
    for title, value, on in rows:
        d.text((28, y), title, font=font(14, bold=True), fill=TEXT)
        if value:
            vb = d.textbbox((0, 0), value, font=font(12))
            d.text((W - 28 - (vb[2] - vb[0]), y + 2), value, font=font(12), fill=TEXT)
        elif on is not None:
            tw, th = 42, 22
            tx, ty = W - 28 - tw, y
            fill = ACCENT if on else (50, 36, 48)
            rr(d, (tx, ty, tx + tw, ty + th), 11, fill=fill)
            kx = tx + tw - 12 if on else tx + 12
            d.ellipse((kx - 8, ty + 3, kx + 8, ty + 19), fill=INK if on else GLYPH)
        y += 40
    return im.convert("RGB")


def preview():
    im = new(1280, 800, BG)
    d = ImageDraw.Draw(im)
    d.text((48, 32), "OhmTabs", font=font(28, bold=True), fill=TEXT)
    d.text((48, 72), "Glass title strips · pill taskbar · Super Menu · Alt+Tab", font=font(16), fill=MUTED)
    wx, wy, ww, wh = 80, 120, 1120, 510
    rr(d, (wx, wy, wx + ww, wy + wh), 12, fill=WIN, outline=(40, 24, 40), width=1)
    title_strip_pill(im, wx + 10, wy + 8, ww - 20, 40, "Terminal")
    d = ImageDraw.Draw(im)
    d.text((wx + 36, wy + 72), "$ ohmtabs status", font=font(18), fill=TEXT)
    cards = [("Term", "term", True), ("Files", "files", False), ("Web", "web", False)]
    cx0, cy0 = wx + 280, wy + 210
    for i, (name, kind, on) in enumerate(cards):
        x = cx0 + i * 180
        rr(
            d,
            (x, cy0, x + 150, cy0 + 130),
            16,
            fill=(28, 16, 28) if on else (18, 12, 28),
            outline=ACCENT if on else (70, 40, 50),
            width=2 if on else 1,
        )
        symbol(d, kind, x + 75, cy0 + 50, 22)
        f = font(13, bold=True)
        bbox = d.textbbox((0, 0), name, font=f)
        d.text((x + 75 - (bbox[2] - bbox[0]) / 2, cy0 + 92), name, font=f, fill=TEXT)
    pill_dock(im, 730, KINDS, hover_i=0, hover_label="Terminal")
    d = ImageDraw.Draw(im)
    d.text((48, 770), "Diagram — not a live desktop", font=font(12), fill=MUTED)
    return im.convert("RGB")


def flip_digit(d, x, y, ch, w=16, h=22):
    rr(d, (x, y, x + w, y + h), 3, fill=(22, 18, 16), outline=(74, 64, 52), width=1)
    f = font(14, bold=True)
    bbox = d.textbbox((0, 0), ch, font=f)
    d.text((x + (w - (bbox[2] - bbox[0])) / 2, y + 2), ch, font=f, fill=(244, 228, 184))
    d.line((x, y + h // 2, x + w, y + h // 2), fill=(0, 0, 0), width=1)


def supermenu():
    W, H = 1100, 640
    im = new(W, H, (0, 0, 0))
    d = ImageDraw.Draw(im)
    rain = (0, 255, 65)
    # Sparse matrix rain — geometric, not copied terminal art.
    for x in range(18, W - 18, 14):
        for y in range(40, H - 50, 18):
            if (x * 3 + y * 7) % 11 == 0:
                d.point((x, y), fill=rain)
            if (x + y) % 17 == 0:
                d.rectangle((x, y, x + 1, y + 8), fill=(0, 140, 40))
    rr(d, (1, 1, W - 2, H - 2), 18, outline=ACCENT, width=2)
    d.text((24, 16), "Start", font=font(16, bold=True), fill=TEXT)
    d.text((W - 70, 14), "⚙   ✕", font=font(16), fill=TEXT)
    rr(d, (20, 48, W - 20, 84), 18, fill=(20, 16, 32, 180), outline=(60, 50, 70), width=1)
    d.text((36, 56), "Search apps...", font=font(14), fill=MUTED)

    col_y, col_h = 100, 470
    # All
    rr(d, (20, col_y, 300, col_y + col_h), 14, fill=(12, 10, 22, 200))
    d.text((36, col_y + 12), "All", font=font(13, bold=True), fill=TEXT)
    apps = [("A", "Editor"), ("A", "Files"), ("B", "Browser"), ("T", "Terminal")]
    yy = col_y + 44
    for letter, name in apps:
        d.text((36, yy), letter, font=font(11, bold=True), fill=MUTED)
        d.text((58, yy), name, font=font(13), fill=TEXT)
        yy += 36

    # Pinned
    rr(d, (316, col_y, 760, col_y + col_h), 14, fill=(12, 10, 22, 160))
    d.text((332, col_y + 12), "Pinned", font=font(13, bold=True), fill=TEXT)
    pins = [("term", "Terminal"), ("files", "Files"), ("web", "Browser"), ("chat", "Chat")]
    for i, (kind, name) in enumerate(pins):
        px = 350 + (i % 4) * 100
        py = col_y + 70
        symbol(d, kind, px + 30, py + 20, 18)
        f = font(11)
        bbox = d.textbbox((0, 0), name, font=f)
        d.text((px + 30 - (bbox[2] - bbox[0]) / 2, py + 48), name, font=f, fill=TEXT)

    # Widgets
    rr(d, (776, col_y, W - 20, col_y + col_h), 14, fill=(12, 10, 22, 200))
    d.text((792, col_y + 12), "Clocks", font=font(12, bold=True), fill=TEXT)
    d.text((792, col_y + 32), "Local   05/10/26", font=font(10), fill=MUTED)
    for i, ch in enumerate("2304"):
        ox = 792 + i * 20 + (8 if i >= 2 else 0)
        if i == 2:
            d.text((792 + 40, col_y + 52), ":", font=font(16, bold=True), fill=(230, 211, 163))
        flip_digit(d, ox, col_y + 50, ch)
    d.text((792, col_y + 86), "October 2026", font=font(11, bold=True), fill=TEXT)
    headers = "M T W T F S S".split()
    for i, h in enumerate(headers):
        d.text((796 + i * 28, col_y + 108), h, font=font(9), fill=MUTED)
    # tiny month cells
    for day in range(1, 32):
        c = (day + 2) % 7
        r = (day + 2) // 7
        x = 792 + c * 28
        y = col_y + 126 + r * 18
        if day == 5:
            rr(d, (x, y, x + 22, y + 16), 4, fill=ACCENT)
        d.text((x + 6, y), str(day), font=font(9), fill=TEXT)
    d.text((792, col_y + 250), "Recommended", font=font(12, bold=True), fill=TEXT)
    d.text((792, col_y + 274), "notes.txt", font=font(12), fill=TEXT)
    d.text((792, col_y + 292), "2 hours ago", font=font(10), fill=MUTED)

    d.text((28, H - 36), "user", font=font(12), fill=TEXT)
    d.text((W - 48, H - 38), "⏻", font=font(16), fill=TEXT)
    d.text((20, H - 18), "Diagram — not a live desktop", font=font(11), fill=MUTED)
    return im.convert("RGB")


def supermenu_settings():
    W, H = 420, 640
    im = new(W, H, BG)
    d = ImageDraw.Draw(im)
    rr(d, (8, 8, W - 8, H - 8), 18, fill=(16, 12, 28), outline=ACCENT, width=2)
    d.text((28, 24), "Super Menu", font=font(18, bold=True), fill=TEXT)
    d.text((W - 44, 24), "✕", font=font(16), fill=TEXT)
    rows = [
        ("Recommended files", True),
        ("Calendar", True),
        ("Weather", True),
        ("World clock", True),
        ("Crypto prices", False),
        ("RSS", False),
        ("News", False),
        ("Alerts", False),
        ("Flip clock", True),
    ]
    y = 70
    for title, on in rows:
        d.text((28, y), title, font=font(14, bold=True), fill=TEXT)
        tw, th = 42, 22
        tx, ty = W - 28 - tw, y
        fill = ACCENT if on else (50, 36, 48)
        rr(d, (tx, ty, tx + tw, ty + th), 11, fill=fill)
        kx = tx + tw - 12 if on else tx + 12
        d.ellipse((kx - 8, ty + 3, kx + 8, ty + 19), fill=INK if on else GLYPH)
        y += 44
    d.text((28, y + 4), "24 hour    DDMMYY", font=font(12), fill=MUTED)
    d.text((28, y + 28), "Zones: Local", font=font(12), fill=MUTED)
    return im.convert("RGB")


def save_rgb(im, path, size=None):
    if size:
        im = im.resize(size, Image.Resampling.LANCZOS)
    im = im.convert("RGB")
    im.save(path, "PNG", optimize=True)
    print("wrote", path, im.size)


def main():
    print("live grim files are the gallery; not overwriting docs/screenshots")


if __name__ == "__main__":
    main()
