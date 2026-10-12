# 街坊行 · Mac 语音服务器

**2026-10-12 起换成组员 B 新版嗰套（用户：「直接换成 B 的，用它的那套」）**：全部豆包（火山引擎）。

| | 做乜 | 代码 |
|---|---|---|
| 耳 | 豆包流式识别（粤语 / 普通话），手机收音经 Mac 转发；讲完一句自动出字 | B 嘅 `doubao.py`、`realtime.py`；A 嘅 `app_ear.py`（`/v1/voice/ear`） |
| 脑 | B 嘅范围规则（紧急 → 求助提示；医疗 / 投资 / 政治 / 色情 → 拒答）+ 豆包模型判断话题同指令 + 天文台北区天气 + 约人确认卡 | B 嘅 `voice_policy.py`、`weather.py`、`service.py`；A 嘅 `app_policy.py`（`/v1/assistant/turn`） |
| 嘴 | 豆包「小何」粤语声（普通话都得），首段约 0.7 秒出声，服务器同手机都有缓存 | A 嘅 `doubao_speech.py`（同 B 一样嘅请求，交俾原有 `SpeechService`） |

App 嘅「连续对话」（`ios/StreetWalk/Store/AppStore+Conversation.swift`）：撳一下咪就一路倾，讲完唔使撳；助手讲嘢时开口就停（插嘴）；
手机先认 App 自己做嘅指令（找人、改约、取消约、反映、地标改名），其余交 B 嗰套；影响别人嘅动作照旧要撳「好」。
连唔到 Mac → 手机识别（Apple）+ 手机模板（TemplateAI）+ 系统声音，功能唔会少。

**密钥**：B 私下交嘅 `Private/voice-config.json`（豆包语音 Key、方舟 Key、模型、音色）抄去 `~/Desktop/HACK/voice-runtime/doubao.json`（chmod 600），**唔入 git、唔去手机**。

## 每次测试之前（一条命令）

```sh
cd ~/Desktop/HACK/HACK4SDG
tools/voice_server.sh                 # 局域网：同一个 Wi-Fi 嘅 iPhone 自动搵到（Bonjour）
tools/voice_server.sh --tunnel        # 再开 https 公网地址（外出测试，要 brew install cloudflared）
tools/voice_server.sh --voice=sovits  # 播报改返旧嘅 Mac 本机 GPT-SoVITS 声（要下面嘅声音模型）
```

- 即开即用（豆包喺云端，唔使载入模型）。终端印局域网地址；iPhone 搵唔到时：App → 設定 → 聲音 →「語音伺服器」填地址。
- 部 Mac 要开住、唔好合盖；外出用 `--tunnel`，经隧道嘅识别 / 播报 / 助手都要 App 登录。
- `--verbose`：日志印埋合成嘅句子；`--test`：只跑服务器测试（107 项）。Ctrl-C 停。
- 模拟器测连续对话（唔使讲嘢）：`-debugCommands -earFeed a.wav,b.wav [-earGap 秒]`（16 kHz 单声道 WAV 当系用户讲），再写 `mic` 入 Documents/debug-commands.txt。

### 实测（2026-10-12，这台 Mac）

| | 时间 |
|---|---|
| 识别：讲完到出整句 | 约 1.2–1.6 秒（豆包判停 1.2 秒） |
| 理解（豆包模型） | 约 3–4 秒，偶然 > 12 秒（App 12 秒后用返手机模板） |
| 天气（加天文台） | 约 3.5–4 秒 |
| 播报首段 | 0.6–1 秒；播过嘅即刻 |

已知：豆包「二遍识别」对好短嘅句子会乱认（「咁聽日呢」→「帮我导航到大沥公园」），`app_ear.settle()` 发现同边讲边出嘅字对唔上就用后者。

## 旧：GPT-SoVITS 本机声（`--voice=sovits` 先用）

### 第一次安装（模型同 Python 环境放喺仓库外面）

模型约 1.4 GB、Python 环境约 1.1 GB，唔入 git，放 `~/Desktop/HACK/voice-runtime/`（用 `VOICE_RUNTIME=…` 可以改位置）：

```
voice-runtime/
  gptsovits/                 GPT-SoVITS 仓库（commit 1b47ca0）连 GPT_SoVITS/pretrained_models：
                             s1v3.ckpt、v2Pro/s2Gv2ProPlus.pth、chinese-roberta-wwm-ext-large、chinese-hubert-base、
                             sv/pretrained_eres2netv2w24s4ep4.ckpt、fast_langdetect
  ref/cv_yue_f2.wav + .txt   参考录音（CC0，Common Voice 粤语 common_voice_yue_31206624）同佢嘅文字
  venv/                      Python 3.10（uv 建）
  requirements.lock.txt      venv 嘅确切版本（torch 2.6.0、transformers 4.57.6、fastapi 0.143.0 …）
  nltk_data/                 英文字典（cmudict、averaged_perceptron_tagger(_eng)）：句子有英文字（例如英文网名）先用到
  data/                      运行时产生：assistant.sqlite3（B 嘅对话 / 确认卡 / 回执）、tts-cache/（合成过嘅 WAV）
```

2026-10-11 由 `/private/tmp/…/scratchpad/tts_oss/` 复制过嚟（/private/tmp 重启会清走）。由零开始重建：

```sh
RT=~/Desktop/HACK/voice-runtime
git clone https://github.com/RVC-Boss/GPT-SoVITS "$RT/gptsovits" && git -C "$RT/gptsovits" checkout 1b47ca0
# 按 GPT-SoVITS README 下载 v2ProPlus 预训练模型到 $RT/gptsovits/GPT_SoVITS/pretrained_models/（上面列嗰几个）
uv venv --python 3.10 "$RT/venv"
uv pip install --python "$RT/venv/bin/python" -r "$RT/requirements.lock.txt"
# 英文字典（nltk 自带下载器喺有代理嘅网络会拒绝，直接由 nltk_data 官方仓库攞）：
mkdir -p "$RT/nltk_data/corpora" "$RT/nltk_data/taggers"
curl -L -o "$RT/nltk_data/corpora/cmudict.zip" https://raw.githubusercontent.com/nltk/nltk_data/gh-pages/packages/corpora/cmudict.zip
curl -L -o "$RT/nltk_data/taggers/averaged_perceptron_tagger_eng.zip" https://raw.githubusercontent.com/nltk/nltk_data/gh-pages/packages/taggers/averaged_perceptron_tagger_eng.zip
(cd "$RT/nltk_data/corpora" && unzip -o cmudict.zip); (cd "$RT/nltk_data/taggers" && unzip -o averaged_perceptron_tagger_eng.zip)
# 参考录音：Common Voice 粤语（CC0）common_voice_yue_31206624.mp3 → 转 wav 放 $RT/ref/cv_yue_f2.wav，文字放 cv_yue_f2.txt
```

## 速度（M1 Pro、CPU、2026-10-11 实测；当时部 Mac 同时跑紧其他模拟器同 Unity，负载 15–20）

| 情况 | 第一段声音 | 备注 |
|---|---|---|
| 新句子（服务器合成，边合成边传） | 2.2–3.6 秒 | 之后大约实时（6 秒声音约 6 秒合成完） |
| 合成过嘅句子（服务器缓存） | 0.03 秒 | App 连上时会叫服务器预先合成常用句子 |
| 手机播过嘅句子（手机缓存） | 即刻 | 离线都得 |
| Mac 闩咗 | 即刻转系统声音 | |
| 服务器太慢（> 6 秒冇声） | 6 秒后转系统声音 | |
| 模型载入（开机） | 约 17 秒 | |

## 接口

B 原有（见 `upstream_b/docs/INTEGRATION.md`）：`/healthz`、`/v1/capabilities`、`/v1/speech/transcribe`（Azure，未配置）、`/v1/speech/synthesize`、`/v1/assistant/turn`、`/v1/conversations/{id}/choice`、`/v1/drafts/{id}/confirm|cancel|reconcile`。

成员 A 加：

| 方法 / 路径 | 用途 |
|---|---|
| `GET /v1/voice` | App 搵服务器用（唔使登录、冇用户资料）：声音版本、模型状态、助手模式 |
| `POST /v1/speech/synthesize` | 加 `speed`（0.7–1.3）同 `prefetch`（只排队合成）。sovits 时返回 `audio/wav`（PCM16 32 kHz 单声道，边合成边传，长度栏 0xFFFFFFFF）；`X-TTS-Cache: hit/miss`。普通话答 503（App 用系统声音） |
| `POST /v1/assistant/context` | App 上传地标、步行分钟、未来三日每半个钟遮荫（**冇坐标**，多咗栏位一律 422） |
| `GET /assistant/session`、`GET /assistant/context?at=`、`POST /assistant/actions`（`Idempotency-Key`）、`GET /assistant/actions/{id}` | B 文档入面「A 必须提供的业务 API」，由本服务用 Supabase 实现（`supabase_business.py`） |

### 身份同权限

- `ASSISTANT_MODE=supabase`：每个请求嘅 `Authorization: Bearer` 系用户喺 App 匿名登录得到嘅 Supabase access token，服务器问 Supabase `GET /auth/v1/user` 核实（结果缓存 60 秒），**唔收客户端自报 id**。之后所有读写都用返用户自己嘅 token 打 Supabase，所以 RLS 照样把关：只可以约互为街坊、只睇到自己嘅约会。
- 播报：局域网直接连入（私有 IP、冇代理头）唔使登录（演示模式、模拟器都用到）；经 `--tunnel` 或任何代理嚟嘅请求一定要登录。
- 约人：`meetups.id = uuid5(用户, 确认卡 id)`，同一张卡点撳都只会有一行；回执存喺 B 嘅 SQLite（`business_receipts`）。网络断咗唔知写咗未时，B 嘅流程标「结果不确定」，App 只准「查結果」（用同一个 id 去 Supabase 查），唔会再写。
- 请假 = upsert `leaves`；改网名 = 更新 `profiles.nickname`（1–20 字）。
- 冇坐标、冇屋企位置上服务器：只有地标名、分钟数、遮荫比例。局域网用 HTTP（token 会以明文经 Wi-Fi 传）：只喺自己屋企 / 信得过嘅 Wi-Fi 用；公网一定用 `--tunnel`（HTTPS）。

### 理解用户讲咩（LLM）

而家冇通义千问 key：用 B 嘅有限规则（`providers.demo_interpret`，成员 A 补咗粤语「分鐘」「十五」「改名做」）。有 key 之后：

```sh
export QWEN_API_KEY=…  QWEN_BASE_URL=https://dashscope.aliyuncs.com/compatible-mode/v1  QWEN_MODEL=qwen-plus
tools/voice_server.sh
```

就会自动改用模型理解（B 嘅 `Providers.interpret`），确认卡同所有检查不变。

## 测试

```sh
tools/voice_server.sh --test                                 # 60 项：B 原有 41 项 + Supabase 适配 9 项 + 播报 10 项
~/Desktop/HACK/voice-runtime/venv/bin/python server/tools/verify_backend.py   # B 嘅一条龙验证（测试 + 临时服务 HTTP 冒烟）
python3 server/tools/tts_probe.py "一句粤语"                  # 服务器开住时：量第一段声音几耐到，存 WAV
```

## 改咗组员 B 嘅乜（俾 B 睇）

B 嘅文件照搬入 `server/assistant/`，测试原封不动全过。改动全部係加嘢、有注释「成员 A」：

- `config.py`：多一个模式 `supabase`；加 `SUPABASE_URL`、`SUPABASE_ANON_KEY`、`TTS_PROVIDER`（auto/sovits/azure/none）、`SOVITS_*`、`SPEECH_CACHE_DIR`、`SPEECH_LAN_OPEN`、`VOICE_LOG_TEXT`。
- `providers.py`：`supabase` 模式冇 Qwen key 时都用规则（`production` 照旧拒绝）；规则识「分鐘」（繁体）、中文数字分钟（「十五分鐘」）、「改名做」。
- `models.py`：`SpeakRequest` 加 `speed`、`prefetch`。
- `service.py`：确认卡回覆加 `data.action`（联系人 / 地点 id、时间），App 用嚟出粤语复述卡，唔使由 message 猜。
- `app.py`：按模式揀 `Business` 或 `SupabaseBusiness`；加 `/v1/voice`、`/v1/assistant/context`、`/assistant/*`；播报用 sovits 时流式返回 WAV。
- 新文件：`sovits.py`（本机粤语播报）、`supabase_business.py`（业务适配）、`tests/test_sovits.py`、`tests/test_supabase_adapter.py`、`tools/tts_probe.py`。
- 冇用到：Azure 录音转写（App 用 iPhone 自己嘅粤语识别，免费）；B 嘅 iOS `AssistantPanel`、`AudioController`（App 用自己嘅语音卡）。`AssistantClient`、`Models`、`AssistantViewModel` 嘅规则抄咗入 `ios/StreetWalk/Assistant/`。

### 2026-10-12 B 新版（豆包那套）点样接

- B 嘅 `doubao.py`、`realtime.py`、`voice_policy.py`、`weather.py`、`windows.py` 同测试原样搬入（`windows.py` 只改网页路径一行，网页喺 `server/windows/web/`）；B 嘅文档、Mac 壳、工具喺 `upstream_b/`（Mac 壳只作参考，佢按 B 嘅目录结构揾 `backend/`）。
- B 写 Python 3.12，我哋同 GPT-SoVITS 共用 3.10 环境：`compat.py`（由 `__init__.py` 最先载入）补 `asyncio.timeout`、统一 `TimeoutError`；服务器经 `python -m assistant.serve` 开（等 uvicorn / websockets 都喺补丁之后载入）。
- `config.py`：`DOUBAO_CONFIG`（B 嘅 voice-config.json）、`TTS_PROVIDER=doubao`；冇另外设千问就用 B 嘅方舟模型做理解（`providers.py` 对方舟关「思考」，同 B 一样）。
- `sovits.py` 嘅 `SpeechService`：可以几条线程同时合成、按语言合成（豆包有普通话）。
- B 嘅实时对话（`/windows/realtime`）只准本机网页用；App 用 A 嘅 `/v1/voice/ear`（只收音、唔自己答，交返手机分流）同 `/v1/assistant/turn`（`app_policy.TurnPolicy` 照 B 嘅 VoicePolicy 次序：本地规则 → 豆包路由 → 天气 / 固定句 / App 操作）。B 嘅播报句（「测试确认卡」等联调字眼）唔用：App 按结构出自己嘅粤语卡同播报。
- 排行榜、散步纪录：B 嘅固定句讲「未接通」，喺 App 唔啱，改讲去边一页睇（`app_policy.BOARD/HISTORY`）。
