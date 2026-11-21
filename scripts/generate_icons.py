"""Generates the My Life: Business Tycoon app icon artwork.

Outputs (committed):
  assets/icon/app_icon.png        1024x1024 full icon (iOS / legacy Android / web)
  assets/icon/app_icon_fg.png     1024x1024 transparent foreground (Android adaptive)
Re-run with: python3 scripts/generate_icons.py
"""
from PIL import Image, ImageDraw, ImageFont

SIZE = 1024
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
TOP = (108, 92, 231)     # #6C5CE7
BOTTOM = (0, 184, 148)   # #00B894


def gradient(size):
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            px[x, y] = tuple(int(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3))
    return img


def coin(draw, box_size, origin):
    """Draws a gold coin with a bold dollar sign, centered at origin."""
    cx, cy = origin
    r = box_size // 2
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 206, 84), outline=(255, 255, 255), width=28)
    inner = int(r * 0.78)
    draw.ellipse([cx - inner, cy - inner, cx + inner, cy + inner], outline=(230, 160, 40), width=18)
    font = ImageFont.truetype(FONT, int(r * 1.25))
    draw.text((cx, cy + 6), "$", font=font, fill=(255, 255, 255), anchor="mm",
              stroke_width=10, stroke_fill=(120, 80, 0))


def main():
    full = gradient(SIZE).convert("RGBA")
    d = ImageDraw.Draw(full)
    coin(d, 640, (SIZE // 2, SIZE // 2))
    full.save("assets/icon/app_icon.png")

    fg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    # Adaptive icons keep the glyph inside the central 66% safe zone.
    fg_draw = ImageDraw.Draw(fg)
    coin(fg_draw, 500, (SIZE // 2, SIZE // 2))
    fg.save("assets/icon/app_icon_fg.png")
    print("wrote assets/icon/app_icon.png and app_icon_fg.png")


if __name__ == "__main__":
    main()
