#!/usr/bin/env python3
"""Generates the app's own voice pack into assets/voice/{ar,en}/*.mp3 (bundled in the APK,
so the app speaks fully offline). Neural voice (edge-tts) -> studio-style mastering with ffmpeg
(high-pass, trim, two-pass loudness match, 44.1 kHz / 128 kbps). If the neural voice is
unreachable for a clip, falls back to espeak-ng so the app is never silent.
Env: VOICE_AR (default ar-JO-TaimNeural; female ar-JO-SanaNeural), VOICE_EN (en-US-GuyNeural),
VOICE_RATE (default +4%)."""
import asyncio, json, os, re, shutil, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VOICES = {"ar": os.environ.get("VOICE_AR", "ar-JO-TaimNeural"),
          "en": os.environ.get("VOICE_EN", "en-US-GuyNeural")}
RATE = os.environ.get("VOICE_RATE", "+4%")
MANIFEST = json.loads((ROOT / "tool" / "voice_manifest.json").read_text(encoding="utf-8"))
FF = shutil.which("ffmpeg")
ESPEAK = shutil.which("espeak-ng")
TARGET_I, TARGET_TP, TARGET_LRA = -18.0, -2.0, 7.0
PRE = ("highpass=f=70,"
       "silenceremove=start_periods=1:start_silence=0.02:start_threshold=-45dB,areverse,"
       "silenceremove=start_periods=1:start_silence=0.02:start_threshold=-45dB,areverse")
POST = "afade=t=in:d=0.004,areverse,afade=t=in:d=0.012,areverse"


def run(args):
    return subprocess.run(args, capture_output=True, text=True)


def master(src: Path, dst: Path) -> bool:
    """Trim + loudness-normalise + re-encode. Returns True on success."""
    if not FF:
        return False
    r = run([FF, "-hide_banner", "-i", str(src), "-af",
             f"{PRE},loudnorm=I={TARGET_I}:TP={TARGET_TP}:LRA={TARGET_LRA}:print_format=json",
             "-f", "null", "-"])
    m = re.search(r"\{[^{}]*\"input_i\"[^{}]*\}", r.stderr, re.S)
    gain = None
    try:
        j = json.loads(m.group(0))
        vals = [float(j[k]) for k in ("input_i", "input_tp", "input_lra", "input_thresh", "target_offset")]
        if all(abs(v) < 200 for v in vals):
            norm = (f"loudnorm=I={TARGET_I}:TP={TARGET_TP}:LRA={TARGET_LRA}:"
                    f"measured_I={vals[0]}:measured_TP={vals[1]}:measured_LRA={vals[2]}:"
                    f"measured_thresh={vals[3]}:offset={vals[4]}:linear=true")
        else:
            raise ValueError
    except Exception:
        # very short clip (single letter): loudness gating can't measure it -> peak-normalise
        v = run([FF, "-hide_banner", "-i", str(src), "-af", f"{PRE},volumedetect", "-f", "null", "-"])
        mm = re.search(r"max_volume:\s*(-?[\d.]+) dB", v.stderr)
        gain = (-5.0 - float(mm.group(1))) if mm else 0.0
        norm = f"volume={gain:.2f}dB,alimiter=limit=0.8"
    out = run([FF, "-y", "-loglevel", "error", "-i", str(src), "-af", f"{PRE},{norm},{POST}",
               "-ar", "44100", "-ac", "1", "-c:a", "libmp3lame", "-b:a", "128k", str(dst)])
    return out.returncode == 0 and dst.exists() and dst.stat().st_size > 200


def espeak(lang: str, text: str, wav: Path) -> bool:
    if not ESPEAK:
        return False
    r = run([ESPEAK, "-v", "ar" if lang == "ar" else "en-us", "-s", "150", "-w", str(wav), text])
    return r.returncode == 0 and wav.exists()


async def one(lang, cid, text, sem, stats):
    import edge_tts
    out = ROOT / "assets" / "voice" / lang / f"{cid}.mp3"
    out.parent.mkdir(parents=True, exist_ok=True)
    if out.exists():
        return
    tmp = Path(tempfile.mkdtemp())
    raw = tmp / "raw.mp3"
    ok = False
    async with sem:
        for attempt in range(4):
            try:
                await edge_tts.Communicate(text, VOICES[lang], rate=RATE).save(str(raw))
                ok = raw.exists() and raw.stat().st_size > 200
                if ok:
                    break
            except Exception as e:
                if attempt == 3:
                    print("neural voice failed", lang, cid, e)
                await asyncio.sleep(1.5 * (attempt + 1))
    if ok:
        stats["neural"] += 1
    else:
        raw = tmp / "raw.wav"
        if espeak(lang, text, raw):
            stats["espeak"] += 1
            ok = True
    if ok and master(raw, out):
        return
    if ok and raw.suffix == ".mp3":
        shutil.copy(raw, out)  # mastering unavailable: still ship the clip
        return
    print("FAILED", lang, cid)
    stats["failed"] += 1


async def main():
    stats = {"neural": 0, "espeak": 0, "failed": 0}
    sem = asyncio.Semaphore(4)
    await asyncio.gather(*[one(lang, cid, t[lang], sem, stats)
                           for cid, t in MANIFEST.items() for lang in ("ar", "en")])
    total = sum(1 for _ in (ROOT / "assets" / "voice").rglob("*.mp3"))
    expected = len(MANIFEST) * 2
    print(f"voice pack: {total}/{expected} clips  (neural={stats['neural']} espeak={stats['espeak']} failed={stats['failed']})")
    if total < expected:
        sys.exit(1)

asyncio.run(main())
