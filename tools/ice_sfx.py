"""Варіанти звуку льоду для набору «Краплі». ice_variants(sr) -> {ключ: (масив, гучність)}"""
import numpy as np


def ice_variants(sr=44100):
    rng = np.random.default_rng(5)
    def t(d): return np.arange(int(sr * d)) / sr
    def fade(y, a=.004, r=.05):
        n = len(y); na = min(n, max(1, int(sr * a))); nr = min(n, max(1, int(sr * r))); y = y.copy()
        y[:na] *= np.sin(np.linspace(0, np.pi / 2, na)) ** 2; y[-nr:] *= np.cos(np.linspace(0, np.pi / 2, nr)) ** 2
        return y
    def lp(y, cut, times=2):
        k = 1.0 - np.exp(-2 * np.pi * cut / sr)
        for _ in range(times):
            out = np.empty_like(y); acc = 0.0
            for i in range(len(y)):
                acc += k * (y[i] - acc); out[i] = acc
            y = out
        return y
    def hp(y, cut): return y - lp(y, cut, 1)
    def drop(f, d, vol=1.0, glide=.55):
        x = t(d); ff = f * (1 + glide * np.exp(-x / .028)); ph = 2 * np.pi * np.cumsum(ff) / sr
        return fade((np.sin(ph) + .16 * np.sin(2 * ph)) * np.exp(-8.5 * x), .006, .07) * vol
    def glass(f, d, vol=1.0):
        x = t(d)
        y = sum(a * np.sin(2 * np.pi * f * m * x) * np.exp(-dc * x) for m, a, dc in [(1, 1, 9), (2.32, .4, 13), (4.25, .18, 20)])
        return fade(y, .003, .05) * vol
    def crackle(d, n, vol=1.0, cut=3200):
        """Сухий хрускіт: кілька дуже коротких клацань у приглушеному шумі."""
        y = np.zeros(int(sr * d))
        for _ in range(n):
            i = int(rng.uniform(0, .75) ** 1.6 * len(y)); m = int(sr * rng.uniform(.004, .012))
            m = min(m, len(y) - i); y[i:i + m] += rng.standard_normal(m) * np.linspace(1, 0, m) * rng.uniform(.4, 1)
        return lp(hp(y, 500), cut) * vol
    def mix(*parts):
        n = max(int(s * sr) + len(y) for s, y in parts); out = np.zeros(n)
        for s, y in parts:
            i = int(s * sr); out[i:i + len(y)] += y
        return out
    V = {}
    V['crunch'] = (mix((0, crackle(.16, 9, 1.0)), (.01, drop(196, .22, .55, .3))), .5)
    V['bell'] = (mix((0, glass(1175, .45, .8)), (.05, glass(1568, .4, .35)), (0, crackle(.05, 3, .35))), .4)
    V['drip'] = (mix((0, drop(784, .3, .9)), (.09, drop(1175, .22, .45)), (0, crackle(.06, 3, .3))), .45)
    V['scatter'] = (mix((0, crackle(.1, 6, .8)), (.05, drop(1568, .16, .5)), (.11, drop(1319, .16, .42)), (.17, drop(1047, .18, .36)), (.24, drop(784, .25, .3))), .45)
    V['deep'] = (mix((0, drop(330, .35, 1.0, .8)), (0, crackle(.12, 5, .45, 2200)), (.06, glass(880, .3, .22))), .5)
    out = {}
    for k, (y, g) in V.items():
        y = lp(np.asarray(y, float), 5000)
        out[k] = (y / (np.max(np.abs(y)) + 1e-9), g)
    return out
