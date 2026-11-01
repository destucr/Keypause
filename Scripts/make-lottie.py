#!/usr/bin/env python3
"""Generates Kip's single Lottie composition: Resources/lottie/kip.json  (512x512, 30 fps, 324 frames).

One timeline, five segments. Every segment boundary is a 'home' pose (same body, face, mouth), so the app's
state machine can flow from one segment straight into the next without a visible cut:

   0- 75  SLEEP     loop   (breathing, snore bubble, Zzz)          home = asleep
  75-150  WAKE      once   (yawn, stretch, cap flick, eyes open)  asleep -> awake
 150-240  IDLE      loop   (looks around, blinks, bobs)           home = awake
 240-264  CHEER_IN  once   (arms up, happy face)                  awake -> cheering
 264-324  CHEER     loop   (hops, confetti, sparkles)             home = cheering
"""
import json, os, random

FR = 30
OFF = 0          # frame offset of the segment being built
SEG = 0          # length of the segment being built
TOTAL = 324

def rgb(h, a=1): return [(h >> 16 & 255) / 255, (h >> 8 & 255) / 255, (h & 255) / 255, a]
def st(v): return {"a": 0, "k": v}
EASE = {"i": {"x": [0.45], "y": [1]}, "o": {"x": [0.55], "y": [0]}}

def kf(pairs):
    out = []
    for i, (t, v) in enumerate(pairs):
        k = {"t": t + OFF, "s": v if isinstance(v, list) else [v]}
        if i < len(pairs) - 1: k.update(EASE)
        out.append(k)
    return {"a": 1, "k": out}

def fade(ranges, ramp=3):
    """Opacity (linear) that is 100 inside the segment-local (start, end) ranges, with `ramp`-frame cross-fades."""
    def val(t):
        best = 0
        for s, e in ranges:
            if s <= t <= e: best = 100
            elif s - ramp < t < s: best = max(best, 100 * (t - (s - ramp)) / ramp)
            elif e < t < e + ramp: best = max(best, 100 * (1 - (t - e) / ramp))
        return best
    ts = {0, SEG}
    for s, e in ranges: ts |= {s - ramp, s, e, e + ramp}
    ts = sorted(t for t in ts if 0 <= t <= SEG)
    return {"a": 1, "k": [{"t": t + OFF, "s": [val(t)]} for t in ts]}

def fill(c, o=100): return {"ty": "fl", "c": st(rgb(c)), "o": st(o), "r": 1}
def stroke(c, w, o=100): return {"ty": "st", "c": st(rgb(c)), "o": st(o), "w": st(w), "lc": 2, "lj": 2}
def tr(): return {"ty": "tr", "p": st([0, 0]), "a": st([0, 0]), "s": st([100, 100]), "r": st(0), "o": st(100)}
def group(items): return {"ty": "gr", "it": items + [tr()]}
def rect(cx, cy, w, h, r): return {"ty": "rc", "p": st([cx, cy]), "s": st([w, h]), "r": st(r)}
def ell(cx, cy, w, h): return {"ty": "el", "p": st([cx, cy]), "s": st([w, h])}
def path(verts, ins=None, outs=None, closed=False):
    z = [[0, 0]] * len(verts)
    return {"ty": "sh", "ks": st({"c": closed, "v": verts, "i": ins or z, "o": outs or z})}
def star(points, outer, inner):
    return {"ty": "sr", "sy": 1, "pt": st(points), "p": st([0, 0]), "r": st(0), "or": st(outer), "ir": st(inner), "os": st(0), "is": st(0)}

_idx = [0]
def layer(name, shapes, p=(256, 256), a=(256, 256), s=None, o=None, r=None, parent=None, ty=4):
    _idx[0] += 1
    L = {"ddd": 0, "ind": _idx[0], "ty": ty, "nm": name, "sr": 1, "ao": 0, "ip": OFF, "op": OFF + SEG, "st": 0, "bm": 0,
         "ks": {"o": o or st(100), "r": r or st(0), "p": p if isinstance(p, dict) else st(list(p)),
                "a": st(list(a)), "s": s or st([100, 100])}}
    if ty == 4: L["shapes"] = shapes
    if parent: L["parent"] = parent
    return L

EYE_L, EYE_R = (196, 258), (316, 258)
INK, TEAL, PINK = 0x0C3447, 0x2BB5A6, 0xFF7F8E
BASE = (256, 400)
SMILE = lambda: path([[226, 316], [286, 316]], outs=[[10, 22], [0, 0]], ins=[[0, 0], [-10, 22]])
def bowl(x0, x1, y, h): return path([[x0, y], [x1, y]], ins=[[0, h], [0, 0]], outs=[[0, 0], [0, h]], closed=True)
def arc_eye(x, y): return path([[x - 26, y + 13], [x + 26, y + 13]], outs=[[9, -43], [0, 0]], ins=[[0, 0], [-9, -43]])

class Seg:
    """Collects one segment's layers; `child` parents face parts to this segment's root null."""
    def __init__(self, start, length, p, r, s):
        global OFF, SEG
        OFF, SEG = start, length
        self.front, self.face, self.back = [], [], []
        self.root = layer("Kip root", None, p=p, a=BASE, s=s, r=r, ty=3)
        self.R = self.root["ind"]
    def child(self, name, shapes, **kw): self.face.append(layer(name, shapes, parent=self.R, **kw))
    def layers(self): return self.front + self.face + [self.root] + self.back

def cheeks(sg, opacity):
    for nm, x in (("Cheek L", 172), ("Cheek R", 340)):
        sg.child(nm, [group([ell(x, 308, 42, 27), {"ty": "fl", "c": st(rgb(0xFF8A7A)), "o": opacity, "r": 1}])])

def keycap(sg):
    sg.child("Top rim light", [group([rect(256, 232, 300, 200, 48), stroke(0xFFFFFF, 5, 85)])])
    sg.child("Top shade", [group([rect(256, 380, 320, 40, 20), fill(0xDCE5EA)])])
    sg.child("Keycap top", [group([rect(256, 261, 320, 280, 56), fill(0xF4F8FA)])])
    sg.child("Keycap base", [group([rect(256, 287, 320, 300, 60), fill(0x9FB4BF)])])

def shadow(sg, scale, opacity=None):
    sg.back.append(layer("Ground shadow", [group([ell(256, 452, 300, 40), fill(0x000000)])], s=scale, o=opacity or st(26), a=(256, 452), p=(256, 452)))

def dots(sg, nm, x, y, look, blink, o=None):
    sg.child(nm + " shine", [group([ell(x + 4, y - 14, 15, 18), fill(0xFFFFFF)])], o=o, s=blink, a=(x, y), p=look)
    sg.child(nm, [group([ell(x, y, 46, 56), fill(INK)])], o=o, s=blink, a=(x, y), p=look)

def cap(sg, sway, flick_at=None):
    """Nightcap. If flick_at is set, it hops off the head and fades out from that frame."""
    def fx(base_x, base_y):
        if flick_at is None: return None, None
        f = flick_at
        pos = kf([(0, [base_x, base_y]), (f, [base_x, base_y]), (f + 6, [base_x - 30, base_y - 70]), (f + 16, [base_x - 70, base_y - 120]), (SEG, [base_x - 70, base_y - 120])])
        op = fade([(0, f + 8)], ramp=8)
        return pos, op
    pp, po = fx(256, 256); _ = pp
    if flick_at is None:
        sg.child("Cap pompom", [group([ell(52, 75, 40, 40), fill(0xFFFFFF)])], p=sway, a=(52, 75))
        sg.child("Cap band", [group([path([[116, 147], [305, 121], [300, 99], [111, 125]], closed=True), fill(0xFFFFFF)])])
        sg.child("Cap", [group([path([[116, 138], [304, 114], [60, 70]], ins=[[-15, -25], [0, 0], [70, -15]],
                                     outs=[[0, 0], [-80, -55], [-5, 20]], closed=True), fill(TEAL)])])
    else:
        f = flick_at
        def hop(dx0, dy0):
            return kf([(0, [dx0, dy0]), (f, [dx0, dy0]), (f + 6, [dx0 - 30, dy0 - 70]), (f + 16, [dx0 - 70, dy0 - 120]), (SEG, [dx0 - 70, dy0 - 120])])
        op = fade([(0, f + 6)], ramp=8)
        sg.child("Cap pompom", [group([ell(52, 75, 40, 40), fill(0xFFFFFF)])], a=(52, 75), o=op,
                 p=kf([(0, [52, 75]), (f, [52, 75]), (f + 6, [22, 5]), (f + 16, [-18, -45]), (SEG, [-18, -45])]))
        sg.child("Cap band", [group([path([[116, 147], [305, 121], [300, 99], [111, 125]], closed=True), fill(0xFFFFFF)])], o=op, p=hop(256, 256))
        sg.child("Cap", [group([path([[116, 138], [304, 114], [60, 70]], ins=[[-15, -25], [0, 0], [70, -15]],
                                     outs=[[0, 0], [-80, -55], [-5, 20]], closed=True), fill(TEAL)])], o=op, p=hop(256, 256))

def arms(sg, vis, rot_for):
    for nm, x, sign in (("Arm L", 88, -1), ("Arm R", 424, 1)):
        limb = [group([rect(x, 262, 30, 92, 15), fill(0xDCE6EB), stroke(0x9FB4BF, 4)]),      # arm
                group([ell(x, 214, 46, 44), fill(0xF4F8FA), stroke(0x9FB4BF, 4)])]           # mitten hand
        sg.child(nm, limb, a=(x, 308), p=(x, 308), o=vis, r=rot_for(sign))

def z_letters(sg):
    for i, (x, y, sz) in enumerate(((424, 128, 56), (466, 78, 42), (490, 40, 30))):
        d = i * 10
        op = kf([(0, 0), (d + 4, 0), (d + 14, 100), (d + 34, 100), (d + 46, 0), (SEG, 0)])
        rise = kf([(0, [x, y + 14]), (d + 4, [x, y + 14]), (d + 30, [x + 6, y + 2]), (d + 46, [x + 5, y - 20]), (SEG, [x + 5, y - 20])])
        grow = kf([(0, [60, 60]), (d + 4, [60, 60]), (d + 46, [125, 125]), (SEG, [125, 125])])
        sg.front.append(layer(f"Z{i}", [group([path([[-sz/2, -sz/2], [sz/2, -sz/2], [-sz/2, sz/2], [sz/2, sz/2]]), stroke(0x5FD6C8, 11)])],
                              p=rise, a=(0, 0), o=op, s=grow))

# ---------------------------------------------------------------- segments
def sleep(t0, n=75):
    sg = Seg(t0, n, st(list(BASE)), kf([(0, -5), (37, 8), (75, -5)]), kf([(0, [100, 100]), (37, [106, 93]), (75, [100, 100])]))
    droop = kf([(0, [100, 100]), (37, [100, 52]), (75, [100, 100])])
    for nm, (x, y) in (("Eye L", EYE_L), ("Eye R", EYE_R)):
        sg.child(nm, [group([rect(x, y, 30, 78, 14), fill(0x14677A)])], s=droop, a=(x, y), p=(x, y))
    snore = kf([(0, [100, 100]), (37, [150, 140]), (75, [100, 100])])
    sg.child("Mouth o", [group([ell(256, 325, 24, 20), fill(INK)])], s=snore, a=(256, 325), p=(256, 325))
    cheeks(sg, kf([(0, 50), (37, 85), (75, 50)]))
    cap(sg, kf([(0, [52, 75]), (19, [44, 86]), (37, [54, 78]), (56, [47, 88]), (75, [52, 75])]))
    bs = kf([(0, [0, 0]), (6, [0, 0]), (44, [100, 100]), (50, [110, 110]), (52, [150, 150]), (54, [0, 0]), (75, [0, 0])])
    bo = kf([(0, 0), (6, 0), (7, 100), (52, 100), (53, 30), (54, 0), (75, 0)])
    sg.front.append(layer("Snore bubble", [group([ell(286, 318, 58, 58), fill(0xBDEFF0, 55), stroke(0x2BB5A6, 3)])], parent=sg.R, s=bs, o=bo, a=(286, 318), p=(286, 318)))
    z_letters(sg)
    keycap(sg)
    shadow(sg, kf([(0, [100, 100]), (37, [96, 100]), (75, [100, 100])]))
    return sg.layers()

def wake(t0, n=75):
    sg = Seg(t0, n, st(list(BASE)), kf([(0, -5), (15, -2), (30, 3), (45, -3), (62, 2), (75, 0)]),
             kf([(0, [100, 100]), (14, [100, 100]), (26, [92, 114]), (40, [94, 110]), (54, [104, 93]), (75, [100, 100])]))
    for nm, (x, y) in (("Eye L", EYE_L), ("Eye R", EYE_R)):
        sg.child(nm + " asleep", [group([rect(x, y, 30, 78, 14), fill(0x14677A)])], o=fade([(0, 8)], 4), a=(x, y), p=(x, y))
    sg.child("Squint L", [group([path([[180, 242], [208, 258], [180, 274]]), stroke(INK, 11)])], o=fade([(10, 36)], 4))
    sg.child("Squint R", [group([path([[332, 242], [304, 258], [332, 274]]), stroke(INK, 11)])], o=fade([(10, 36)], 4))
    flutter = kf([(0, [100, 30]), (36, [100, 30]), (42, [100, 45]), (48, [100, 12]), (54, [100, 70]), (60, [100, 100]), (64, [100, 8]), (68, [100, 100]), (75, [100, 100])])
    look = lambda x, y: kf([(0, [x, y]), (56, [x, y]), (62, [x + 6, y + 2]), (70, [x - 4, y]), (75, [x, y])])
    for nm, (x, y) in (("Eye L", EYE_L), ("Eye R", EYE_R)):
        dots(sg, nm, x, y, look(x, y), flutter, o=fade([(36, 75)], 5))
    yawn = kf([(10, [30, 30]), (22, [100, 100]), (34, [106, 110]), (38, [25, 25]), (75, [25, 25])])
    sg.child("Mouth o", [group([ell(256, 325, 24, 20), fill(INK)])], o=fade([(0, 9)], 3), a=(256, 325), p=(256, 325))
    sg.child("Yawn tongue", [group([ell(256, 352, 34, 18), fill(PINK)])], o=fade([(11, 36)], 3), s=yawn, a=(256, 326), p=(256, 326))
    sg.child("Yawn mouth", [group([ell(256, 334, 50, 62), fill(INK)])], o=fade([(11, 36)], 3), s=yawn, a=(256, 326), p=(256, 326))
    sg.child("Mouth smile", [group([SMILE(), stroke(INK, 11)])], o=fade([(36, 75)], 4))
    cheeks(sg, st(50))
    arms(sg, fade([(14, 44)], 3), lambda sign: kf([(0, sign * 8), (14, sign * 8), (26, sign * 72), (36, sign * 78), (46, sign * 8), (75, sign * 8)]))
    cap(sg, kf([(0, [52, 75]), (15, [48, 80]), (30, [56, 72]), (45, [50, 84]), (75, [52, 75])]), flick_at=46)
    keycap(sg)
    shadow(sg, st([100, 100]))
    return sg.layers()

def idle(t0, n=90):
    sg = Seg(t0, n, kf([(0, [256, 400]), (22, [256, 392]), (45, [256, 400]), (67, [256, 392]), (90, [256, 400])]),
             kf([(0, 0), (22, -4), (45, 0), (67, 4), (90, 0)]),
             kf([(0, [100, 100]), (10, [104, 95]), (22, [98, 103]), (45, [102, 98]), (56, [104, 95]), (67, [98, 103]), (90, [100, 100])]))
    look = lambda x, y: kf([(0, [x, y]), (20, [x, y]), (30, [x + 12, y - 2]), (48, [x + 12, y - 2]), (58, [x - 12, y - 2]), (76, [x - 12, y - 2]), (86, [x, y]), (90, [x, y])])
    blink = kf([(0, [100, 100]), (52, [100, 100]), (55, [100, 8]), (58, [100, 100]), (90, [100, 100])])
    for nm, (x, y) in (("Eye L", EYE_L), ("Eye R", EYE_R)):
        dots(sg, nm, x, y, look(x, y), blink)
    grin = kf([(0, [100, 100]), (36, [118, 130]), (56, [118, 130]), (90, [100, 100])])
    sg.child("Mouth smile", [group([SMILE(), stroke(INK, 11)])], s=grin, a=(256, 322), p=(256, 322))
    cheeks(sg, kf([(0, 50), (45, 80), (90, 50)]))
    keycap(sg)
    shadow(sg, kf([(0, [100, 100]), (45, [96, 100]), (90, [100, 100])]))
    return sg.layers()

def cheer_in(t0, n=24):
    sg = Seg(t0, n, st(list(BASE)), st(0), kf([(0, [100, 100]), (8, [112, 88]), (16, [96, 106]), (24, [100, 100])]))
    for nm, (x, y) in (("Eye L", EYE_L), ("Eye R", EYE_R)):
        dots(sg, nm, x, y, st([x, y]), st([100, 100]), o=fade([(0, 4)], 4))
        sg.child(nm + " happy", [group([arc_eye(x, y), stroke(INK, 13)])], o=fade([(8, 24)], 4))
    sg.child("Mouth smile", [group([SMILE(), stroke(INK, 11)])], o=fade([(0, 6)], 4))
    sg.child("Tongue", [group([ell(256, 334, 46, 22), fill(PINK)])], o=fade([(8, 24)], 4))
    sg.child("Mouth grin", [group([bowl(203, 309, 303, 58), fill(INK)])], o=fade([(8, 24)], 4))
    cheeks(sg, kf([(0, 50), (24, 80)]))
    arms(sg, fade([(8, 24)], 6), lambda sign: kf([(0, sign * 8), (8, sign * 8), (24, sign * 30)]))
    keycap(sg)
    shadow(sg, st([100, 100]))
    return sg.layers()

def cheer(t0, n=60):
    random.seed(11)
    sg = Seg(t0, n,
             kf([(0, [256, 400]), (10, [256, 400]), (22, [256, 300]), (34, [256, 372]), (40, [256, 400]), (60, [256, 400])]),
             kf([(0, 0), (14, -6), (28, 6), (40, 0), (60, 0)]),
             kf([(0, [100, 100]), (10, [114, 84]), (18, [92, 112]), (30, [98, 104]), (40, [118, 80]), (48, [96, 106]), (60, [100, 100])]))
    happy = kf([(0, [100, 100]), (14, [100, 130]), (28, [100, 100]), (44, [100, 70]), (60, [100, 100])])
    for nm, (x, y) in (("Eye L", EYE_L), ("Eye R", EYE_R)):
        sg.child(nm, [group([arc_eye(x, y), stroke(INK, 13)])], s=happy, a=(x, y + 13), p=(x, y + 13))
    sg.child("Tongue", [group([ell(256, 334, 46, 22), fill(PINK)])])
    sg.child("Mouth grin", [group([bowl(203, 309, 303, 58), fill(INK)])])
    cheeks(sg, kf([(0, 80), (20, 100), (60, 80)]))
    arms(sg, st(100), lambda sign: kf([(0, sign * 30), (14, sign * 62), (28, sign * 38), (44, sign * 66), (60, sign * 30)]))
    colors = [0xFFC857, 0xFF6B6B, 0x2BB5A6, 0x6C8CFF, 0xFF9AD5]
    for i in range(10):
        x = random.randint(30, 482); d = random.randint(0, 8); dur = random.randint(36, 50)
        sway = random.choice((-1, 1)) * random.randint(14, 30)
        fall = kf([(0, [x, -30]), (d, [x, -30]), (d + dur, [x + sway, 540]), (60, [x + sway, 540])])
        spin = kf([(0, 0), (60, random.choice((-1, 1)) * random.randint(240, 480))])
        (sg.front if i % 2 else sg.back).append(layer(f"Confetti{i}", [group([rect(0, 0, 11, 18, 3), fill(random.choice(colors))])], p=fall, a=(0, 0), r=spin))
    for i, (x, y, rad) in enumerate(((75, 102, 30), (442, 92, 24), (60, 252, 16), (452, 230, 18))):
        d = i * 4
        sc = kf([(0, [0, 0]), (d, [0, 0]), (d + 8, [110, 110]), (d + 22, [30, 30]), (d + 34, [100, 100]), (d + 48, [0, 0]), (60, [0, 0])])
        sg.front.append(layer(f"Sparkle{i}", [group([star(4, rad, rad * 0.22), fill(0xFFC857)])], p=(x, y), a=(0, 0), s=sc, r=kf([(0, 0), (60, 90)])))
    keycap(sg)
    shadow(sg, kf([(0, [100, 100]), (10, [110, 100]), (22, [60, 100]), (34, [90, 100]), (40, [118, 100]), (48, [100, 100]), (60, [100, 100])]),
           kf([(0, 26), (22, 12), (40, 30), (60, 26)]))
    return sg.layers()

layers = []
for builder, start in ((sleep, 0), (wake, 75), (idle, 150), (cheer_in, 240), (cheer, 264)):
    layers += builder(start)
comp = {"v": "5.9.0", "fr": FR, "ip": 0, "op": TOTAL, "w": 512, "h": 512, "nm": "Kip", "ddd": 0, "assets": [], "layers": layers,
        "markers": [{"tm": 0, "cm": "sleep", "dr": 75}, {"tm": 75, "cm": "wake", "dr": 75}, {"tm": 150, "cm": "idle", "dr": 90},
                    {"tm": 240, "cm": "cheer-in", "dr": 24}, {"tm": 264, "cm": "cheer", "dr": 60}]}
out = os.path.join(os.path.dirname(__file__), "..", "Resources", "lottie")
os.makedirs(out, exist_ok=True)
for f in os.listdir(out): os.remove(os.path.join(out, f))
with open(os.path.join(out, "kip.json"), "w") as f: json.dump(comp, f, separators=(",", ":"))
print(len(layers), "layers", round(len(json.dumps(comp)) / 1024, 1), "KB")
