# HACK4SDG · 街坊行（暂名）

香港跨校 GenAI Hackathon for SDGs 2026，赛道 2（Sustainable Northern Metropolis）。

北都新屋邨的街坊天天在同一条路上擦肩而过。这个 App 让大家在每天本来就会走的那段路上认识彼此：在排行榜上认出面孔，碰一碰手机成为街坊，说一句话就约好一起走。

- 产品规格：[docs/产品定稿_康乐社交App_v1.0.md](docs/产品定稿_康乐社交App_v1.0.md)
- 排版草图：[docs/design/layout_sketch.html](docs/design/layout_sketch.html)（浏览器直接打开）

## iOS 原型（`ios/`）

需要 Xcode 26.6 和 iOS 26.5 模拟器（`xcodebuild -downloadPlatform iOS` 可装）。

```sh
cd ios
./tools/selftest.sh      # 在 Mac 上跑核心逻辑自测：地图解析、地标、太阳位置、遮荫
./tools/run.sh -demo     # 编译、装到 iPhone 17 模拟器并启动（定位设在皇后山邨）
```

调试启动参数：`-demo`（右上角演示菜单）、`-skipOnboarding`、`-resetOnboarding`、`-withNeighbor`、`-hour 15`（指定时间）、`-offline`（强制用内置地图）、`-stats`、`-notilt`（关移轴模糊）。

### 分工与目录

| 目录 | 负责 | 内容 |
|---|---|---|
| `App/` `Design/` `Store/` `UI/` | A | App 骨架、设计规范、状态与流程、全部界面 |
| `Map/` | A | 定位 → 400 m 网格 → Overpass 实时地图 → 缓存/兜底、地标选取、寻路 |
| `Scene/` | A | SceneKit 微缩模型、相机、人物、标签投影、移轴模糊 |
| `Shade/` | A | 太阳位置（NOAA）、楼宇射线遮荫 |
| `AI/` | B | `TemplateAI`：AIService 的模板实现（之后换真模型） |
| `Voice/` | B | 粤语语音识别与播报 |
| `Bump/` | B | `SimulatedBumpService`：碰一碰的模拟实现（真机用超宽带） |
| `Domain/Contracts.swift` | A + B | 规格 §8 的接口，改动需两人同意 |

新增 `.swift` 文件放进 `ios/StreetWalk/` 任意子目录即可，Xcode 工程用文件夹同步，不用改 `project.pbxproj`。

### 隐私

- 只有 400 m 网格的范围会发给地图服务，精确位置不离开手机。
- 非街坊永远不会出现在 3D 场景里；街坊只在出门时、只以地标级位置出现。

## 数据署名

地图数据 © OpenStreetMap contributors，依 ODbL 授权。内置示例数据：`ios/StreetWalk/Resources/fallback_queenshill.json`（皇后山邨）。
