# StreetWalk · 原型演示视频剧本（v4，10-18，按 App 实际功能核对过）

> v4 改动（用户 10-18 意见）：产品名一律 StreetWalk（App 英文界面亦改返）；碰一碰改成两部手机同时出现、跟住距离一齐靠近；
> 每个操作画手指点击；开头改成连续镜头（楼起 → 跟住迷路长者 → 横移到日间冇人），段落之间唔用渐变。
> 成片：video/out/streetwalk_demo_2min.mp4（合成代码 video/src/demo2/Demo2.tsx）。

## 定位
- **一条 2:00 的英文视频**：10/18 随 deck 交，作为原型证明（评分里 Prototype/demo 占 20%）；10/24 决赛路演中途也放这一条。
- 评委自己看，旁边没人讲解，所以**英文配音讲清楚画面上正在发生什么**，英文字幕全程。
- **界面是主角**：用英文版 App，浅色模式，状态栏统一 9:41。每个功能都拍完整的一来一回（做了什么 → App 回了什么），手机画面占半屏以上。
- 只有一处切成粤语：李伯用粤语讲话约人，配英文字幕。
- **画面上出现的每一句文字，都是 App 里真实有的**（下面引号里的英文就是 App 原文）。

## 故事线（每一段都是上一段的结果）
李伯刚搬进北都的新屋邨，谁都不认识。
**选好自己那栋楼 → 出门散步 → 排行榜上总有同一个名字 → 碰面时手机并排，成了街坊 → 知道她出门了，一句话约她 → 到时候找到对方 → 路上顺便反映问题，汇总给屋邨。**
结尾收回开头：搬进来的时候是陌生人，现在是街坊。

## 节奏

| 段 | 时间 | 内容 | 张力从哪里来 |
|---|---|---|---|
| 1 问题 | 0:00–0:12 | 新屋邨，长者谁都不认识 | 3D 屋邨里一个小人，四周的楼都一样 |
| 2 转折 | 0:12–0:20 | 他们要的是真人，不是陪聊机器人 | 音乐抽空，一句话停一秒 |
| 3 行 | 0:20–0:36 | 你家附近 200 米，出门就记录 | 楼影 2 秒内扫过整条路 |
| 4 碰 | 0:36–0:50 | 排行榜上的名字 → 手机并排成为街坊 | 距离环一路收紧，「Done!」 |
| 5 約 | 0:50–1:12 | 她出门了 → 一句话约她 | 粤语真声；左右分屏，两边同时「All set」 |
| 6 搵 | 1:12–1:28 | 到时候找到对方 | 箭头距离一路变小，音乐越来越密，然后一停 |
| 7 報 | 1:28–1:40 | 路上反映问题 → 月报 | 地图上一个图标 → 一张月报 |
| 8 照顾 | 1:40–1:50 | 为长者设计 | 四个快切，跟着鼓点 |
| 9 收尾 | 1:50–2:00 | 天色暗下来，两个小人并排走 | 场景拉远，音乐收 |

## 分镜和配音
配音约 260 个英文单词（按每秒 2.4 个词计，粤语那 8 秒不配音），留了换气位。

---

**1 问题 0:00–0:12**
- 画面：全黑，升降机「叮」一声。切 App 的 3D 屋邨，镜头低角度慢慢推进，平台上一个小人，四周的楼都一样。
- 屏幕小字：`70,000 new public flats` / `1 in 4 over 65 by 2031`（右下角写来源：RTHK、规划署推算）。
- 配音：
  > In Hong Kong's Northern Metropolis, seventy thousand new public flats are going up. By 2031, one in four here will be over sixty-five.
  > One elder, moved here from her village, took three months to find her way home.

**2 转折 0:12–0:20**
- 画面：同一个场景，白天，路上空无一人。音乐停。
- 配音：
  > Their children commute far. Over half of older people feel lonely, and they want real people, not chatbots.
- 停 1 秒。片名：App 图标 + `StreetWalk`，小字 `Every walk, a chance to meet a neighbour.` 音乐起。

**3 行 Walk 0:20–0:36**
- 画面 A（0:20）：欢迎页「Welcome to StreetWalk」→「Which block do you live in?」→「Tap the block you live in」，手指点一栋楼 →「Do you live in …?」→「Yes」。场景按真实地图拼出家附近 200 米，「Your home」名牌弹出，镜头推进。
- 配音：
  > Pick your block, and StreetWalk rebuilds the two hundred metres around your home.
- 画面 B（0:26）：出门。今日页主卡变成「Walking」「N min · passed N places」，灵动岛「Walking N min」，场景里小人沿路走，身后留一条轨迹。
  > Step outside, and it starts recording.
- 画面 C（0:30）：**楼影 2 秒内扫过整条路**（用时间面板拖动录下来，剪掉面板只留场景）。接着点一个地标名牌，卡片弹出「Here now:」「Seats here」「Shady now」。
  > It knows which spots are shady right now, and where to sit.

**4 碰 Tap 0:36–0:50**
- 画面 A（0:36）：排行榜页「Ranking」，每行一个网名 + 「N days」，高亮「陳太」那一行。
- 配音：
  > The ranking shows who walks nearby, by nickname only, and how many days in a row.
- 画面 B（0:42）：**两部真机实拍**，暗背景、侧光、手入镜，两部手机并排慢慢靠近。屏幕上距离环一路收紧，「Move closer」→「A bit closer」→「Good! Hold still」→「Done!」「You're now neighbours.」
  > When they meet, they hold their phones side by side. Neighbours are only made in person.

**5 約 Plan 0:50–1:12**
- 画面 A（0:50）：配对后的卡片「Turn on out-and-about alerts?」→ 撳「Turn on」。第二天，横幅弹出「陳太 just went out, probably near Shelter.」，按钮「Invite」。
- 配音：
  > Neighbours can choose to know when the other goes out.
- 画面 B（0:56）：李伯撳橙色「Speak」，**粤语真声**：「聽日三點約陳太去公園行吓。」
  字幕：`"Ask Mrs Chan for a walk tomorrow at three."`
  确认卡弹出：「I heard: “…”」「Walk with 陳太 tomorrow 3 pm」「Place: …」+ 理由「Shaded by buildings then, seats here, about N minutes' walk for both」。李伯撳「OK」。
- 配音（1:04 接上）：
  > One sentence is enough. A language model understands it, and the app picks a spot with shade and seats. Nothing is sent until he says OK.
- 画面 C（1:08）：**左右分屏**，右边是陈太的手机：灵动岛位置长出横幅「李伯 invites you for a walk tomorrow 3 pm at …」→「Have a look」→「OK」。左边李伯收到「陳太 said yes」，两边都是「All set」。
  > Mrs Chan taps OK, and it's set for both.

**6 搵 Find 1:12–1:28**
- 画面 A（1:12）：灵动岛倒数「Meet 陳太 in N min」→「Time to meet 陳太」，第二行「Meet at …」。
- 配音：
  > Half an hour before, the Dynamic Island counts down.
- 画面 B（1:16）：找人页，大箭头 + 「N m」，跟着转身摆动；底部「On my way」→「Almost there」。近距离时箭头变绿「Right in front of you」，音乐越来越密 → 一停：「Found them!」「You met 陳太 at …」。切回 3D 场景，两个小人碰头。
  > If they can't spot each other, an arrow points the way, and ultra-wideband guides the last few metres. Location is shared only while they look for each other.

**7 報 Tell 1:28–1:40**
- 画面 A（1:28）：路上撳「Speak」讲「Too sunny here.」→ 卡片「Noted: Too sunny here」，场景里最近的地标上出现一个图标。
- 画面 B（1:33）：月报「Walking report this month」，「Residents' reports」里「… · Too sunny」「N people reported」「Suggestion: Add shade or plant trees」，底部「Only issues reported by 10+ people · no personal routes」。
- 配音：
  > On the way, residents can report problems, like too much sun. Issues raised by ten or more people go into an anonymous monthly report for the estate.
- 月报画面角落加小字 `Sample data`（演示里其他住户的数据是样本，要标明）。

**8 照顾 Care 1:40–1:50**
- 画面：四个快切，每个约 2 秒，跟着鼓点：
  1. 设置「Text size」由「Normal」拖到「X-Large」，整页一起变大；
  2. 设置「Language」：粵語 → 普通话 → English，同一页文字跟着换；
  3. 讲「I fell」→ 卡片「If you are in danger, call 999 now, or ask someone nearby for help.」；
  4. 晚上的今日页「Walk tips」：「Dark now. Street lights nearby」。
- 配音：
  > Four text sizes, three languages, and a 999 reminder if someone says they've fallen.

**9 收尾 1:50–2:00**
- 画面：3D 场景慢慢拉远，天色暗下来；中间两个小人并排走（李伯和陈太）。
- 配音：
  > Running today on real iPhones, with a real backend. Strangers when they moved in. Neighbours now.
- 定格：`StreetWalk` + `SDG 3 · SDG 11`，音乐收。

---

## 素材清单（按 App 实际情况）

| 段 | 素材 | 怎么录 | 注意 |
|---|---|---|---|
| 1、2、9 | 3D 屋邨推进、拉远、天暗 | 模拟器 `-demo -skipOnboarding -lang en`，`-hour 10` 白天、`-hour 19` 傍晚 | App 没有「楼升起」「路灯一盏盏亮」的动画，不拍这些 |
| 3A | 欢迎页 → 选楼 | 模拟器 `-resetOnboarding -lang en` 手动走一遍 | |
| 3B | 散步中 | 模拟器 Demo 菜单「Go out」 | 自动开始记录只在真机、关演示模式时有；配音这句在真机上成立 |
| 3C | 楼影扫过、地标卡 | Demo 菜单「Time…」拖动，剪掉面板 | 时间面板是演示工具，不当成用户功能讲 |
| 4A | 排行榜 | 模拟器 `-script` 第 4 秒 | 演示模式下页面会写「Demo: …」，录时裁掉或者用真账号录 |
| 4B | 碰一碰 | **两部真机实拍**，手机 60fps | 真机描述文件 10/17 23:18 已过期，要插线重装：`cd ios && ./tools/install_device.sh` |
| 5 | 出门提醒、粤语约人、陈太接受 | **关演示模式、两个真账号**（iPhone 15 + iPhone Air 模拟器）+ 开 `tools/voice_server.sh` | 只有这样才走语言模型理解；演示模式下是手机规则解析，配音里「A language model」就不成立 |
| 6 | 灵动岛倒数、找人 | 真机录屏，人真的走近 | 超宽带「Right in front of you」只有真机有；模拟器版本会显示「Demo: their location is simulated」 |
| 7 | 反映、月报 | 模拟器 `-script` 第 87、92 秒 | 月报只能从 Demo 菜单打开，数据是样本 |
| 8 | 字体、语言、999、夜晚 | 模拟器逐个录 | |
| 全片 | 英文配音 | 真人录，或 TTS 英文声，语速平稳 | |

## 剪辑规则
- 一首音乐贯穿：0:12 抽空，0:20 片名进，1:26「Found them!」重拍，1:50 收。
- 手机画面不要固定在框里不动：跟着操作推近，剪辑点落在 App 有反应的那一帧。
- 字幕居中偏下、字号大；章节名（WALK / TAP / PLAN / FIND / TELL）在每段开头左上角出现 1 秒。
- 画面上不出现「Demo」字样和 Demo 菜单（裁掉），月报标「Sample data」。
- 数字只用有来源的：7 万单位、2031 年 1/4、超过一半长者孤独。

## 和 App 对不上的地方（录之前要决定）
1. **英文界面里邻居名仍是中文**：「陳太」「李伯」。配音和字幕讲 Mrs Chan / Uncle Lee，画面显示「陳太」。评委能看懂，可以不改。
2. **确认卡语音说「say "yes" or tap Yes」，按钮其实写「OK」**。英文版录音时会听到对不上，录这段时把 App 音量压低，或者先改一句文案。
