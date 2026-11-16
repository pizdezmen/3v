"""Синтезує всі звуки гри у WAV: набір «Краплі», гучність 70%. Запуск: python3 tools/gen_sfx.py
Інші набори (bells, kalimba) є в soft_sfx.py."""
import os
import soft_sfx

SR = 44100
SET = "drops"
VOLUME = 0.7
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sfx")

os.makedirs(OUT, exist_ok=True)
for name, (y, gain) in soft_sfx.make_set(SET, SR).items():
    with open(os.path.join(OUT, name + ".wav"), "wb") as f:
        f.write(soft_sfx.wav_bytes(y, gain * VOLUME, SR))
print("ok")
