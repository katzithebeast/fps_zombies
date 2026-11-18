#!/usr/bin/env python3
"""Upeče masky pro realistický hazmat oblek (spouštět po tools/build_hazmat.gd).
Vstup: /tmp/hz_mesh_0.bin (godot --headless --script res://tools/export_hazmat_mesh.gd), textury v assets/hazmat.
Výstup:
  hazmat_wear.png   R špína (nohy, záhyby, šmouhy), G odřené hrany, B zaschlá krev, A zaschlé stopy vody
  hazmat_zones.png  R oblek, G guma (rukavice, boty, maska), B hledí
  hazmat_detail_n.png  jemná dlaždicová normála (struktura PVC fólie)
Šum se počítá v prostoru modelu, takže masky na švech UV navazují."""
import struct, numpy as np, os
from PIL import Image
from scipy import ndimage
R = 2048
ASSET = os.path.join(os.path.dirname(__file__), '..', 'assets', 'hazmat')
b = open('/tmp/hz_mesh_0.bin', 'rb').read()
nv, ni = struct.unpack('<II', b[:8])
V = np.frombuffer(b[8:8 + nv * 32], dtype='<f4').reshape(nv, 8)
I = np.frombuffer(b[8 + nv * 32:8 + nv * 32 + ni * 4], dtype='<u4').reshape(-1, 3)
P, UV, N = V[:, :3], V[:, 3:5], V[:, 5:8]
# --- rasterizace do UV: poloha a normála v každém texelu
pos = np.zeros((R, R, 3), np.float32); nor = np.zeros((R, R, 3), np.float32); mask = np.zeros((R, R), bool)
for tri in I:
    uv = UV[tri] * R - 0.5
    x0, y0 = np.floor(uv.min(0)).astype(int); x1, y1 = np.ceil(uv.max(0)).astype(int)
    x0, y0 = max(x0, 0), max(y0, 0); x1, y1 = min(x1, R - 1), min(y1, R - 1)
    if x1 < x0 or y1 < y0: continue
    xs, ys = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
    a, bb, c = uv
    den = (bb[1] - c[1]) * (a[0] - c[0]) + (c[0] - bb[0]) * (a[1] - c[1])
    if abs(den) < 1e-12: continue
    w0 = ((bb[1] - c[1]) * (xs - c[0]) + (c[0] - bb[0]) * (ys - c[1])) / den
    w1 = ((c[1] - a[1]) * (xs - c[0]) + (a[0] - c[0]) * (ys - c[1])) / den
    w2 = 1 - w0 - w1
    m = (w0 >= -0.02) & (w1 >= -0.02) & (w2 >= -0.02)
    if not m.any(): continue
    W = np.stack([w0[m], w1[m], w2[m]], 1)
    yy, xx = ys[m], xs[m]
    pos[yy, xx] = W @ P[tri]; nor[yy, xx] = W @ N[tri]; mask[yy, xx] = True
# dilatace přes švy UV
for _ in range(12):
    grown = ndimage.binary_dilation(mask) & ~mask
    if not grown.any(): break
    for arr in (pos, nor):
        for k in range(3):
            ch = arr[:, :, k]
            s = ndimage.uniform_filter(np.where(mask, ch, 0), 3); w = ndimage.uniform_filter(mask.astype(np.float32), 3)
            ch[grown] = (s / np.maximum(w, 1e-6))[grown]
    mask |= grown
nor /= np.maximum(np.linalg.norm(nor, axis=2, keepdims=True), 1e-6)
ymin, ymax = P[:, 1].min(), P[:, 1].max()
h = (pos[:, :, 1] - ymin) / (ymax - ymin)
rng = np.random.default_rng(11)
# --- 3D hodnotový šum (fbm) v prostoru modelu
G = 64
lat = rng.random((G, G, G)).astype(np.float32)
def vnoise(p):
    p = p % G
    i = np.floor(p).astype(int); f = p - i; f = f * f * (3 - 2 * f)
    out = 0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (f[..., 0] if dx else 1 - f[..., 0]) * (f[..., 1] if dy else 1 - f[..., 1]) * (f[..., 2] if dz else 1 - f[..., 2])
                out = out + w * lat[(i[..., 0] + dx) % G, (i[..., 1] + dy) % G, (i[..., 2] + dz) % G]
    return out
def fbm(p, oct=5):
    s, a, tot = 0, 0.5, 0
    for o in range(oct):
        s = s + a * vnoise(p * (2 ** o) + o * 17.3); tot += a; a *= 0.5
    return s / tot
def ss(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1); return t * t * (3 - 2 * t)
pp = pos * 1.0
n_lo = fbm(pp * 3.0 + 5.1, 4)
n_mid = fbm(pp * 9.0 + 1.7, 5)
n_hi = fbm(pp * 31.0, 3)
orm = np.asarray(Image.open(os.path.join(ASSET, 'hazmat_orm.png')).convert('RGB'), np.float32) / 255
cav = np.clip((1 - orm[:, :, 0]) * 1.8, 0, 1)
# --- špína: zespodu (bahno a usazeniny z bazénů), kolena, záhyby, šmouhy od rukou, prach shora
lower = ss(0.4, 0.03, h) * (0.35 + 0.65 * n_mid)
knees = ss(0.12, 0.0, np.abs(h - 0.29)) * ss(-0.1, 0.5, nor[:, :, 2]) * 0.45
smudge = ss(0.58, 0.75, n_lo) * 0.5 * (0.6 + 0.4 * n_hi)
dust = np.clip(nor[:, :, 1], 0, 1) * 0.25 * n_mid
dirt = np.clip(lower + knees + cav * (0.55 + 0.5 * n_mid) + smudge + dust - 0.08, 0, 1)
# --- odřené hrany (ohyby normálové mapy) a škrábance
nm = np.asarray(Image.open(os.path.join(ASSET, 'hazmat_normal.png')).convert('RGB'), np.float32) / 255 * 2 - 1
curv = np.abs(ndimage.sobel(nm[:, :, 0], 1)) + np.abs(ndimage.sobel(nm[:, :, 1], 0))
curv = np.clip(ndimage.gaussian_filter(curv, 1.2) * 0.35, 0, 1)
scratch = ss(0.82, 0.9, fbm(pp * np.array([90.0, 6.0, 90.0]), 2)) * 0.5
wear = np.clip(curv * (0.4 + 0.9 * n_hi) + scratch * ss(0.5, 0.1, h + 0.2 * n_lo), 0, 1)
# --- zaschlá krev: pár skvrn (předek, nohy, rukavice) a drobné kapky
blob = ss(0.67, 0.77, fbm(pp * 4.5 + 31.0, 4)) * ss(-0.2, 0.4, nor[:, :, 2])
drops = ss(0.8, 0.86, fbm(pp * 55.0 + 7.0, 2)) * ss(0.7, 0.2, h)
blood = np.clip((blob * 0.8 + drops * 0.7) * (0.5 + 0.5 * n_hi), 0, 1)
# --- zaschlé stopy vody: svislé stékance a čáry hladiny (příliv) na nohou
streak = ss(0.6, 0.72, fbm(pp * np.array([70.0, 2.5, 70.0]) + 3.0, 3)) * ss(0.55, 0.15, h)
tide = sum(ss(0.006, 0.0, np.abs(h - t + 0.01 * (n_lo - 0.5))) for t in (0.13, 0.19, 0.24)) * 0.6
water = np.clip(streak * 0.8 + tide, 0, 1)
wearimg = np.stack([dirt, wear, blood, water], 2)
Image.fromarray((wearimg * 255 + 0.5).astype(np.uint8), 'RGBA').save(os.path.join(ASSET, 'hazmat_wear.png'))
# --- zóny materiálu podle barvy
alb = np.asarray(Image.open(os.path.join(ASSET, 'hazmat_albedo.png')).convert('RGB'), np.float32) / 255
r, g, bl = alb[:, :, 0], alb[:, :, 1], alb[:, :, 2]
lum = 0.3 * r + 0.59 * g + 0.11 * bl
suit = ss(0.08, 0.2, bl - r)
visor = ss(0.15, 0.3, r - bl) * ss(0.3, 0.45, g)
rubber = np.clip(ss(0.32, 0.2, lum) * (1 - suit) * (1 - visor), 0, 1)
zones = np.stack([suit, rubber, visor], 2)
zones = ndimage.gaussian_filter(zones, (1.0, 1.0, 0))
Image.fromarray((zones * 255 + 0.5).astype(np.uint8), 'RGB').save(os.path.join(ASSET, 'hazmat_zones.png'))
# --- jemná dlaždicová normála: zmačkaná PVC fólie (šum filtrovaný ve frekvenci = dlaždicový)
T = 512
wn = rng.standard_normal((T, T))
fx = np.fft.fftfreq(T)[:, None]; fy = np.fft.fftfreq(T)[None, :]
fr = np.sqrt(fx ** 2 + fy ** 2) + 1e-6
def band(lo, hi, aniso=1.0):
    f = np.sqrt((fx * aniso) ** 2 + fy ** 2) + 1e-6
    return np.real(np.fft.ifft2(np.fft.fft2(wn) * np.exp(-((np.log(f) - np.log((lo + hi) / 2)) ** 2) / 0.5)))
crinkle = np.abs(band(0.01, 0.03))            # záhyby fólie (hřebeny)
crinkle = 1 - crinkle / crinkle.max()
grain = band(0.15, 0.35)
hgt = crinkle * 1.0 + grain / np.abs(grain).max() * 0.18
hgt = (hgt - hgt.min()) / (hgt.max() - hgt.min())
dx = (np.roll(hgt, -1, 1) - np.roll(hgt, 1, 1)) * 6
dy = (np.roll(hgt, -1, 0) - np.roll(hgt, 1, 0)) * 6
nn = np.stack([-dx, -dy, np.ones_like(dx)], 2); nn /= np.linalg.norm(nn, axis=2, keepdims=True)
Image.fromarray(((nn * 0.5 + 0.5) * 255 + 0.5).astype(np.uint8), 'RGB').save(os.path.join(ASSET, 'hazmat_detail_n.png'))
print('upečeno', R, 'texelů, pokryto', mask.mean().round(3))
