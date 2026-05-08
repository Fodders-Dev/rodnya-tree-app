"""Generate ringback / ringtone / dial-tone WAVs as bundled placeholders.

We don't ship a curated audio library yet — these are synthesized from
the canonical telephony tone tables so the app at least HAS a ringer
that mimics what users expect from a phone call.

Tones:
  - ringback.wav  -> outgoing call: 440 Hz + 480 Hz dual-tone, 1s on / 3s off
                     Russian / North-American RBT pattern. Loops cleanly.
  - ringtone.wav  -> incoming call: arpeggio (G4 -> B4 -> D5 -> G5) repeated
                     2x with a brief silence, simple but pleasant.
  - dial_tone.wav -> precall: 350 Hz + 440 Hz continuous, 0.6s.
                     North-American dial tone (we don't ship a precall but
                     this is here as a fallback for SystemSound replacements).

All 16-bit mono PCM at 22 050 Hz — small footprint, fine for a ringer.
Output is written to repo `assets/audio/`.
"""

import math
import os
import struct
import wave

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), '..'))
OUT_DIR = os.path.join(ROOT, 'assets', 'audio')
os.makedirs(OUT_DIR, exist_ok=True)

SAMPLE_RATE = 22050
AMPLITUDE = 0.32  # leave headroom — dual-tone sums can clip if both at full


def write_wav(path: str, samples: list[float]) -> None:
    pcm = bytearray()
    for sample in samples:
        clipped = max(-1.0, min(1.0, sample))
        pcm.extend(struct.pack('<h', int(clipped * 32767)))
    with wave.open(path, 'wb') as fh:
        fh.setnchannels(1)
        fh.setsampwidth(2)
        fh.setframerate(SAMPLE_RATE)
        fh.writeframes(bytes(pcm))


def tone(freq_hz: float, duration_s: float, amp: float = AMPLITUDE) -> list[float]:
    n = int(duration_s * SAMPLE_RATE)
    return [
        amp * math.sin(2 * math.pi * freq_hz * (i / SAMPLE_RATE))
        for i in range(n)
    ]


def dual_tone(f1: float, f2: float, duration_s: float,
              amp: float = AMPLITUDE) -> list[float]:
    n = int(duration_s * SAMPLE_RATE)
    half = amp / 2
    return [
        half * (
            math.sin(2 * math.pi * f1 * (i / SAMPLE_RATE)) +
            math.sin(2 * math.pi * f2 * (i / SAMPLE_RATE))
        )
        for i in range(n)
    ]


def silence(duration_s: float) -> list[float]:
    return [0.0] * int(duration_s * SAMPLE_RATE)


def envelope_in_out(samples: list[float], fade_s: float = 0.05) -> list[float]:
    """Soften tone edges so loops don't click."""
    n = len(samples)
    fade_n = min(int(fade_s * SAMPLE_RATE), n // 2)
    if fade_n <= 0:
        return samples
    out = list(samples)
    for i in range(fade_n):
        ratio = i / fade_n
        out[i] *= ratio
        out[n - 1 - i] *= ratio
    return out


# ── Ringback (outgoing) ────────────────────────────────────────────────────
# Russian RBT: 1s on / 3-4s off. North-American: same 1s on but 3s off.
# Use 1s on / 3s off — within a single 4s loop cycle.
ringback = (
    envelope_in_out(dual_tone(440, 480, 1.0)) +
    silence(3.0)
)
write_wav(os.path.join(OUT_DIR, 'ringback.wav'), ringback)
print(f'Wrote ringback.wav ({len(ringback) / SAMPLE_RATE:.2f}s)')

# ── Ringtone (incoming) ────────────────────────────────────────────────────
# Pleasant arpeggio: G4(392) -> B4(494) -> D5(587) -> G5(784)
# Two passes + 1.2s silence so it loops cleanly when played in a Timer.
def note(freq: float, duration_s: float = 0.18) -> list[float]:
    return envelope_in_out(tone(freq, duration_s), fade_s=0.02)

arpeggio = (
    note(392) + note(494) + note(587) + note(784) +
    silence(0.18) +
    note(784) + note(587) + note(494) + note(392) +
    silence(1.2)
)
write_wav(os.path.join(OUT_DIR, 'ringtone.wav'), arpeggio)
print(f'Wrote ringtone.wav ({len(arpeggio) / SAMPLE_RATE:.2f}s)')

# ── Dial tone (precall) ────────────────────────────────────────────────────
dial = envelope_in_out(dual_tone(350, 440, 0.6))
write_wav(os.path.join(OUT_DIR, 'dial_tone.wav'), dial)
print(f'Wrote dial_tone.wav ({len(dial) / SAMPLE_RATE:.2f}s)')

# ── Soft "tap" / call connected confirm ────────────────────────────────────
connect = (
    envelope_in_out(tone(880, 0.12), fade_s=0.02) +
    envelope_in_out(tone(1320, 0.16), fade_s=0.02)
)
write_wav(os.path.join(OUT_DIR, 'connect.wav'), connect)
print(f'Wrote connect.wav ({len(connect) / SAMPLE_RATE:.2f}s)')

# ── Soft "end" / call ended ───────────────────────────────────────────────
hangup = envelope_in_out(tone(880, 0.16), fade_s=0.02) + envelope_in_out(tone(440, 0.24), fade_s=0.02)
write_wav(os.path.join(OUT_DIR, 'hangup.wav'), hangup)
print(f'Wrote hangup.wav ({len(hangup) / SAMPLE_RATE:.2f}s)')

print('\nDone. Total files:')
for fn in sorted(os.listdir(OUT_DIR)):
    full = os.path.join(OUT_DIR, fn)
    print(f'  {fn:20s} {os.path.getsize(full) / 1024:.1f} KB')
