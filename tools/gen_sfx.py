"""Синтезує всі звуки гри у WAV. Запуск: python3 tools/gen_sfx.py"""
import os
import wave
import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sfx")
rng = np.random.default_rng(7)


def t(d):
    return np.linspace(0, d, int(SR * d), endpoint=False)


def env(x, a=0.005, r=0.08):
    n = len(x)
    e = np.ones(n)
    na, nr = min(n, max(1, int(SR * a))), min(n, max(1, int(SR * r)))
    e[:na] = np.linspace(0, 1, na)
    e[-nr:] *= np.linspace(1, 0, nr)
    return x * e


def tone(f, d, decay=8.0, harm=(1.0, 0.35, 0.12)):
    x = t(d)
    y = sum(a * np.sin(2 * np.pi * f * (k + 1) * x) for k, a in enumerate(harm))
    return env(y * np.exp(-decay * x))


def sweep(f0, f1, d, decay=5.0):
    x = t(d)
    f = f0 * (f1 / f0) ** (x / d)
    return env(np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-decay * x))


def noise(d, decay=20.0, lp=0.3):
    y = rng.standard_normal(int(SR * d))
    out = np.zeros_like(y)
    acc = 0.0
    for i, v in enumerate(y):
        acc += lp * (v - acc)
        out[i] = acc
    return env(out * np.exp(-decay * t(d)), 0.002, 0.03)


def mix(*parts):
    n = max(len(p[1]) + int(p[0] * SR) for p in parts)
    y = np.zeros(n)
    for start, data in parts:
        s = int(start * SR)
        y[s:s + len(data)] += data
    return y


def save(name, y, gain=0.7):
    y = y / (np.max(np.abs(y)) + 1e-9) * gain
    data = (y * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(data.tobytes())


os.makedirs(OUT, exist_ok=True)
save("click", tone(660, 0.07, 40), 0.4)
save("swap", sweep(380, 620, 0.11, 12), 0.35)
save("bad", mix((0, tone(196, 0.12, 18)), (0.09, tone(165, 0.16, 16))), 0.4)
save("match", mix((0, tone(784, 0.28, 11)), (0, tone(1568, 0.2, 16) * 0.3)), 0.5)
save("land", noise(0.06, 45, 0.08), 0.22)
save("create", mix((0, tone(659, 0.2, 9)), (0.07, tone(880, 0.2, 9)), (0.14, tone(1175, 0.35, 7))), 0.5)
save("line", mix((0, sweep(300, 1500, 0.28, 5)), (0, noise(0.28, 9, 0.5) * 0.35)), 0.5)
save("bomb", mix((0, sweep(160, 45, 0.5, 6)), (0, noise(0.45, 8, 0.12) * 0.9)), 0.75)
save("star", mix(*[(i * 0.05, tone(f, 0.4, 6)) for i, f in enumerate([523, 659, 784, 1047, 1319])]), 0.5)
save("fly", sweep(900, 1700, 0.3, 4) * (0.6 + 0.4 * np.sin(2 * np.pi * 28 * t(0.3))), 0.3)
save("wood", mix((0, noise(0.12, 30, 0.2)), (0, tone(140, 0.12, 30) * 0.8)), 0.6)
save("ice", mix((0, noise(0.2, 22, 0.9) * 0.6), (0, tone(2100, 0.2, 18) * 0.4), (0.03, tone(2800, 0.15, 22) * 0.3)), 0.45)
save("chain", mix((0, tone(1244, 0.12, 25, (1, 0.6, 0.5, 0.4))), (0.05, tone(1661, 0.2, 18, (1, 0.6, 0.5, 0.4)))), 0.4)
save("shuffle", mix(*[(i * 0.045, sweep(500 + i * 60, 700 + i * 60, 0.08, 14)) for i in range(6)]), 0.35)
save("win", mix(*[(s, tone(f, 0.7, 4)) for s, f in [(0, 523), (0.13, 659), (0.26, 784), (0.39, 1047), (0.6, 784), (0.6, 1047), (0.6, 1319)]]), 0.6)
save("lose", mix((0, tone(392, 0.4, 5)), (0.22, tone(330, 0.4, 5)), (0.44, tone(262, 0.8, 3.5))), 0.5)
print("ok")
