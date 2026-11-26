#!/usr/bin/env python3
"""Generates the app's own voice pack (neural voice) into assets/voice/{ar,en}/*.mp3.
Run once (needs internet):  pip install edge-tts && python tool/make_voice_pack.py
Change voices with env vars: VOICE_AR (default ar-JO-TaimNeural; female: ar-JO-SanaNeural),
VOICE_EN (default en-US-GuyNeural), VOICE_RATE (default +6%)."""
import asyncio, json, os, shutil, subprocess
from pathlib import Path
import edge_tts

ROOT = Path(__file__).resolve().parent.parent
VOICES = {"ar": os.environ.get("VOICE_AR", "ar-JO-TaimNeural"),
          "en": os.environ.get("VOICE_EN", "en-US-GuyNeural")}
RATE = os.environ.get("VOICE_RATE", "+6%")
MANIFEST = json.loads((ROOT / "tool" / "voice_manifest.json").read_text(encoding="utf-8"))
FF = shutil.which("ffmpeg")
TRIM = ("silenceremove=start_periods=1:start_silence=0.02:start_threshold=-45dB,areverse,"
        "silenceremove=start_periods=1:start_silence=0.02:start_threshold=-45dB,areverse")

async def one(lang, cid, text, sem):
    out = ROOT / "assets" / "voice" / lang / f"{cid}.mp3"
    out.parent.mkdir(parents=True, exist_ok=True)
    if out.exists():
        return
    raw = out.with_suffix(".raw.mp3")
    async with sem:
        for attempt in range(4):
            try:
                await edge_tts.Communicate(text, VOICES[lang], rate=RATE).save(str(raw))
                break
            except Exception as e:
                if attempt == 3:
                    print("FAILED", lang, cid, e)
                    return
                await asyncio.sleep(1.5 * (attempt + 1))
    if FF:  # trim leading/trailing silence so clips join smoothly
        r = subprocess.run([FF, "-y", "-loglevel", "error", "-i", str(raw), "-af", TRIM, str(out)])
        if r.returncode == 0:
            raw.unlink(missing_ok=True)
            return
    raw.replace(out)

async def main():
    sem = asyncio.Semaphore(4)
    jobs = [one(lang, cid, t[lang], sem) for cid, t in MANIFEST.items() for lang in ("ar", "en")]
    await asyncio.gather(*jobs)
    print("voice pack ready")

asyncio.run(main())
