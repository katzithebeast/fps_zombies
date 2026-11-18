"""Distanční pole zbraní pro úchop rukou (prsty na povrch, ruce nesmí projít zbraní).
Vstup: /tmp/guns/<zbraň>_<díl>.json z tools/export_gun_meshes.gd. Výstup: /tmp/guns/<zbraň>_<díl>.sdf
(hlavička: 3×float32 počátek, float32 buňka, 3×int32 rozměry; pak float32 [z][y][x]). Spuštění: python3 tools/gun_sdf.py"""
import json, glob, os, struct, numpy as np, igl
from scipy import ndimage
CELL = 0.005
MARGIN = 0.045
for path in sorted(glob.glob('/tmp/guns/*.json')):
    tri = np.array(json.load(open(path)), dtype=np.float64)
    V = tri
    F = np.arange(len(V)).reshape(-1, 3).astype(np.int64)
    lo = V.min(0) - MARGIN
    hi = V.max(0) + MARGIN
    dims = np.ceil((hi - lo) / CELL).astype(int) + 1
    xs = lo[0] + np.arange(dims[0]) * CELL
    ys = lo[1] + np.arange(dims[1]) * CELL
    zs = lo[2] + np.arange(dims[2]) * CELL
    Z, Y, X = np.meshgrid(zs, ys, xs, indexing='ij')
    P = np.stack([X.ravel(), Y.ravel(), Z.ravel()], 1)
    S, I, C, N = igl.signed_distance(P, V, F, sign_type=igl.SIGNED_DISTANCE_TYPE_FAST_WINDING_NUMBER)
    S = S.astype(np.float32).reshape(dims[2], dims[1], dims[0])
    # Znaménko: modely zbraní nejsou vodotěsné (lučík, spoušť, tenké plechy) a samotné winding number
    # pak bere za "uvnitř" i otvor lučíku. Venek = vše, kam se z okraje mřížky dá projít buňkami
    # dál než 0,6 buňky od povrchu; uvnitř je jen to, kam se projít nedá a winding number souhlasí.
    U = np.abs(S)
    free = U > 0.6 * CELL
    lab, n = ndimage.label(free)
    edge = np.unique(np.concatenate([lab[0].ravel(), lab[-1].ravel(), lab[:, 0].ravel(), lab[:, -1].ravel(), lab[:, :, 0].ravel(), lab[:, :, -1].ravel()]))
    reached = np.isin(lab, edge[edge > 0])
    inside = (~reached) & (S < 0)
    before = int((S < 0).sum())
    S = np.where(inside, -U, U).astype(np.float32)
    out = path.replace('.json', '.sdf')
    with open(out, 'wb') as f:
        f.write(struct.pack('<4f3i', lo[0], lo[1], lo[2], CELL, *dims.tolist()))
        f.write(S.tobytes())
    print(os.path.basename(out), 'rozměry', dims.tolist(), 'uvnitř buněk', before, '→', int((S < 0).sum()), 'min', float(S.min()))
