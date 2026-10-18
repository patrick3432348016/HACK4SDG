# HACK4SDG · 街坊行（暂名）

香港跨校 GenAI Hackathon for SDGs 2026，赛道 2（Sustainable Northern Metropolis）。

北都新屋邨的街坊天天在同一条路上擦肩而过。这个 App 让大家在每天本来就会走的那段路上认识彼此：在排行榜上认出面孔，碰一碰手机成为街坊，说一句话就约好一起走。

## 现状（2026-10-11）

**全部功能都是真的，两部 iPhone（iPhone 15、iPhone Air）实测装好，碰一碰已在真机成功。** 「示範」角色只在演示模式（录视频、脚本）出现。

| 功能 | 怎么实现 |
|---|---|
| 实时地图、3D 纸雕场景、地标、楼影遮荫、寻路 | 定位 → 400 m 网格 → OpenStreetMap；SceneKit |
| 认家、出门自动记录散步、搬家提示 | 「始终允许」定位 + 夜间学家 + 离家地理围栏（`Services/HomeLearner` `LocationMonitor`） |
| 网名、附近真人排行榜、街坊、约会、出门提醒、反映 | Supabase 后端（新加坡，匿名登录，`supabase/`）；服务器上没有坐标和门牌，只有地标名 |
| 碰一碰加街坊 | 超宽带测距（移植组员 B 的 `ios/UWBMeetDemo/`），两机 20 cm 内停 0.4 秒 → 服务器配对；旧机型用二维码（`Bump/`） |
| 找人（像「查找」） | 私有频道互传 GPS + 指南针箭头；30 m 内切超宽带精确箭头（`Services/LiveFindSession`） |
| 灵动岛横幅 + Live Activity | 小组件扩展 `StreetWalkWidgets` |
| 天气 | 香港天文台；香港以外（如深圳）用 Open-Meteo |
| 语音助手 | 组员 B 的助手（`server/`）+ Mac 当场生成粤语声（GPT-SoVITS，`tools/voice_server.sh`）；连不上 Mac 时用手机系统声音和模板理解 |
| 语言 | 粤语繁体 / 普通话简体 / 英语，设定里即时切换 |

## 装到自己的 iPhone

看 **[ios/真机安装说明.md](ios/真机安装说明.md)**：装 Xcode、登录自己的 Apple ID（免费即可）、插线后跑 `cd ios && zsh tools/install_device.sh`。免费账号装的 App 7 天过期，重跑即可。

## 剩下要做的

- [ ] **真机实测**（两台两账号）：找人箭头和超宽带近距离、出门提醒（App 要先在家过一晚认家）、后台散步记录、灵动岛
- [ ] **清理服务器测试用户**、执行后端建议的 3 条 SQL（见 `supabase/README.md`），否则测试用户会出现在真人排行榜
- [ ] 普通话版收尾：iOS 菜单名「阅读与朗读」「朗读内容」未核对；`Info.plist` 权限说明仍是粤语
- [ ] **Pitch deck**（10/18 交；要队名、队伍编号、成员姓名和大学）、WorkBuddy 报告
- [ ] 宣传片：`video/`（Remotion 工程，英文旁白约 3 分钟，见 `video/README.md`）
- [ ] AI 换真模型（组员 B，国内模型如智谱 GLM）
- [ ] 10/17 晚前用 `install_device.sh` 重装两台演示机（免费签名到期）
- [ ] 可选：开苹果付费开发者账号 → TestFlight 发链接 + 真推送

其他文档（部分内容是 10/10 前写的，以本页为准）：
- 产品规格：[docs/产品定稿_康乐社交App_v1.0.md](docs/产品定稿_康乐社交App_v1.0.md)
- 排版草图：[docs/design/layout_sketch.html](docs/design/layout_sketch.html)（浏览器直接打开）
- 演示视频：[docs/demo/streetwalk_demo.mp4](docs/demo/streetwalk_demo.mp4)
- 成员 A 旧进度与手动验证清单：[docs/PROGRESS_member_A.md](docs/PROGRESS_member_A.md)
- 后端表结构、权限规则、权限测试：[supabase/README.md](supabase/README.md)

## iOS 原型（`ios/`）

需要 Xcode 26.6 和 iOS 26.5 模拟器（`xcodebuild -downloadPlatform iOS` 可装）。

```sh
cd ios
./tools/selftest.sh      # 在 Mac 上跑核心逻辑自测：地图解析、地标、太阳位置、遮荫、天文台数据
./tools/test.sh          # Xcode 单元测试（207 个）；失败返回非零（SIM="iPhone Air" 换模拟器）
./tools/install_device.sh # 编译并装到插着线的 iPhone（见 真机安装说明.md）
./tools/run.sh -demo     # 编译、装到 iPhone 17 模拟器并启动（定位设在皇后山邨）；编译失败会停下
./tools/record_demo.sh   # 录演示视频（先关掉其他模拟器）
```

`run.sh` 可用 `SIM="iPhone 17 Pro"` 换模拟器。启动参数：

- 演示：`-demo`（右上角演示菜单）、`-script`（主演示，约 105 秒）、`-captions`（配中英字幕）、`-script2`（街坊页、信息卡、语音卡、时间滑杆）、`-script3`（改约、反映回覆、出发提醒、过期、解除街坊、设置页）、`-resetOnboarding -scriptOnboarding`（首次使用）。
- 状态：`-skipOnboarding`、`-resetOnboarding`、`-resetData`（清本机纪录）、`-withNeighbor`、`-hour 15`（指定时间）、`-offline`（强制用内置地图、不拉天气）、`-logNotifications`（打印已安排的约会通知）、`-autoWalk`（自动走一次演示散步，打印落脚点）、`-scriptWalk`（请假几日、提醒时段、关闭演示模式、改楼时返回上一步 / 定位中和选楼后按「唔改」）。
- 画面：`-stats`、`-tilt`（移轴模糊）、`-pitch`、`-ovy`、`-ovd`。

### 分工与目录

| 目录 | 负责 | 内容 |
|---|---|---|
| `App/` `Design/` `Store/` `UI/` | A | App 骨架、设计规范、状态与流程（`AppStore` 按功能分成多个扩展文件）、全部界面、设置页 |
| `Store/Community.swift` `Backend/` | A | `CommunityService`：要和别人同步的数据（街坊、约会、出门状态、反映）。真机用 `SupabaseCommunityService`，演示模式用 `LocalCommunityService` |
| `Store/LocalStore.swift` | A | 本机持久化（街坊关系、约会、反映、地标名、每日散步纪录、请假） |
| `Services/` | A | 香港天文台天气、真机步行检测（Core Motion + 定位 + 计步器）、散步纯逻辑（落脚点、补记、请假）、本地通知、电话 |
| `Map/` | A | 定位 → 400 m 网格 → Overpass 实时地图 → 缓存/兜底、地标选取、寻路 |
| `Scene/` | A | SceneKit 微缩模型、相机、人物、标签投影、移轴模糊 |
| `Shade/` | A | 太阳位置（NOAA）、楼宇射线遮荫 |
| `AI/` | B | `TemplateAI`：AIService 的模板实现（之后换真模型） |
| `Voice/` | B | 粤语语音识别与播报 |
| `Bump/` | A + B | 碰一碰：真机 `NearbyBumpService`（超宽带，移植自 B 的 `UWBMeetDemo`）+ 二维码；演示模式用 `SimulatedBumpService` |
| `Domain/Contracts.swift` | A + B | 规格 §8 的接口，改动需两人同意（2026-10-07 加了改约 / 取消约意图和月报 `stats` 参数，待 B 确认） |
| `StreetWalkTests/` | A | Xcode 单元测试 |

新增 `.swift` 文件放进 `ios/StreetWalk/` 任意子目录即可，Xcode 工程用文件夹同步，不用改 `project.pbxproj`。

### 隐私

- 只有 400 m 网格的范围会发给地图服务；天气请求不带位置；精确位置和散步路线只留在手机。
- 对外（后端）只讲地标级位置；月报只出 10 人以上的匿名汇总。
- 非街坊永远不会出现在 3D 场景里；街坊只在出门时、只以地标级位置出现。

## 数据署名

地图数据 © OpenStreetMap contributors，依 ODbL 授权。内置示例数据：`ios/StreetWalk/Resources/fallback_queenshill.json`（皇后山邨）。
