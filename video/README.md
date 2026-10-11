# 街坊行宣传片（英文讲解，约 3 分钟）

Remotion 工程。画面 = App 真录屏（iPhone Air 模拟器）放进手机外框 + 纸雕风动态排版；旁白由本机 Kokoro 开源声音生成；配乐和转场音效由脚本合成（无版权问题）。

## 重做一遍
1. 录素材（关掉其他模拟器）：`video/footage/record_all.sh [段名…]` → `footage/raw/`
2. 转码 + 对时间：`python3 footage/prep.py [段名…]` → `public/clips/*.mp4`、`src/clips.json`、`footage/sheets/*.jpg`（每秒一格的缩略图，用来定标注位置）
3. 旁白：讲稿在 `narration/script.json`。
   `VIRTUAL_ENV=~/Desktop/HACK/voice-runtime/kokoro-venv PATH=$VIRTUAL_ENV/bin:$PATH python narration/tts.py all`
   → `public/vo/*.wav`、`src/vo.json`（每句时长，决定每段长度）。换声音：`--voice bf_emma` 等；只重做一句：`tts.py one f_bump`
4. 配乐：`python narration/music.py <秒数>` → `public/music.wav`、`public/swish.wav`
5. 检查：`TL=$(npx tsx tools/tl.ts) node tools/stills.mjs` → `out/stills/`（每段 35% / 80% 各一张）
6. 渲染：`npx remotion render src/index.ts Pitch out/streetwalk_pitch_en.mp4 --crf=18`

## 结构
- `src/tokens.ts` 颜色字体（取自 App）；`src/timeline.ts` 由旁白时长排时间轴
- `src/scenes/Opening.tsx` 开场 / 问题 / 洞察；`Features.tsx` 十个功能（录屏片段秒数 + 标注）；`Bump.tsx` 碰一碰；`Ending.tsx` 隐私 / 真功能 / 收尾
- `review/index.html` 给组员的意见收集页（发布为 Artifact）
