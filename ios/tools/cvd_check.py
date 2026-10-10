#!/usr/bin/env python3
"""人物配色的色弱检查：Machado 2009（严重度 1.0）模拟红 / 绿 / 蓝色盲，算两两 CIEDE2000 色差，
再算每个颜色对浅色、深色地面的对比度。改 Palette.people 时跑一次：python3 ios/tools/cvd_check.py
颜色要和 ios/StreetWalk/Domain/Models.swift 的 Palette.people 一致。"""
import math, itertools, sys

PEOPLE = [  # 名字, 十六进制（顺序同 Palette.people）
    ("青綠", "#52ADA3"), ("淺紫", "#9F84F9"), ("藍", "#3E77AD"), ("紫紅", "#B22C7E"),
    ("黃", "#E49800"), ("灰", "#857A73"), ("橙（我）", "#D85A30"),
]
GROUNDS = {"浅色地面": "#F7F7F9", "深色地面": "#2F2F33"}

MACHADO = {
    "红色盲": [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]],
    "绿色盲": [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]],
    "蓝色盲": [[1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602], [0.004733, 0.691367, 0.303900]],
}

def hex2rgb(h): h = h.lstrip("#"); return [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
def lin(c): return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
def gam(c): c = min(1, max(0, c)); return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055

def simulate(rgb, kind):
    if kind == "正常": return rgb
    m = MACHADO[kind]; l = [lin(c) for c in rgb]
    return [gam(sum(m[i][j] * l[j] for j in range(3))) for i in range(3)]

def lab(rgb):
    r, g, b = (lin(c) for c in rgb)
    x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
    y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
    f = lambda t: t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116
    fx, fy, fz = f(x), f(y), f(z)
    return 116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)

def de2000(l1, l2):
    L1, a1, b1 = l1; L2, a2, b2 = l2
    C1, C2 = math.hypot(a1, b1), math.hypot(a2, b2); Cb = (C1 + C2) / 2
    G = 0.5 * (1 - math.sqrt(Cb ** 7 / (Cb ** 7 + 25 ** 7)))
    a1p, a2p = (1 + G) * a1, (1 + G) * a2
    C1p, C2p = math.hypot(a1p, b1), math.hypot(a2p, b2)
    h1p = math.degrees(math.atan2(b1, a1p)) % 360; h2p = math.degrees(math.atan2(b2, a2p)) % 360
    dL, dC = L2 - L1, C2p - C1p
    dh = 0 if C1p * C2p == 0 else (h2p - h1p if abs(h2p - h1p) <= 180 else h2p - h1p - 360 if h2p > h1p else h2p - h1p + 360)
    dH = 2 * math.sqrt(C1p * C2p) * math.sin(math.radians(dh / 2))
    Lb, Cbp = (L1 + L2) / 2, (C1p + C2p) / 2
    hb = h1p + h2p if C1p * C2p == 0 else ((h1p + h2p) / 2 if abs(h1p - h2p) <= 180 else (h1p + h2p + 360) / 2 if h1p + h2p < 360 else (h1p + h2p - 360) / 2)
    T = 1 - 0.17 * math.cos(math.radians(hb - 30)) + 0.24 * math.cos(math.radians(2 * hb)) + 0.32 * math.cos(math.radians(3 * hb + 6)) - 0.2 * math.cos(math.radians(4 * hb - 63))
    Sl = 1 + 0.015 * (Lb - 50) ** 2 / math.sqrt(20 + (Lb - 50) ** 2); Sc = 1 + 0.045 * Cbp; Sh = 1 + 0.015 * Cbp * T
    Rt = -2 * math.sqrt(Cbp ** 7 / (Cbp ** 7 + 25 ** 7)) * math.sin(math.radians(60 * math.exp(-((hb - 275) / 25) ** 2)))
    return math.sqrt((dL / Sl) ** 2 + (dC / Sc) ** 2 + (dH / Sh) ** 2 + Rt * (dC / Sc) * (dH / Sh))

def lum(rgb): r, g, b = (lin(c) for c in rgb); return 0.2126 * r + 0.7152 * g + 0.0722 * b
def contrast(a, b): la, lb = sorted([lum(a), lum(b)], reverse=True); return (la + 0.05) / (lb + 0.05)

def report(people):
    worst = {}
    for kind in ["正常", "红色盲", "绿色盲", "蓝色盲"]:
        labs = [lab(simulate(hex2rgb(h), kind)) for _, h in people]
        pairs = sorted(((de2000(labs[i], labs[j]), people[i][0], people[j][0]) for i, j in itertools.combinations(range(len(people)), 2)))
        worst[kind] = pairs[0]
        print(f"{kind}: 最小 ΔE2000 = {pairs[0][0]:.1f}（{pairs[0][1]} 对 {pairs[0][2]}），次小 {pairs[1][0]:.1f}（{pairs[1][1]} 对 {pairs[1][2]}）")
    for gname, g in GROUNDS.items():
        cs = [(contrast(hex2rgb(h), hex2rgb(g)), n) for n, h in people]
        print(f"对{gname}的对比度：" + "  ".join(f"{n} {c:.2f}" for c, n in cs))
    return worst

if __name__ == "__main__":
    w = report(PEOPLE)
    # 门槛：色弱模拟下两两 ΔE ≥ 10（明显可分）
    sys.exit(0 if all(v[0] >= 10 for v in w.values()) else 1)
