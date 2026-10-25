"""从参考图生成 iOS 图标：
1. 取最大连通块（角色），把对话框/手指/文字/饭碗等其它元素刷白
2. 从边缘洪水填充得到背景，生成 alpha
3. 放到渐变底上，居中缩放到 1024，输出无 alpha 的 PNG
"""
import os
import sys
from collections import deque

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "..", ".ci-tools", "ref.webp")
OUT_DIR = os.path.join(HERE, "..", "..", ".ci-tools")

WHITE_BG = (11, 26, 74)
GRAD_TOP = (24, 46, 122)
GRAD_MID = (34, 122, 190)
GRAD_BOT = (110, 226, 240)


def label_components(mask: np.ndarray, seed=None):
    """返回 (labels, sizes, seed_label)"""
    h, w = mask.shape
    labels = np.zeros((h, w), np.int32)
    sizes = [0]
    current = 0
    seed_label = 0
    for y in range(h):
        row = mask[y]
        for x in range(w):
            if not row[x] or labels[y, x]:
                continue
            current += 1
            count = 0
            q = deque([(y, x)])
            labels[y, x] = current
            hit_seed = False
            while q:
                cy, cx = q.popleft()
                count += 1
                if seed is not None and abs(cy - seed[0]) <= 1 and abs(cx - seed[1]) <= 1:
                    hit_seed = True
                for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not labels[ny, nx]:
                        labels[ny, nx] = current
                        q.append((ny, nx))
            sizes.append(count)
            if hit_seed:
                seed_label = current
    return labels, sizes, seed_label


def flood_from_border(white: np.ndarray):
    """从图像边缘把连通的白色标记为背景"""
    h, w = white.shape
    bg = np.zeros((h, w), bool)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if white[y, x] and not bg[y, x]:
                bg[y, x] = True
                q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if white[y, x] and not bg[y, x]:
                bg[y, x] = True
                q.append((y, x))
    while q:
        cy, cx = q.popleft()
        for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
            if 0 <= ny < h and 0 <= nx < w and white[ny, nx] and not bg[ny, nx]:
                bg[ny, nx] = True
                q.append((ny, nx))
    return bg


def gradient_background(size=1024):
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        t = y / (size - 1)
        if t < 0.5:
            k = t / 0.5
            c = tuple(int(GRAD_TOP[i] + (GRAD_MID[i] - GRAD_TOP[i]) * k) for i in range(3))
        else:
            k = (t - 0.5) / 0.5
            c = tuple(int(GRAD_MID[i] + (GRAD_BOT[i] - GRAD_MID[i]) * k) for i in range(3))
        for x in range(size):
            px[x, y] = c
    return img


def main():
    img = Image.open(SRC).convert("RGB")
    arr = np.array(img).astype(np.int16)
    h, w = arr.shape[:2]
    print("源图:", w, "x", h)

    nonwhite = (arr.min(axis=2) < 246)
    labels, sizes, seed_label = label_components(nonwhite, seed=(330, 530))
    print("连通块数量:", len(sizes) - 1, " 角色块大小:", sizes[seed_label])
    if not seed_label:
        raise SystemExit("没有找到角色所在的连通块")

    char = (labels == seed_label)
    # 其余元素刷白
    cleaned = arr.copy()
    cleaned[nonwhite & ~char] = 254
    cleaned_img = Image.fromarray(cleaned.astype(np.uint8))

    # 背景 = 与边缘连通的白色
    white = (cleaned.min(axis=2) >= 246)
    bg = flood_from_border(white)
    alpha = np.where(bg, 0, 255).astype(np.uint8)

    # 轻微收缩 1px，减少白边
    alpha_img = Image.fromarray(alpha, "L").filter(ImageFilter.MinFilter(3))
    alpha_img = alpha_img.filter(ImageFilter.GaussianBlur(0.8))
    rgba = cleaned_img.convert("RGBA")
    rgba.putalpha(alpha_img)

    # 按角色裁剪
    ys, xs = np.where(char)
    pad = 6
    x0, x1 = max(0, xs.min() - pad), min(w, xs.max() + pad)
    y0, y1 = max(0, ys.min() - pad), min(h, ys.max() + pad)
    print("裁剪区域:", (x0, y0, x1, y1), "尺寸", (x1 - x0, y1 - y0))
    sprite = rgba.crop((x0, y0, x1, y1))

    size = 1024
    bg_img = gradient_background(size)

    # 角色高度占画布 ~86%
    target_h = int(size * 0.86)
    scale = target_h / sprite.height
    new_w = max(1, int(round(sprite.width * scale)))
    sprite = sprite.resize((new_w, target_h), Image.LANCZOS)

    # 落地阴影
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    cx = size // 2
    sd.ellipse([cx - new_w * 0.34, size - 118, cx + new_w * 0.34, size - 46], fill=(6, 28, 62, 90))
    shadow = shadow.filter(ImageFilter.GaussianBlur(28))
    bg_img = Image.alpha_composite(bg_img.convert("RGBA"), shadow)

    pos = (cx - new_w // 2, (size - target_h) // 2 + 18)
    if pos[0] < 0:
        pos = (0, pos[1])

    canvas = Image.alpha_composite(gradient_background(size).convert("RGBA"), shadow)
    canvas.paste(sprite, pos, sprite)

    canvas.convert("RGB").save(os.path.join(OUT_DIR, "icon-ref-1024.png"), "PNG")
    print("已输出 icon-ref-1024.png")

    # 尺寸预览
    for s in (180, 120, 87, 60, 40, 29):
        canvas.convert("RGB").resize((s, s), Image.LANCZOS).save(os.path.join(OUT_DIR, "icon-ref-%d.png" % s))
    print("已输出小尺寸预览")

    # 裁切预览（凑一张对比图）
    sheet = Image.new("RGB", (60 + 120 + 87 + 60 + 40 + 29 + 6 * 14, 190), (16, 24, 32))
    x = 20
    for s in (120, 87, 60, 40, 29):
        im = canvas.convert("RGB").resize((s, s), Image.LANCZOS)
        sheet.paste(im, (x, 30))
        x += s + 14
    sheet.save(os.path.join(OUT_DIR, "icon-ref-sizes.png"))


if __name__ == "__main__":
    main()
