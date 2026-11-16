"""М'які вечірні звуки гри, три набори. Використовує і сторінка зразків, і гра.
make_set(key, sr) -> {назва: (масив, гучність)}; key: bells | kalimba | drops"""
import numpy as np

NAMES = ["click", "swap", "bad", "match", "create", "line", "bomb", "star", "fly",
         "wood", "ice", "chain", "win", "lose", "land", "shuffle"]
PENTA = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21]   # мажорна пентатоніка в півтонах


def make_set(key, sr=44100):
    rng = np.random.default_rng(11)

    def t(d): return np.arange(int(sr * d)) / sr

    def fade(y, a=0.004, r=0.05):
        n = len(y); na = min(n, max(1, int(sr * a))); nr = min(n, max(1, int(sr * r)))
        y = y.copy(); y[:na] *= np.sin(np.linspace(0, np.pi / 2, na)) ** 2; y[-nr:] *= np.cos(np.linspace(0, np.pi / 2, nr)) ** 2
        return y

    def lp(y, cut):
        """Простий фільтр низьких частот, двічі, щоб звук був м'якшим."""
        k = 1.0 - np.exp(-2 * np.pi * cut / sr)
        for _ in range(2):
            out = np.empty_like(y); acc = 0.0
            for i in range(len(y)):
                acc += k * (y[i] - acc); out[i] = acc
            y = out
        return y

    def st(f, semis): return f * 2 ** (semis / 12.0)

    def note(f, d, vol=1.0):
        x = t(d)
        if key == 'bells':
            parts = [(1, 1.0, 5.0), (2.0, .22, 7.0), (2.76, .28, 9.0), (5.4, .10, 14.0), (8.93, .04, 20.0)]
            y = sum(a * np.sin(2 * np.pi * f * m * x) * np.exp(-dc * x) for m, a, dc in parts)
            return fade(y, .004, .06) * vol
        if key == 'kalimba':
            parts = [(1, 1.0, 7.0), (2.0, .30, 11.0), (3.0, .10, 15.0), (5.9, .14, 38.0)]
            y = sum(a * np.sin(2 * np.pi * f * m * x) * np.exp(-dc * x) for m, a, dc in parts)
            n = min(len(x), int(sr * .012))
            y[:n] += lp(rng.standard_normal(n), 1800) * np.linspace(.9, 0, n)
            return fade(y, .002, .05) * vol
        # drops: синус із коротким сковзанням висоти вниз, як крапля
        ff = f * (1 + .55 * np.exp(-x / .028))
        ph = 2 * np.pi * np.cumsum(ff) / sr
        y = (np.sin(ph) + .16 * np.sin(2 * ph)) * np.exp(-8.5 * x)
        return fade(y, .006, .07) * vol

    def air(d, f0, f1, vol=1.0, width=.5):
        """Повітряний шурхіт: шум, що пливе по висоті."""
        n = int(sr * d); y = rng.standard_normal(n); out = np.empty(n); lo = 0.0; bp = 0.0
        x = np.arange(n) / n
        fc = f0 * (f1 / f0) ** x
        for i in range(n):
            g = 2 * np.sin(np.pi * min(fc[i], sr / 6.5) / sr)
            lo += g * bp; hi = y[i] - lo - width * bp; bp += g * hi; out[i] = bp
        e = np.sin(np.pi * x) ** 1.5
        return out * e * vol * .5

    def thud(f0, f1, d, vol=1.0):
        x = t(d); f = f0 * (f1 / f0) ** (x / d)
        return fade(np.sin(2 * np.pi * np.cumsum(f) / sr) * np.exp(-9 * x / (d / .3)), .004, .05) * vol

    def mix(*parts):
        n = max(int(s * sr) + len(y) for s, y in parts); out = np.zeros(n)
        for s, y in parts:
            i = int(s * sr); out[i:i + len(y)] += y
        return out

    root = {'bells': 523.25, 'kalimba': 261.63, 'drops': 392.0}[key]
    tail = {'bells': 1.0, 'kalimba': .7, 'drops': .8}[key]
    P = lambda i: st(root, PENTA[i])
    S = {}
    S['click'] = (note(P(3), .12 * tail + .06), .35)
    S['swap'] = (mix((0, air(.16, 500, 1400, .5)), (.02, note(P(1), .16, .5))), .4)
    S['bad'] = (mix((0, note(st(root, -5), .22, .8)), (.11, note(st(root, -8), .3, .8))), .45)
    S['match'] = (note(root, .5 * tail + .15), .6)
    S['create'] = (mix((0, note(P(0), .5 * tail)), (.07, note(P(2), .5 * tail)), (.14, note(P(3), .6 * tail)), (.21, note(P(5), .8 * tail, .8))), .6)
    S['line'] = (mix((0, air(.42, 350, 2600, 1.0)), (.03, note(P(3), .5 * tail, .45)), (.13, note(P(5), .5 * tail, .35))), .55)
    S['bomb'] = (mix((0, thud(95, 42, .55)), (0, lp(rng.standard_normal(int(sr * .5)), 420) * np.exp(-7 * t(.5)) * .8), (.03, note(st(root, -12), .5, .35))), .75)
    S['star'] = (mix(*[(.075 * i, note(P(i), (.75 + .05 * i) * tail, .8)) for i in range(6)], (0, air(.7, 800, 3200, .35))), .6)
    S['fly'] = (air(.3, 900, 1700, 1.0, .25) * (1 + .5 * np.sin(2 * np.pi * 17 * t(.3)))[:int(sr * .3)], .4)
    S['wood'] = (mix((0, thud(190, 110, .16)), (0, lp(rng.standard_normal(int(sr * .05)), 1500) * np.linspace(1, 0, int(sr * .05)) * .7), (.012, thud(310, 240, .08, .4))), .6)
    S['ice'] = (mix(*[(d, note(st(root * (4 if key != 'bells' else 2), s), .22, v)) for d, s, v in [(0, 12, .7), (.035, 19, .5), (.075, 16, .45), (.12, 24, .3)]]), .4)
    S['chain'] = (mix((0, note(P(5), .6 * tail, .7)), (.045, note(st(P(5), 7.02), .7 * tail, .5)), (.09, note(P(7), .9 * tail, .4)), (0, air(.3, 2000, 5000, .25))), .5)
    S['win'] = (mix((0, note(P(0), .6)), (.16, note(P(2), .6)), (.32, note(P(3), .7)), (.5, note(P(5), 1.3)), (.5, note(P(3), 1.3, .6)), (.5, note(P(2), 1.3, .5)), (.66, note(P(7), 1.2, .4))), .65)
    S['lose'] = (mix((0, note(P(3), .6, .8)), (.24, note(P(1), .7, .8)), (.5, note(st(root, -3), 1.2, .9))), .5)
    S['land'] = (mix((0, thud(130, 85, .1)), (0, note(st(root, -12), .1, .25))), .3)
    S['shuffle'] = (mix(*[(.055 * i, note(P(j), .25 * tail + .1, .7)) for i, j in enumerate([4, 1, 5, 2, 6, 3, 7])], (0, air(.45, 600, 2000, .5))), .5)
    out = {}
    for n, (y, g) in S.items():
        y = lp(np.asarray(y, dtype=float), 6500 if key == 'bells' else 5000)
        out[n] = (y / (np.max(np.abs(y)) + 1e-9), g)
    return out


def wav_bytes(y, gain, sr):
    import io, wave
    data = (np.clip(y * gain, -1, 1) * 32767).astype(np.int16)
    b = io.BytesIO()
    with wave.open(b, 'wb') as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(sr); f.writeframes(data.tobytes())
    return b.getvalue()
