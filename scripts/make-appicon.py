"""生成 DeepChat iOS 应用图标（1024x1024，无圆角，交给 iOS 自动裁切）"""
import os
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "DeepChat", "Assets.xcassets", "AppIcon.appiconset")
SIZE = 1024


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient(size):
    c1 = (0x7C, 0x8F, 0xFF)   # 亮蓝紫
    c2 = (0x33, 0x4C, 0xE0)   # 深蓝
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = min(1.0, max(0.0, (x * 0.45 + y * 0.55) / size))
            px[x, y] = lerp(c1, c2, t)
    return img


def main():
    os.makedirs(OUT, exist_ok=True)
    img = gradient(SIZE).convert("RGBA")

    # 顶部柔光
    glow = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([-SIZE * 0.3, -SIZE * 0.85, SIZE * 1.3, SIZE * 0.35], fill=(255, 255, 255, 55))
    glow = glow.filter(ImageFilter.GaussianBlur(SIZE * 0.08))
    img = Image.alpha_composite(img, glow)

    d = ImageDraw.Draw(img)

    # 对话气泡
    bx0, by0, bx1, by1 = 214, 250, 810, 700
    radius = 150
    d.rounded_rectangle([bx0, by0, bx1, by1], radius=radius, fill=(255, 255, 255, 255))
    # 气泡尾巴
    d.polygon([(330, 676), (312, 800), (452, 682)], fill=(255, 255, 255, 255))

    # 三个点
    dot_y = (by0 + by1) / 2
    for i, cx in enumerate((392, 512, 632)):
        r = 40 if i != 1 else 46
        d.ellipse([cx - r, dot_y - r, cx + r, dot_y + r], fill=(0x4D, 0x6B, 0xFE, 255))

    img.convert("RGB").save(os.path.join(OUT, "AppIcon-1024.png"), quality=95)
    print("icon ->", os.path.join(OUT, "AppIcon-1024.png"))


if __name__ == "__main__":
    main()
