# 街坊行语音播报：怎样选更自然的粤语、普通话和英语声音

调研日期：2026-10-09。正文用以下标记区分证据来源：

- **【官方】**：厂商文档、价格页、Apple 官方声音目录
- **【社区】**：媒体评测、论坛、开源项目、第三方排行榜
- **【实测】**：我们在 iOS 26.4、26.5 模拟器和 Mac 上测的。**没有在真 iPhone 11 上测过**
- **【推断】**：有一些依据，但没有直接证据
- **⚠️**：不确定，或者被核实推翻、已经更正

---

## 一、结论

### 1. 现在听起来僵，最可能的原因

App 现在用的是 iPhone 自带的最低一档粤语声音，Apple 内部叫 super-compact「善怡 Sinji」，文件只有 3.2MB。

- 【实测】App 代码里写的是 `AVSpeechSynthesisVoice(language: "zh-HK")`。在 iOS 26 模拟器上，这样拿到的就是这个最低档声音。
- 【官方】Apple 对这一档的说明是 "A basic quality voice that's available on the device by default"（[文档](https://developer.apple.com/documentation/avfaudio/avspeechsynthesisvoicequality)）。
- 【推断】僵主要是因为档位低。这一点还没有在真机上和高档声音对比试听过。

另外说明一下：iPhone App 不能像安卓那样装社区做的"语音包"。iPhone 上能免费换的只有 Apple 自己提供下载的声音；更自然的声音基本都是云端 AI 声音。

### 2. 每种语言最自然的 1–2 个选择

> **前提：粤语目前没有任何公认的"最自然"排行榜。** 第三方排行榜 Artificial Analysis 的 10 个语言榜里没有粤语，TTS Arena 只测英语，数码港和保诚的粤语语音基准（2026.1 版）语音合成项目参赛数为 0（[来源](https://ai-challenge.pubrio.com/)，调研阶段看到，未二次核实）。所以下面的粤语推荐只是"最值得试听的候选"，最后要用 App 自己的句子请长者盲听来决定。

| 语言 | 证据最多的候选（云端） | 不用账号、手机本机就能用 |
|---|---|---|
| **粤语** | ① **Google Chirp 3 HD**（yue-HK，有 30 把声，⚠️ 仍是预览版）<br>② **MiniMax Speech 2.8**（Cantonese_KindWoman / GentleLady 等）。香港媒体口碑最好，但不是盲测 | Apple 的高档粤语声音：善怡高品质版、Wing（女）、Fung（男）。⚠️ 目前没有任何人评过它们的音质 |
| **普通话** | 按榜单：Inworld TTS-2 第一（二手报道）；2025 年一项学术测试里，豆包 Seed-TTS 和 MiniMax 最像真人。**对我们最实际的做法**：和粤语用同一家（Chirp 3 HD 或 MiniMax） | Apple 高品质 Lilian / Yue / Yun / Han |
| **英语** | **ElevenLabs Eleven v4 / v4 Turbo**，英语榜并列第一 | Apple **Ava**（高品质，有社区推荐），或英式 Serena / Malcolm |

### 3. App 的推荐组合

1. **底座，马上就能做，不用任何账号**：声音开关、语言切换、自动挑手机里最好的系统声音、引导用户下载高品质声音、语速三档。离线可用，隐私最好。
2. **决赛演示要有人味（推荐）**：开发阶段用云端 AI 声音把 App 要说的句子**预先生成录音，打包进 App**。播报时有对应录音就播录音，没有就退回系统声音。首选 Google Chirp 3 HD，和 MiniMax 盲听比较后再定。
3. **正式上线再考虑**：实时云端合成（需要自建中转服务器保护密钥），或者手机本机跑的开源模型。现在都不建议做。

**为什么这样组合：**

- 粤语哪个最自然，目前没有硬证据。预生成录音可以让我们**先听再选**；以后换厂商，只要重新生成一次录音，App 本身不用改。
- 预生成录音不需要在 App 里放密钥，不需要网络，播放没有等待。发到云端的只有演示句子（示范街坊），真实街坊资料不会离开手机。
- 普通话直接播录音，还能绕开 iOS「普通话被读成粤语」的已知问题（见第三节）。
- 这个做法符合我们"单机演示"的决定。系统声音做底座，保证任何句子都能读出来。

---

## 二、对比表

| 方案 | 粤语声音 | 普通话声音 | 英语声音 | 自然度证据 | 本机还是云端 | 要不要账号或密钥 | 费用 | 隐私 | 接入难度 |
|---|---|---|---|---|---|---|---|---|---|
| **A. Apple 默认声音（现状）** | 善怡，最低档 | 婷婷，最低档 | Samantha，最低档（没有香港英语，会自动换成美式） | 【官方】Apple 称"basic quality"<br>【社区】CoMaps 称默认声音"robotic" | 本机，离线 | 不用 | 免费 | 最好，不联网【推断】 | 已接入 |
| **B. Apple 高档声音（增强 / 高品质）** | 善怡（增强、高品质）、Wing 女（高品质）、Fung 男（高品质）、Aasing 男（增强） | Lilian、Lili、Yue、Yun（女）、Han（男），高品质 | Ava、Zoe（美式）、Serena、Malcolm（英式），高品质 | ⚠️ 粤语：找不到任何评价<br>【社区】AppleVis 有用户认为中文"没有真正高清版"<br>【社区】英语方面 CoMaps 推荐 Ava | 本机，离线。要用户自己去「设置」下载（粤语每把约 10–47MB） | 不用 | 免费 | 最好【推断】 | 低（要做引导页） |
| **C. Google Chirp 3 HD** | yue-HK 30 把（如 Kore、Aoede、Leda），⚠️ 预览版 | cmn-CN 同名 30 把（正式版） | en-US 同名 30 把 | ⚠️ 没有独立的粤语盲测<br>英语榜 1059 分，中游 | 云端。生成后可以存成录音，离线播放 | 要 Google Cloud 账号并开通付费 | 每月前 100 万字符免费，超出后每 100 万字符 30 美元 | 【官方】不记录文本和音频 | 中 |
| **D. MiniMax Speech 2.8** | 6 把以上，如 KindWoman、GentleLady | 很多，如 Warm-hearted Aunt | 很多 | 【社区】香港 PCM 评价「相當自然」（非盲测）<br>英语榜 1174 分<br>2025 年普通话"像真人"测试第 2 | 云端 | 账号加密钥 | Turbo 每 100 万字符 60 美元，HD 100 美元（⚠️ 汉字可能按 2 个字符计） | 【官方条款】可以用输入内容改进服务，数据存在美国 | 中，可以用粤拼纠正读音 |
| **E. ElevenLabs v4 / v4 Turbo** | 2026-09-28 起支持粤语，没有现成的粤语声音 | 支持 | 支持 | 英语榜并列第一（1329 / 1326 分）<br>⚠️ 粤语没有任何独立评测 | 云端 | 账号加密钥，商用要付费计划 | v4 每 100 万字符 80 美元，Turbo 40 美元；Starter 计划每月 6 美元起 | 【官方】默认会保留输入和输出 | 中，没有语速滑块 |
| **F. Azure 神经语音** | HiuGaai、HiuMaan（女）、WanLung（男），只有标准档 | 很多 HD 声音 | 很多 HD 声音 | 【学术】唯一一项粤语母语者盲听：读得清楚，口音地道度 3.48/5，作者推测"偏机械" | 云端，可以选香港机房 | 账号加密钥 | 每 100 万字符 15 美元；免费层每月 50 万字符（每分钟最多 20 次请求） | 【官方】实时合成不保存文本和音频 | 中，有 iOS SDK |
| **G. 阿里 Qwen3-TTS-Flash（国际站新加坡）** | Kiki（女）、Rocky（男）。⚠️ 新加坡可用是按文档推断 | 很多 | 很多 | ⚠️ 没有粤语评价 | 云端 | 账号加密钥 | 约每 100 万字符 10 美元 | 数据在新加坡；保留政策没查到 | 中 |
| **H. Amazon Polly** | 只有 Hiujin（女） | 只有 Zhiyu | 很多 | 英语神经声音榜单 895 分，偏低；粤语没有评价 | 云端。【官方】明确允许缓存后重复播放 | 账号加密钥 | 每 100 万字符 16 美元；头 12 个月每月 100 万字符免费 | 【官方】可能用来改进服务，可以申请退出 | 中 |
| **I. 开源本机模型：sherpa-onnx 粤语模型** | 1 把（2023 年社区训练） | 可以搭配 Kokoro、Piper 等 | 可以搭配 Kokoro 等 | ⚠️ 没有评测，没有许可证；2025-09 修过句尾怪音 | 本机，离线（模型 114MB） | 不用 | 免费；⚠️ 粤语模型能否商用不明 | 最好 | 中偏高 |
| **J. 开源本机模型：Kokoro-82M** | 不支持 | v1.0 官方自评全部 D 级 | af_heart 官方自评 A 级；英语榜 1065 分 | 同左 | 本机，离线（约 80–170MB） | 不用 | Apache-2.0，可以商用 | 最好 | 中；⚠️ iPhone 11 没测过速度 |
| **K. 开源大模型自建：CosyVoice2-Yue / VoxCPM2** | CosyVoice2-Yue 在论文作者自评里分数最高；VoxCPM2 声称支持粤语 | 支持 | 支持 | 【学术，作者自评】CosyVoice2-Yue 可懂度 4.45、口音 4.21；VoxCPM2 没有粤语评测 | 只能在显卡服务器或电脑上跑，手机跑不动 | 自己搭服务器 | 显卡成本；⚠️ CosyVoice2-Yue 的训练数据只许非商用 | 自建的话最好 | 高 |

> 「英语榜」指 [Artificial Analysis 语音竞技场](https://artificialanalysis.ai/text-to-speech/leaderboard)，测的是美式和英式英语，**不能代表粤语**。

**表格来源：**

- **A、B**：[Apple 官方声音目录](https://mesu.apple.com/assets/com_apple_MobileAsset_TTSAXResourceModelAssets/com_apple_MobileAsset_TTSAXResourceModelAssets.xml)、[CoMaps 2026-08](https://www.comaps.app/news/ios-hq-voices/)、[AppleVis 主帖](https://mail.applevis.com/forum/ios-ipados/ios-chinese-tts-voice-quality-very-poor)
- **C**：[Chirp 3 HD 文档](https://docs.cloud.google.com/text-to-speech/docs/chirp3-hd)、[声音列表](https://docs.cloud.google.com/text-to-speech/docs/list-voices-and-types)、[价格](https://cloud.google.com/text-to-speech/pricing)、[不记录日志的声明](https://docs.cloud.google.com/text-to-speech/docs/data-logging)
- **D**：[PCM 评测](https://www.pcmarket.com.hk/minimax-free-cantonese-ai-voice-actor/)、[声音列表](https://platform.minimax.io/docs/faq/system-voice-id)、[价格](https://platform.minimax.io/docs/guides/pricing-paygo.md)、[服务条款](https://platform.minimax.io/docs/guides/terms-of-service.md)、[隐私政策](https://platform.minimax.io/docs/guides/privacy-policy.md)、[普通话"像真人"测试论文](https://arxiv.org/html/2505.11200v1)
- **E**：[模型与语言](https://elevenlabs.io/docs/overview/models)、[v4 功能说明](https://elevenlabs.io/docs/overview/capabilities/text-to-speech/eleven-v4)、[价格](https://elevenlabs.io/pricing/api)、[数据保留](https://elevenlabs.io/docs/resources/zero-retention-mode)、[免费计划限制](https://elevenlabs.io/docs/overview/administration/billing)
- **F**：[语言支持](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-support?tabs=tts)、[隐私](https://learn.microsoft.com/en-us/azure/ai-foundry/responsible-ai/speech-service/text-to-speech/data-privacy-security)、[配额](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/speech-services-quotas-and-limits)、[WenetSpeech-Yue 论文表 5](https://arxiv.org/html/2509.03959v2)
- **G**：[Qwen 声音列表](https://www.alibabacloud.com/help/en/model-studio/qwen-tts-voice-list)、[区域](https://www.alibabacloud.com/help/en/model-studio/qwen-tts)
- **H**：[声音列表](https://docs.aws.amazon.com/polly/latest/dg/available-voices.html)、[FAQ](https://aws.amazon.com/polly/faqs/)、[价格](https://aws.amazon.com/polly/pricing/)
- **I**：[sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)、[粤语模型](https://huggingface.co/csukuangfj/vits-cantonese-hf-xiaomaiiwn)、[句尾修复 PR #2558](https://github.com/k2-fsa/sherpa-onnx/pull/2558)
- **J**：[Kokoro 官方声音评级](https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md)、[iPhone 12 Pro 第三方测速](https://huggingface.co/mattmireles/kokoro-coreml)
- **K**：[CosyVoice2-Yue](https://huggingface.co/ASLP-lab/Cosyvoice2-Yue)、[训练数据许可](https://huggingface.co/datasets/ASLP-lab/WenetSpeech-Yue)、[VoxCPM2](https://huggingface.co/openbmb/VoxCPM2)

**已排除的选项：**

- **Siri 的声音**：【官方】WWDC20 明确说，第三方 App 用 AVSpeechSynthesizer 用不了 Siri 声音（[WWDC20 10022](https://developer.apple.com/videos/play/wwdc2020/10022/)）。没有发现 iOS 26 或 27 开放的证据。
- **个人声音（Personal Voice）**：【官方】只支持美式英语、普通话和墨西哥西班牙语，而且要 iPhone 12 或更新的机型（[功能可用性页](https://www.apple.com/ios/feature-availability/#accessibility-personal-voice)、[支持文档](https://support.apple.com/en-us/104993)）。它是用户自己录出来的声音，本来也不适合当播报员。
- **OpenAI**：【官方】官方语言列表没有粤语，香港也不在 API 支持地区里（[TTS 文档](https://developers.openai.com/api/docs/guides/text-to-speech)、[支持地区](https://developers.openai.com/api/docs/supported-countries)）。
- **Google Gemini TTS**：【官方】Gemini API 支持地区列表里没有香港（[地区列表](https://ai.google.dev/gemini-api/docs/available-regions)）。
- **字节 BytePlus、科大讯飞**：粤语各只有一把声，没有找到评价，香港能否开户也不确定。
- **Inworld、Cartesia**：普通话榜单排在前面，但粤语要么是实验性的，要么不支持。

---

## 三、对长者的考虑

### 语速

- 现在 App 设的是 0.42，比系统默认的 0.5 慢一点。
- 【实测】在模拟器里读同一句「8 樓陳太啱啱出門，應該喺公園櫈仔嗰邊」：0.5 用 4.25 秒，0.4 用 4.68 秒（只慢约 10%），0.3 用 5.53 秒（慢约 30%）。
- **建议**：设「正常 / 慢 / 再慢啲」三档，默认用「慢」，具体数值请长者试听后定。
- 云端方面：
  - Chirp 3 HD 的语速控制对粤语可用（【官方】）。
  - MiniMax 和 Azure 都能调语速（【官方】）。
  - ElevenLabs v4 没有语速滑块，只能在文字里加 [slowly] 这类标签，效果是大致的（[官方博客](https://elevenlabs.io/blog/elevenlabs-audio-tags-list)）。
- 预生成录音可以直接按选好的语速生成。

### 清晰

- **停顿**：长句按逗号拆开，中间停一下。系统声音可以拆成几段来读。Chirp 3 HD 的粤语不支持插入停顿标记，但官方写稿指南说逗号、句号、省略号本身就会产生停顿（【官方】）。
- **重点试听的字**：咗、喺、嗰、櫈、下晝这类口语字，有没有被读成普通话音；「8 樓」「三點」这类数字怎么读；中英夹杂的词怎么读。
  - 读错时，MiniMax 可以用粤拼纠正（【官方】）。Chirp 3 HD 的粤语**不支持自定义读音**（【官方】），只能改写原文，比如把「8 樓」写成「八樓」。
- **配套设计**（我们的建议，没有外部证据）：屏幕上同时显示同一句文字；加一个大的「再講一次」按钮。
- **音量**：现在代码播报时会压低其他 App 的声音，这个保留。2022 年有用户反映 iOS 16 新加的中文声音音量偏小（[AppleVis](https://mail.applevis.com/comment/142091)），真机试听时要留意。

### 离线可用

- 街坊行主要在户外散步时用，长者不一定开着流动数据。
- 系统声音和预生成录音都能完全离线。实时云端合成不行。这是底座选系统声音、演示选预生成录音的主要原因。

### 隐私

- 播报里有邻居姓名、楼层和去向（「8 樓陳太啱啱出門」），属于个人资料。
- 预生成方案只把演示句子（示范街坊）发到云端，真实资料不出手机。
- 如果以后做实时云端合成，真实资料会上传：
  - Google 和 Azure 官方声明不记录（【官方】），是相对好的选择。
  - MiniMax 条款允许用输入改进服务，数据存在美国（【官方】）。
  - ElevenLabs 默认保留数据（【官方】）。
  - 上线前需要告诉用户并取得同意，具体合规要求我们没有查，建议咨询。

### 下载高品质声音的门槛

- App 不能替用户下载，也没有办法一键跳到下载页（【官方】，见第四节）。
- 长者自己操作有难度。建议做一张有截图的步骤卡，并在社区中心或者由家人、社工帮忙设置一次。

### 声音开关和静音键（需要你拍板）

- 现在的代码设置是：手机侧边静音键打开时，App 照样出声。这是 Apple「playback」音频类别的设计，建议真机确认。
- 对长者来说，误开静音键后仍能听到提示，可能是好事。
- **建议**：以 App 里的「語音播報」开关为准；主界面放一个喇叭按钮，可以一键静音。

### 语言切换要准备三套文字

- 粤语口语句子（「啱啱」「喺」「嗰邊」）不能直接交给普通话或英语声音读，否则会很怪。
- 每句播报都要有粤、普、英三个版本。这需要和组员 B 的模板文案一起准备。

### 已知风险：普通话被读成粤语

- 【社区，开发者论坛多份报告】iOS 18 到 26 上，如果 Siri 语言或「朗读设置」里的中文口语语言设成了粤语，就算 App 指定了普通话声音，也会读成粤语。
- 有人在 2026-03 报告 iOS 26.2.1 上仍然存在。Apple 只请开发者提交问题报告，没有给出解决办法。
- 据报告，这个问题主要出现在从旧版本升级、或者从备份恢复的手机上。
- 有间接迹象显示，用声音编号（identifier）指定声音也绕不过去，但没有人验证过。
- 很多香港长者会把 Siri 设成粤语，所以这是普通话切换的直接风险。**用预生成录音可以完全避开。**
- 来源：[772348](https://developer.apple.com/forums/thread/772348)、[788218](https://developer.apple.com/forums/thread/788218)、[792744](https://developer.apple.com/forums/thread/792744)、[801554](https://developer.apple.com/forums/thread/801554)

---

## 四、分档实现方案

### 第一档：不用账号，马上能做（估计 1–2 天开发，加真机测试）

**做什么：**

1. **设置页新增「聲音」区**：
   - 語音播報：開 / 關。关闭时立即停止正在读的句子，文字照常显示。
   - 播報語言：粵語 / 普通話 / English。
   - 聲音：列出手机里已经装好的声音，标注「高品質 / 增強 / 標準」，每把声音都有「試聽」按钮。
   - 語速：三档。
2. **自动挑最好的声音**：
   - 用户选过的声音优先；没选过，就按高品质、增强、标准的顺序选。
   - 不再用现在这种只写语言代码的方式。iOS 26 上它拿到的是最低档；还有开发者报告它不跟随用户的选择，不过 Apple 没能复现（[804648](https://developer.apple.com/forums/thread/804648)）。
   - 【实测】iOS 26 上粤语声音的语言代码显示为 "yue-HK"，不是 "zh-HK"，筛选声音时要两个都认。
3. **引导下载高品质声音**：
   - 如果某种语言只有标准档，就显示提示卡，写清楚路径：
     - iOS 26（香港繁中界面）：**設定 > 輔助使用 > 閲讀與朗讀 > 聲音**，再进入中文（香港）（[Apple 说明](https://support.apple.com/zh-hk/guide/iphone/iph96b214f0/26.0/ios/26.0)）。
     - iOS 18：**設定 > 輔助使用 > 語音內容 > 聲音**（[Apple 说明](https://support.apple.com/zh-hk/guide/iphone/iph96b214f0/18.0/ios/18.0)）。
   - 用户回到 App 时自动重新检查有没有装好。

**做不到的事：**

- 【官方】App 不能触发下载，也查不到"能下载但还没装"的声音。API 里根本没有这种功能（[AVSpeechSynthesisVoice 文档](https://developer.apple.com/documentation/avfaudio/avspeechsynthesisvoice)）。
- 【官方】没有能直接跳到「聲音」页面的公开链接。可以直接打开的辅助功能设置项一共只有 6 个，都和朗读无关（[文档](https://developer.apple.com/documentation/accessibility/accessibilitysettings/feature)）。
- 用私有链接有被 App Store 拒审的风险（[DTS 回复](https://developer.apple.com/forums/thread/691712)）。

**取舍：**

- 优点：免费、离线、隐私最好，iPhone 11 能跑。高品质粤语声音只有约 47MB，内存峰值低于 80MB（【官方目录】）。
- 缺点：**高品质粤语声音会不会明显不僵，没有任何证据。** 粤语高品质包约 46MB，英语 Ava 是 280MB，体量差一个数量级；这只说明体积差别，不能直接推出音质。所以第一档解决"可以切换、可以关"，但不保证解决"有人味"。

### 第二档：开发团队注册云服务（推荐用于决赛演示）

**2A：预生成录音，推荐现在做（估计 2–3 天）**

1. 列出演示中会说的所有句子，粤、普、英各一版。因为街坊、时间、地点都来自演示数据，数量有限。
2. **盲听**：
   - 候选：Chirp 3 HD 三把（如 Kore、Aoede、Leda）、MiniMax 两把（KindWoman、GentleLady），再加 Apple 高品质善怡作为对照；可以选加 ElevenLabs v4。
   - 请 3–5 位长者或母语者给每把声音打 1–5 分，看清楚程度、语速和亲切感。
3. 用得分最高的声音批量生成录音，打包进 App。估算几十 MB 以内。
4. App 播报时先找有没有对应的录音，找不到就用系统声音读。

**为什么首选 Chirp 3 HD：**

- 粤、普、英都有同名的 30 把声。
- 每月前 100 万字符免费。演示句子按 300 句 × 30 字 × 3 种语言估算，约 2.7 万字，远低于免费额度。
- 官方声明不记录文本（【官方】）。

**为什么 MiniMax 是对照组：** 香港媒体口碑最好，还能用粤拼纠正读音；同样字数大约只要几美元。

**要注意：**

- ⚠️ Chirp 3 HD 的粤语仍是预览版。Google 对预览版的定位是测试用途，没有服务保证（[服务条款](https://cloud.google.com/terms/service-terms)）。
- ⚠️ 官方没有说同名声音在三种语言里是同一个人的音色，要自己听。
- ⚠️ 从香港能否开通使用 Google Cloud TTS，没有官方说明。有一个香港开发者的开源项目在用（[cantonese-dubbing-desk](https://raw.githubusercontent.com/wongsir1011/cantonese-dubbing-desk/main/README.md)），要用香港网络实测。
- ⚠️ Google 和 MiniMax 生成的录音能否打包商用，我们没有逐条读服务条款。Amazon Polly 官方明确允许缓存后重复播放。
- 如果组员 B 的 AI 会在运行时生成新句子，这些句子没有预先录好，会退回系统声音读。
- 演示时可以如实标注「演示語音由 AI 預先生成」。

**另一种做法：真人录音。** 最有人味的其实是请一位街坊或社工把固定句子录下来，长者还会觉得声音熟悉。缺点是姓名、时间这些会变化的内容不好处理。这是我们的建议，没有外部证据。

**2B：实时云端合成（等正式上线时再考虑）**

- 适合在运行时生成新句子的情况。
- 服务选择：
  - Google Chirp 3 HD：每月前 100 万字符免费，不记录。
  - Azure：免费层每月 50 万字符，可以选香港机房，不保存；但粤语只有旧一代标准声音，而且免费层每分钟最多 20 次请求。
- 密钥不能写进 App。要自建一个小中转服务器，这和"单机演示"的决定冲突。
- 内部演示可以临时让用户在设置里输入自己的密钥，但不能用在公开发布的版本。
- 每句合成后存在手机上，重复播放时不再收费，也能离线。

### 第三档：开源模型在手机本机运行（现在不建议）

- **粤语**：
  - 能在手机离线跑的，只有 sherpa-onnx 的一个粤语模型：114MB，单一声音，2023 年的技术，**没有评测，没有许可证**。有没有比 Apple 高品质声音好，只能自己听（试听：[k2-fsa Space](https://huggingface.co/spaces/k2-fsa/text-to-speech)）。
  - canto-tts-nano：ONNX 文件约 764MB，只有 Python 版，要移植到 iOS，不现实。
- **英语**：Kokoro-82M 可以商用（Apache-2.0），官方自评 af_heart 是 A 级。
  - 第三方在 iPhone 12 Pro 上测到生成 3 秒音频约 1.4 秒（不含前处理）。⚠️ iPhone 11 没有测过。
  - 官方提醒，少于 10–20 个词元的短句效果偏弱，而我们的提示正好很短。
  - 和 Apple Ava 高品质比好多少，没有证据。
- **普通话**：Kokoro v1.0 的普通话声音官方自评全部 D 级。
- **大模型**（CosyVoice2-Yue、VoxCPM2 等）手机跑不动。
  - 只能在显卡服务器或电脑上**预先批量生成**，等于第二档 2A 的"不用云账号"版本。
  - CosyVoice2-Yue 的训练数据只许非商用。VoxCPM2 是 Apache-2.0，但没有粤语评测。
- **结论**：投入大、证据少，演示阶段不做。

---

## 五、被核实推翻或要更正的说法，以及仍不确定的地方

### 已更正

1. ⚠️ **iOS 26 的菜单名**：调研里写的「朗读与说话」是错的。正确名称是「阅读与朗读」（简体）/「閲讀與朗讀」（香港），英文 Read & Speak（[Apple 说明](https://support.apple.com/zh-cn/guide/iphone/iph96b214f0/26.0/ios/26.0)）。
2. ⚠️ **"粤语高品质约 46MB"** 只对新版成立，旧版善怡高品质是 25MB。Wing 和 Fung 只有新版条目。
3. ⚠️ **"只写语言标签、不指定声音时，系统会选普通话婷婷"** 不准确。实际用的是手机默认声音：手机语言是普通话时才是婷婷，是英语时是 Samantha。结论不变：一定要明确指定声音。
4. ⚠️ **"iOS 26 按语言取声音有回归"**（FB20271264）只是开发者自己报告的，Apple 工程师表示无法复现（[804648](https://developer.apple.com/forums/thread/804648)）。
5. ⚠️ **"WWDC20 说 Siri 声音不在可用声音列表里"**：WWDC20 只说第三方 API 用不了 Siri 声音，"不在列表里"来自 2021 年的社区帖子。"社区公认 Siri 粤语更自然"也没有找到依据。
6. ⚠️ **"Lilian 音量偏小"**：原帖说的是 iOS 16 新加的中文声音整体偏小，不是专指 Lilian。Lilian 漏读句尾字是真的，但那是 2022 年的版本，现在的版本是否修好不确定。
7. ⚠️ **"Azure 的 HD 声音只有普通话和英语"** 是错的。很多语言都有 HD 声音，只有其中 HD Flash 一种限普通话和英语。但**粤语确实没有 HD 声音**这一点成立（[文档](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/high-definition-voices)）。
8. ⚠️ **"论文证明 Azure 粤语就是用户说的那种僵"** 说过头了：
   - 论文测的是 Edge-TTS，我们推断它用的是同一套声音。
   - "偏机械"是作者的推测，论文没有直接测自然度，也没有和 Apple 的声音比较过。
   - 每个分数只来自 10 名评分者、50 个样本，置信区间有重叠。
   - "唯一一项粤语母语者研究"的说法也不成立：至少还有另一项（[arXiv 2206.04922](https://arxiv.org/pdf/2206.04922)）。
9. ⚠️ **"Chirp 3 HD 粤语可以用 [pause] 插停顿"** 是错的。【官方】粤语不支持停顿控制，也不支持自定义读音，只能调语速。用标点控制停顿是官方写稿指南里写的方法。
10. ⚠️ **"香港项目 cantonese-dubbing-desk 把 Chirp 3 HD 定为主要粤语引擎"** 是错的。它的默认引擎是 Azure，Chirp 只是可选升级；而且这个项目 0 个星标，社区分量很小。
11. ⚠️ **MiniMax**：
    - PCM 文章提到的是中英夹杂和声调的问题，没有提多音字。
    - 把 language_boost 设为 "Chinese,Yue" 是**官方文档**写的，不是第三方。
    - "香港口碑最好"没有盲测支撑。
    - "没有零保留选项"：官方文档里没找到这个选项，但不能确定一定没有。
12. ⚠️ **ElevenLabs**：
    - 1329 分是 v4 Turbo 的分数，和 v4 的 1326 分在统计上打平。
    - "第一次支持粤语"是我们根据语言列表推断的，官方没有直说。
    - "没法放慢语速"不对：可以用 [slowly] 标签，效果是大致的；也可以在手机播放时调慢。
13. ⚠️ **sherpa-onnx**：官方从 v1.13.5（2026-08-11）就支持 Swift 包管理，不是 v1.13.8。修句尾怪音的是 PR #2558 和 #2559，不是 issue #589。
14. ⚠️ **"Kokoro 比 Chirp 3 HD 好"** 不成立，两者在置信区间内打平。
15. ⚠️ **"Polly 是几家里最低的"** 只是和新一代产品比较；而且这个分数只测英语。
16. ⚠️ **个人声音**：模拟器测试不能证明 iPhone 11 的情况，排除它的依据是 Apple 官方机型列表。

### 仍不确定（需要真机或试听才能回答）

- **Apple 高品质粤语声音**（善怡高品质、Wing、Fung、Aasing）听起来是否明显不僵：没有任何评价。
- **iOS 18 上能不能下载 Wing 和 Fung**：它们只有新版条目。iOS 26 大概率可以（【推断】）。
- **普通话被读成粤语的问题**：iOS 26.3 以后修好没有；用声音编号指定能不能绕过。
- **同一语言能否同时装多把高品质声音**：CoMaps 说只能装一把，未核实。如果属实，Wing 和 Fung 之间切换会受影响。
- **云端粤语自然度**：Chirp 3 HD、MiniMax、ElevenLabs v4 的粤语都没有独立盲测。MiniMax 粤语里混入普通话的问题现在是否还在，也不清楚。
- **云端录音能否打包进 App 商用**：Google 和 MiniMax 的条款没有逐条读过。
- **iPhone 11 的实际速度**：所有本机方案都没有实测，首句要等多久也不知道。
- **从香港能否使用 Google Cloud TTS**：没有官方说明。

---

## 六、建议的下一步（按顺序）

1. **真机试听（半天）**：
   - 在 iPhone 11 上，最好 iOS 18 和 iOS 26 各一台，到设置里下载粤语的善怡高品质、Wing、Fung、Aasing。
   - 用三句真实提示试听，例如「8 樓陳太啱啱出門，應該喺公園櫈仔嗰邊」「幫你約咗陳太聽日下晝三點，喺涼亭附近。等緊陳太確認」，再加一句带英文和数字的。
2. **同一天测普通话问题**：把 Siri 设成粤语，看普通话会不会被读成粤语。
3. **做第一档**：声音开关、语言切换、选择声音并试听、语速三档、下载引导卡。和组员 B 一起准备三种语言的播报文字。
4. **云端试听**：
   - MiniMax 有粤语试用页（[链接](https://www.minimax.io/audio/text-to-speech/cantonese)）。
   - Chirp 3 HD 要注册 Google Cloud 账号后试，我们没有确认有免登录的试听页。
   - 请 3–5 位长者盲听打分。
5. **按盲听结果做第二档 2A**：预生成演示录音，打包进 App，系统声音做后备。
6. **pitch 里如实说明**：演示语音由 AI 预先生成；正式版的上线路径是实时云端合成加隐私保护。