"""Procedurální textury pro karanténní pokoj (Hladina). Vše tileable, kde to dává smysl."""
import numpy as np, math, random, os, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont
OUT = sys.argv[1] if len(sys.argv) > 1 else "."
rng = np.random.default_rng(7); random.seed(7)
N = 2048
FD = "/usr/share/fonts/truetype/dejavu/"

def spectral(n, beta, seed, lo=0.0):
    """Tileable fraktální šum (1/f^beta), normalizovaný 0..1."""
    r = np.random.default_rng(seed)
    f = np.fft.fftfreq(n)
    fx, fy = np.meshgrid(f, f)
    k = np.sqrt(fx**2 + fy**2); k[0, 0] = 1
    amp = 1.0 / k**beta
    if lo > 0: amp *= (k > lo / n)
    ph = np.exp(2j * np.pi * r.random((n, n)))
    a = np.real(np.fft.ifft2(amp * ph))
    a -= a.min(); a /= a.max()
    return a

def blur(a, s):
    if s <= 0: return a
    im = Image.fromarray((np.clip(a, 0, 1) * 65535).astype(np.uint16).astype(np.int32), mode="I")
    # wrap-around blur: dlaždice 3x3
    t = np.tile(a, (3, 3))
    im = Image.fromarray((np.clip(t, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(s))
    b = np.asarray(im, dtype=np.float32)[a.shape[0]:2*a.shape[0], a.shape[1]:2*a.shape[1]] / 255.0
    return b

def cracks(n, count, seed, length=(80, 400), width=1.6, branch=0.25):
    """Vlasové praskliny (náhodná procházka), kreslené s přesahem kvůli návaznosti."""
    r = random.Random(seed)
    im = Image.new("L", (n * 3, n * 3), 0); d = ImageDraw.Draw(im)
    def walk(x, y, ang, steps, w):
        pts = [(x, y)]
        for _ in range(steps):
            ang += r.gauss(0, 0.35)
            st = r.uniform(4, 10)
            x += math.cos(ang) * st; y += math.sin(ang) * st
            pts.append((x, y))
            if r.random() < branch * 0.04 and w > 0.8:
                walk(x, y, ang + r.choice([-1, 1]) * r.uniform(0.5, 1.1), steps // 3, w * 0.6)
        for ox in (0, n, 2 * n):
            for oy in (0, n, 2 * n):
                d.line([(p[0] + ox, p[1] + oy) for p in pts], fill=255, width=max(1, int(round(w))))
    for _ in range(count):
        walk(r.uniform(0, n), r.uniform(0, n), r.uniform(0, 6.28), r.randint(*length) // 6, width)
    a = np.asarray(im, dtype=np.float32)[n:2*n, n:2*n] / 255.0
    return a

def save_rgb(a, name, q=92):
    Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, name), quality=q)

def normal_from_height(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * strength
    n = np.stack([-dx, dy, np.ones_like(h)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5

def mix(c1, c2, t):
    t = t[..., None]
    return np.array(c1) * (1 - t) + np.array(c2) * t

# ---------------------------------------------------------------- 1) vápenná omítka (strop), 1,6 m
def plaster():
    big = spectral(N, 1.6, 1)
    mid = spectral(N, 1.1, 2)
    fine = spectral(N, 0.5, 3)
    base = mix((0.86, 0.85, 0.8), (0.74, 0.72, 0.66), np.clip(big * 1.4 - 0.25, 0, 1))
    base *= (0.94 + 0.1 * mid)[..., None]
    base *= (0.97 + 0.05 * fine)[..., None]
    # vodní mapy: zažloutlé skvrny s tmavším okrajem
    wm = spectral(N, 2.0, 4)
    stain = np.clip((wm - 0.62) * 6, 0, 1)
    edge = np.clip(1 - np.abs(wm - 0.62) * 40, 0, 1)
    base = mix(base, (0.72, 0.64, 0.48), stain * 0.12)
    base *= (1 - edge * 0.03)[..., None]
    cr = blur(cracks(N, 9, 5, width=1.4), 0.6)
    base *= (1 - cr * 0.55)[..., None]
    h = 0.55 * big + 0.3 * mid + 0.15 * fine - cr * 0.6
    save_rgb(base, "plaster_albedo.jpg")
    save_rgb(normal_from_height(blur(h, 1.0), 14.0), "plaster_normal.jpg")
    save_rgb(np.clip(0.88 - fine * 0.08 + cr * 0.05, 0, 1)[..., None].repeat(3, -1), "plaster_rough.jpg")

# ---------------------------------------------------------------- 2) olejový nátěr (stěny), 1,6 m
def oil_paint(name, c_hi, c_lo):
    big = spectral(N, 1.7, 11)
    # tahy štětce: protáhlý šum (svisle)
    r = np.random.default_rng(12)
    s = r.random((N // 64, N)).astype(np.float32)
    s = np.asarray(Image.fromarray((s * 255).astype(np.uint8)).resize((N, N), Image.BICUBIC), dtype=np.float32) / 255
    strokes = blur(s, 2.0)
    fine = spectral(N, 0.6, 13)
    base = mix(c_hi, c_lo, np.clip(big * 1.3 - 0.2, 0, 1))
    base *= (0.95 + 0.07 * strokes + 0.04 * fine)[..., None]
    # pár odloupnutých míst: pod nimi starší světlá vrstva / omítka
    chip_n = spectral(N, 1.3, 14)
    chips = np.clip((chip_n - 0.83) * 30, 0, 1)
    chips_edge = np.clip((chip_n - 0.80) * 30, 0, 1) - chips
    base = mix(base, (0.8, 0.78, 0.72), chips)
    base *= (1 - np.clip(chips_edge, 0, 1) * 0.25)[..., None]
    cr = blur(cracks(N, 5, 15, width=1.2), 0.6)
    base *= (1 - cr * 0.35)[..., None]
    h = 0.3 * big + 0.25 * strokes + 0.1 * fine + 0.5 * (1 - chips) - cr * 0.4
    save_rgb(base, f"{name}_albedo.jpg")
    save_rgb(normal_from_height(blur(h, 0.8), 10.0), f"{name}_normal.jpg")
    rough = 0.55 + 0.15 * big - 0.05 * strokes + chips * 0.35
    save_rgb(np.clip(rough, 0, 1)[..., None].repeat(3, -1), f"{name}_rough.jpg")

# ---------------------------------------------------------------- 3) velká špína na rozbití opakování (decal)
def grunge():
    n = 2048
    a = spectral(n, 1.9, 21) * 0.6 + spectral(n, 1.2, 22) * 0.4
    m = np.clip((a - 0.45) * 2.2, 0, 1) ** 1.6
    # svislé stékance
    r = np.random.default_rng(23)
    s = r.random((n, n // 48)).astype(np.float32)
    s = np.asarray(Image.fromarray((s * 255).astype(np.uint8)).resize((n, n), Image.BICUBIC), dtype=np.float32) / 255
    streak = np.clip((blur(s, 3) - 0.55) * 3, 0, 1) * np.linspace(1.0, 0.2, n)[:, None]
    m = np.clip(m + streak * 0.5 * spectral(n, 1.5, 24), 0, 1)
    # okraje průhledné (decal)
    yy, xx = np.mgrid[0:n, 0:n] / n
    fade = np.clip(np.minimum(np.minimum(xx, 1 - xx), np.minimum(yy, 1 - yy)) * 6, 0, 1)
    al = m * fade * 0.75
    rgb = mix((0.32, 0.28, 0.2), (0.18, 0.16, 0.12), spectral(n, 1.0, 25))
    img = np.dstack([rgb, al[..., None]])
    Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "grunge_wall.png"))

# ---------------------------------------------------------------- 4) špína u podlahy (pruh) a v rohu
def floor_strip():
    w, h = 2048, 256
    n = spectral(2048, 1.3, 31)[:h, :]
    y = np.linspace(0, 1, h)[:, None]           # 0 nahoře, 1 u podlahy
    grad = np.clip((y - 0.15) / 0.85, 0, 1) ** 1.4
    m = grad * (0.55 + 0.45 * n)
    # odrazy mopu: tmavší pás úplně dole a nepravidelná horní hrana
    m += np.clip((y - 0.88) * 8, 0, 1) * 0.3
    x = np.linspace(0, 1, w)[None, :]
    side = np.clip(np.minimum(x, 1 - x) * 12, 0, 1)
    al = np.clip(m, 0, 1) * side * 0.85
    rgb = mix((0.3, 0.26, 0.2), (0.16, 0.14, 0.11), n)
    Image.fromarray((np.dstack([rgb, al[..., None]]) * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "dirt_floor_strip.png"))
    # roh: svislý pruh tmavší u stropu i u podlahy
    w2, h2 = 256, 1024
    n2 = spectral(1024, 1.3, 32)[:, :w2]
    xx = np.linspace(-1, 1, w2)[None, :]
    yy = np.linspace(0, 1, h2)[:, None]
    m2 = np.clip(1 - np.abs(xx) * 1.2, 0, 1) ** 1.5 * (0.35 + 0.65 * (np.clip(1 - yy * 4, 0, 1) + np.clip((yy - 0.8) * 5, 0, 1)) + 0.25)
    al2 = np.clip(m2 * (0.6 + 0.4 * n2), 0, 1) * 0.8
    rgb2 = mix((0.26, 0.23, 0.18), (0.12, 0.11, 0.09), n2)
    Image.fromarray((np.dstack([rgb2, al2[..., None]]) * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "dirt_corner.png"))

# ---------------------------------------------------------------- 5) špinavé sklo
def dirty_glass():
    n = 1024
    a = spectral(n, 1.4, 41)
    yy, xx = np.mgrid[0:n, 0:n] / n
    corner = np.clip(1 - np.minimum(np.minimum(xx, 1 - xx), np.minimum(yy, 1 - yy)) * 7, 0, 1) ** 2
    dust = np.clip(a * 0.35 + corner * 0.5, 0, 1)
    # zaschlé kapky deště: stékance s kapkou na konci
    im = Image.new("L", (n, n), 0); d = ImageDraw.Draw(im); r = random.Random(42)
    for _ in range(140):
        x = r.uniform(0, n); y = r.uniform(0, n * 0.9); L = r.uniform(20, 160)
        pts = [(x + math.sin(i * 0.15) * r.uniform(0, 2), y + i * L / 20) for i in range(21)]
        d.line(pts, fill=r.randint(60, 150), width=r.randint(1, 3))
        ex, ey = pts[-1]; rr = r.uniform(2, 5)
        d.ellipse([ex - rr, ey - rr, ex + rr, ey + rr], outline=r.randint(90, 180), width=1)
    drops = np.asarray(im.filter(ImageFilter.GaussianBlur(0.8)), dtype=np.float32) / 255
    # šmouhy od hadru (oblouky)
    im2 = Image.new("L", (n, n), 0); d2 = ImageDraw.Draw(im2)
    for _ in range(10):
        cx, cy, rad = r.uniform(0, n), r.uniform(0, n), r.uniform(80, 300)
        d2.arc([cx - rad, cy - rad, cx + rad, cy + rad], r.uniform(0, 360), r.uniform(0, 360), fill=70, width=r.randint(10, 30))
    smear = np.asarray(im2.filter(ImageFilter.GaussianBlur(6)), dtype=np.float32) / 255
    al = np.clip(0.05 + dust * 0.5 + drops * 0.35 + smear * 0.3, 0, 0.85)
    rgb = mix((0.78, 0.76, 0.7), (0.55, 0.52, 0.45), a)
    Image.fromarray((np.dstack([rgb, al[..., None]]) * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "glass_dirty.png"))

# ---------------------------------------------------------------- 6) drátosklo (dveře), 0,5 m
def wired_glass():
    n = 1024
    im = Image.new("L", (n, n), 0); d = ImageDraw.Draw(im)
    step = n // 8            # kosočtverce ~6 cm
    for k in range(-16, 17):
        for ox in (-n, 0, n):
            d.line([(k * step + ox, 0), (k * step + n + ox, n)], fill=255, width=3)
            d.line([(k * step + ox, n), (k * step + n + ox, 0)], fill=255, width=3)
    wire = np.asarray(im.filter(ImageFilter.GaussianBlur(0.7)), dtype=np.float32) / 255
    frost = spectral(n, 0.9, 51)
    al = np.clip(0.55 + frost * 0.15 + wire * 0.35, 0, 1)
    rgb = mix((0.82, 0.85, 0.82), (0.7, 0.74, 0.7), frost)
    rgb = mix(rgb, (0.25, 0.25, 0.24), wire)
    Image.fromarray((np.dstack([rgb, al[..., None]]) * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "glass_wired.png"))

# ---------------------------------------------------------------- 8) deka a matrace
def blanket():
    n = 1024
    yy, xx = np.mgrid[0:n, 0:n]
    weave = (np.sin(xx * 2 * np.pi / 6) * np.sin(yy * 2 * np.pi / 6)) * 0.5 + 0.5
    fuzz = spectral(n, 0.4, 61)
    pill = spectral(n, 1.0, 62)
    base = mix((0.36, 0.4, 0.45), (0.27, 0.3, 0.34), pill)
    # dva tmavé pruhy přes deku (erární deka)
    band = ((yy % n > n * 0.12) & (yy % n < n * 0.16)) | ((yy % n > n * 0.19) & (yy % n < n * 0.21))
    base = mix(base, (0.16, 0.18, 0.22), band.astype(np.float32) * 0.85)
    base *= (0.88 + 0.12 * weave * 0.5 + 0.12 * fuzz)[..., None]
    save_rgb(base, "blanket_albedo.jpg")
    save_rgb(normal_from_height(blur(weave * 0.6 + fuzz * 0.4, 0.5), 3.0), "blanket_normal.jpg")
    # matrace: modrobílý proužek
    m = ((xx // 22) % 3 == 0).astype(np.float32)
    m = blur(m, 0.8)
    mt = mix((0.86, 0.85, 0.8), (0.32, 0.4, 0.55), m * 0.85)
    st = spectral(n, 1.6, 63)
    mt = mix(mt, (0.62, 0.55, 0.4), np.clip((st - 0.65) * 3, 0, 1) * 0.5)   # skvrny
    mt *= (0.92 + 0.08 * weave)[..., None]
    save_rgb(mt, "mattress_albedo.jpg")

# ---------------------------------------------------------------- 9) zrcadlo se slepými okraji
def mirror():
    w, h = 512, 640
    yy, xx = np.mgrid[0:h, 0:w]
    ex = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy)).astype(np.float32)
    n = spectral(1024, 1.3, 71)[:h, :w]
    desilver = np.clip((n * 60 + 30 - ex) / 25, 0, 1)
    spots = np.clip((spectral(1024, 0.8, 72)[:h, :w] - 0.83) * 20, 0, 1)
    dark = np.clip(desilver * 0.8 + spots * 0.6, 0, 1)
    rgb = mix((0.93, 0.93, 0.9), (0.2, 0.18, 0.14), dark)
    save_rgb(rgb, "mirror_albedo.jpg")
    rough = 0.05 + dark * 0.6 + spectral(1024, 1.0, 73)[:h, :w] * 0.05
    save_rgb(np.clip(rough, 0, 1)[..., None].repeat(3, -1), "mirror_rough.jpg")

# ---------------------------------------------------------------- 10) papíry: cedulka, kalendář, plakát, poznámky, mapka
def paper_base(w, h, seed, tint=(0.93, 0.9, 0.8)):
    n = spectral(1024, 1.2, seed)
    n = np.asarray(Image.fromarray((n * 255).astype(np.uint8)).resize((w, h)), dtype=np.float32) / 255
    rgb = mix(tint, (0.78, 0.72, 0.58), np.clip(n * 1.2 - 0.3, 0, 1) * 0.6)
    yy, xx = np.mgrid[0:h, 0:w]
    ex = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy)) / min(w, h)
    rgb *= (1 - np.clip(0.08 - ex, 0, 1) * 3)[..., None]
    return Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8))

def age(img, seed):
    """Zažloutnutí, skvrny, ohyb."""
    a = np.asarray(img, dtype=np.float32) / 255
    h, w = a.shape[:2]
    n = spectral(1024, 1.8, seed)
    n = np.asarray(Image.fromarray((n * 255).astype(np.uint8)).resize((w, h)), dtype=np.float32) / 255
    stain = np.clip((n - 0.7) * 4, 0, 1)
    a = a * (1 - stain[..., None] * 0.25) + np.array((0.6, 0.5, 0.3)) * stain[..., None] * 0.12
    fold = np.abs(np.linspace(-1, 1, h))[:, None] < 0.004
    a *= (1 - fold[..., None] * 0.15)
    return Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))

def font(sz, bold=False, mono=False, serif=False):
    f = "DejaVuSansMono" if mono else ("DejaVuSerif" if serif else "DejaVuSans")
    if bold: f += "-Bold"
    return ImageFont.truetype(FD + f + ".ttf", sz)

def papers():
    # cedulka na dveře
    w, h = 900, 300
    im = Image.new("RGB", (w, h), (232, 228, 214)); d = ImageDraw.Draw(im)
    d.rectangle([10, 10, w - 10, h - 10], outline=(40, 40, 40), width=8)
    d.rectangle([10, 10, w - 10, 95], fill=(160, 32, 28))
    d.text((w // 2, 52), "KARANTÉNA", font=font(62, True), fill=(245, 240, 230), anchor="mm")
    d.text((w // 2, 160), "POKOJ č. 7", font=font(70, True), fill=(30, 30, 30), anchor="mm")
    d.text((w // 2, 240), "Vstup jen v ochranném oděvu · Biologické riziko", font=font(28), fill=(60, 60, 60), anchor="mm")
    age(im, 81).save(os.path.join(OUT, "sign_quarantine.jpg"), quality=92)
    # kalendář 1993
    w, h = 700, 1000
    im = paper_base(w, h, 82); d = ImageDraw.Draw(im)
    d.rectangle([0, 0, w, 420], fill=(70, 96, 120))
    for i in range(7):   # „fotka“ krajiny: kopce
        y0 = 250 + i * 22
        d.polygon([(0, 420), (0, y0), (w * (0.3 + 0.1 * i % 0.4), y0 - 60 + i * 5), (w, y0 + 10), (w, 420)], fill=(60 + i * 12, 90 + i * 10, 70 + i * 6))
    d.text((w // 2, 470), "LISTOPAD 1993", font=font(48, True, serif=True), fill=(40, 40, 40), anchor="mm")
    days = ["Po", "Út", "St", "Čt", "Pá", "So", "Ne"]
    for i, dd in enumerate(days):
        d.text((70 + i * 90, 540), dd, font=font(26, True), fill=(160, 32, 28) if i == 6 else (60, 60, 60), anchor="mm")
    for day in range(1, 31):
        idx = day - 1 + 0          # 1. 11. 1993 = pondělí
        cx, cy = 70 + (idx % 7) * 90, 600 + (idx // 7) * 70
        d.text((cx, cy), str(day), font=font(34), fill=(160, 32, 28) if idx % 7 == 6 else (40, 40, 40), anchor="mm")
        if day in (12, 17, 23):
            d.ellipse([cx - 28, cy - 28, cx + 28, cy + 28], outline=(30, 50, 140), width=4)
    for day in range(1, 11):       # přeškrtnuté dny
        idx = day - 1
        cx, cy = 70 + (idx % 7) * 90, 600 + (idx // 7) * 70
        d.line([cx - 22, cy - 18, cx + 22, cy + 18], fill=(30, 30, 30), width=4)
    age(im, 83).save(os.path.join(OUT, "calendar_1993.jpg"), quality=92)
    # plakát civilní obrany
    w, h = 800, 1130
    im = paper_base(w, h, 84, (0.9, 0.86, 0.72)); d = ImageDraw.Draw(im)
    d.rectangle([30, 30, w - 30, h - 30], outline=(30, 30, 30), width=6)
    cx, cy, r = w // 2, 360, 230
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(230, 160, 30), outline=(30, 30, 30), width=8)
    d.polygon([(cx, cy - 170), (cx - 150, cy + 110), (cx + 150, cy + 110)], fill=(40, 70, 140))
    d.text((cx, 660), "CIVILNÍ OBRANA", font=font(70, True), fill=(30, 30, 30), anchor="mm")
    lines = ["Při vyhlášení poplachu:", "1. Nasaďte ochrannou masku.", "2. Uzavřete okna a dveře.",
             "3. Řiďte se pokyny rozhlasu.", "4. Nepijte vodu z vodovodu!"]
    for i, l in enumerate(lines):
        d.text((90, 760 + i * 58), l, font=font(36, i == 0), fill=(40, 40, 40))
    d.text((cx, h - 70), "ŠTÁB CO OKRESU · 1987", font=font(24), fill=(80, 80, 80), anchor="mm")
    age(im, 85).save(os.path.join(OUT, "poster_civil_defense.jpg"), quality=92)
    # poznámky na nástěnku (psací stroj) + mapka
    notes = [
        ("HLÁŠENÍ Č. 14", ["Objekt B – suterén:", "nalezeny prázdné kotce,", "zámky zvenčí prořezané.", "Vzorek 3/C chybí."]),
        ("ROZKAZ", ["Pracovník č. 7 zůstává", "v karanténě do odvolání.", "Strava 3x denně.", "                — MUDr. H."]),
        ("SEZNAM", ["- filtry do masky (2x)", "- baterie do svítilny", "- klíč od kotelny?", "- NEPÍT vodu v lázních"]),
    ]
    for i, (t, ls) in enumerate(notes):
        w, h = 600, 520
        im = paper_base(w, h, 90 + i); d = ImageDraw.Draw(im)
        d.text((40, 40), t, font=font(40, True, mono=True), fill=(35, 35, 40))
        d.line([40, 95, w - 40, 95], fill=(60, 60, 60), width=2)
        for j, l in enumerate(ls):
            d.text((40, 130 + j * 70), l, font=font(30, mono=True), fill=(35, 35, 45))
        if i == 0:
            d.ellipse([w - 170, h - 170, w - 40, h - 40], outline=(120, 40, 120), width=5)
            d.text((w - 105, h - 105), "TAJNÉ", font=font(26, True), fill=(120, 40, 120), anchor="mm")
        age(im.rotate(0), 95 + i).save(os.path.join(OUT, f"note_{i + 1}.jpg"), quality=92)
    w, h = 900, 650
    im = paper_base(w, h, 99, (0.92, 0.9, 0.84)); d = ImageDraw.Draw(im)
    d.text((40, 30), "AREÁL LÁZNÍ – SITUACE", font=font(34, True), fill=(30, 30, 30))
    for (x0, y0, x1, y1, lab) in [(80, 120, 380, 300, "A – hlavní budova"), (460, 120, 820, 260, "B – laboratoře"),
                                  (460, 330, 700, 560, "C – lázně"), (80, 380, 340, 560, "D – kotelna")]:
        d.rectangle([x0, y0, x1, y1], outline=(30, 30, 30), width=4)
        d.text((x0 + 12, y0 + 12), lab, font=font(24), fill=(30, 30, 30))
    d.line([380, 210, 460, 190], fill=(30, 30, 30), width=3)
    d.line([570, 260, 570, 330], fill=(30, 30, 30), width=3)
    d.ellipse([600, 420, 660, 480], outline=(180, 30, 30), width=6)
    d.line([560, 600, 640, 480], fill=(180, 30, 30), width=4)
    d.text((440, 600), "TADY?!", font=font(34, True), fill=(180, 30, 30))
    age(im, 100).save(os.path.join(OUT, "map_site.jpg"), quality=92)

# ---------------------------------------------------------------- 7) výhled z okna: protější křídlo sanatoria
def window_view():
    w, h = 2048, 1024
    yy, xx = np.mgrid[0:h, 0:w] / np.array([h, w])[:, None, None]
    sky = mix((0.98, 0.83, 0.62), (0.45, 0.58, 0.78), np.clip(1 - yy * 1.6, 0, 1) ** 1.3)
    img = Image.fromarray((sky * 255).astype(np.uint8)); d = ImageDraw.Draw(img)
    r = random.Random(111)
    # vzdálené střechy a komíny (opar)
    for layer, (col, base_y) in enumerate([((150, 128, 118), 520), ((112, 92, 84), 600)]):
        x = 0
        while x < w:
            bw = r.randint(140, 360); bh = r.randint(40, 140)
            top = base_y - bh
            if r.random() < 0.5:
                d.polygon([(x, base_y + 300), (x, top + 40), (x + bw // 2, top), (x + bw, top + 40), (x + bw, base_y + 300)], fill=col)
            else:
                d.rectangle([x, top, x + bw, base_y + 300], fill=col)
            if r.random() < 0.4:
                cx = x + r.randint(20, bw - 30)
                d.rectangle([cx, top - r.randint(40, 120), cx + 22, top + 5], fill=tuple(int(c * 0.9) for c in col))
            x += bw
    # protější křídlo: omítka, řady oken, sedlová střecha
    fy0, fy1 = 470, h
    d.polygon([(-50, fy0), (w * 0.45, fy0 - 110), (w + 50, fy0)], fill=(95, 72, 62))
    d.rectangle([0, fy0, w, fy1], fill=(176, 160, 138))
    for row in range(3):
        for col in range(14):
            x0 = 60 + col * 142; y0 = fy0 + 60 + row * 170
            lit = r.random() < 0.15
            d.rectangle([x0 - 8, y0 - 8, x0 + 78, y0 + 118], fill=(150, 136, 116))
            d.rectangle([x0, y0, x0 + 70, y0 + 110], fill=(230, 190, 120) if lit else (48, 46, 50))
            d.line([x0 + 35, y0, x0 + 35, y0 + 110], fill=(200, 195, 185), width=5)
            d.line([x0, y0 + 40, x0 + 70, y0 + 40], fill=(200, 195, 185), width=5)
    # okapová a kordonová římsa, zatečení
    d.rectangle([0, fy0, w, fy0 + 14], fill=(140, 126, 106))
    a = np.asarray(img, dtype=np.float32) / 255
    stains = spectral(2048, 1.6, 112)[:h, :w]
    facade = (yy > fy0 / h)
    a = a * (1 - (np.clip((stains - 0.55) * 2, 0, 1) * 0.3 * facade)[..., None])
    # západ slunce: teplé světlo zleva na fasádu, opar
    light = np.clip(1.2 - xx * 0.8, 0.5, 1.2)
    a *= (1 + (light - 1) * facade * 0.6)[..., None]
    haze = np.clip(1 - yy * 1.1, 0, 1) * 0.25
    a = a * (1 - haze[..., None]) + np.array((1.0, 0.85, 0.65)) * haze[..., None]
    out = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))
    out.save(os.path.join(OUT, "window_view.jpg"), quality=90)

if __name__ == "__main__":
    what = sys.argv[2:] or ["plaster", "paint", "grunge", "dirt", "glass", "wired", "blanket", "mirror", "papers", "view"]
    if "plaster" in what: plaster()
    if "paint" in what:
        oil_paint("paint_cream", (0.84, 0.81, 0.7), (0.74, 0.7, 0.6))
        oil_paint("paint_green", (0.62, 0.7, 0.62), (0.52, 0.58, 0.52))
    if "grunge" in what: grunge()
    if "dirt" in what: floor_strip()
    if "glass" in what: dirty_glass()
    if "wired" in what: wired_glass()
    if "blanket" in what: blanket()
    if "mirror" in what: mirror()
    if "papers" in what: papers()
    if "view" in what: window_view()
    print("hotovo")
