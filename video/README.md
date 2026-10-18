# StreetWalk promotional video (English narration, about three minutes)

Historical Remotion project, retained only on this older branch; video production was removed from main in `f8d63c9`. It combines app recordings from the iPhone Air simulator with a phone frame and paper-style motion graphics. Local Kokoro speech generates narration, and scripts synthesize music and transition effects. Those implementation choices alone do not establish copyright clearance for every asset or voice. Original recordings, bilingual captions, and narration data remain unchanged by the English documentation review.

## Reproduce the historical build

1. Close other simulators and record footage: `video/footage/record_all.sh [segment ...]` → `footage/raw/`.
2. From `video/`, transcode and align timing: `python3 footage/prep.py [segment ...]` → `public/clips/*.mp4`, `src/clips.json`, and one-thumbnail-per-second contact sheets in `footage/sheets/*.jpg` for positioning labels.
3. Narration uses `narration/script.json`:
   `VIRTUAL_ENV=~/Desktop/HACK/voice-runtime/kokoro-venv PATH=$VIRTUAL_ENV/bin:$PATH python narration/tts.py all`
   → `public/vo/*.wav` and `src/vo.json`; utterance durations determine scene lengths. Select another voice with `--voice bf_emma`, or regenerate one utterance with `tts.py one f_bump`.
4. Music: `python narration/music.py <seconds>` → `public/music.wav` and `public/swish.wav`.
5. Preview: `TL=$(npx tsx tools/tl.ts) node tools/stills.mjs` → `out/stills/`, at 35% and 80% of each scene.
6. Render: `npx remotion render src/index.ts Pitch out/streetwalk_pitch_en.mp4 --crf=18`.

## Structure

- `src/tokens.ts`: app-derived colors and fonts. `src/timeline.ts`: a timeline based on narration durations.
- `src/scenes/Opening.tsx`: opening, problem, and insight. `Features.tsx`: ten features, clip timing, and annotations. `Bump.tsx`: pairing. `Ending.tsx`: historical privacy statements, implementation, and closing.
- `review/index.html`: the historical team-feedback page intended for an Artifact. This translation does not publish or submit feedback.

The video contains earlier claims and UI. Current product scope, consent boundaries, and evidence limits are documented on main; translating this guide does not update the original video.
