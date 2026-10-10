# 北都碰一碰 UWB 独立演示原型

这是为 Sustainable Northern Metropolis 路演准备的独立 iPhone 工程，不接入现有 App。目标是两台指定真机在前台完成：加密配对 → 真实 UWB 测距 → 靠近显示名片 → 双方确认 → 交换虚构演示联系方式 → 本地保存。

**当前没有完成 Xcode 编译或真机验证。源代码不是已测试成功的 App，也不是可直接安装的 IPA。Windows 上无法使用 Xcode，模拟器不能证明 UWB 硬件效果。**

## 已知测试条件

- 用户提供：iPhone 18 Pro / iOS 27.0；iPhone 15 Pro / iOS 26.5.2。型号与版本尚未由设备读取验证。
- 当前工作机：Windows，没有 Mac、Xcode 或 Swift 编译器。
- 项目最低部署目标：iOS 17.0。必须使用支持实际手机系统版本的 Xcode/macOS；降低部署目标不能解决 Xcode 不支持连接新系统的问题。
- 启动时以 `NISession.deviceCapabilities.supportsPreciseDistanceMeasurement` 检查实际能力。不支持时明确停止，不显示模拟距离。
- 仅两台设备、一组配对、程序保持前台。不做后台运行、多人最近对象选择、正式账号或云端好友同步。
- 主题以用户在本会话的更新为准；仓库根目录 AGENTS.md 仍保留旧主题。Official judging weights have not been located.

## 获取 Xcode 与安装

1. 找一台能运行合适版本 Xcode 的 Mac。Xcode 可从 Mac App Store 免费下载，不能安装到 Windows。
2. 把整个 `UWBMeetDemo` 文件夹复制到 Mac，双击 `UWBMeetDemo.xcodeproj`。不需要 XcodeGen、CocoaPods 或第三方 Swift 包。
3. Xcode → Settings → Apple Accounts，登录自己的 Apple Account。不要把密码、证书或签名文件提交到仓库。
4. 选择项目里的 UWBMeetDemo target → Signing & Capabilities → 开启 Automatically manage signing，选择自己的 Team；若标识符不可用，把 `org.hack4sdg.uwbmeetdemo` 改成唯一值。
5. 用数据线连接手机，按设备提示信任 Mac、启用 Developer Mode。在 Xcode 顶部选择实际手机，点击 Run。两台分别安装同一份工程。
6. 首次运行允许“本地网络”和“附近交互”。若拒绝，去 iOS Settings 修改权限，再重启程序。保持 Wi-Fi/蓝牙可用；第一次排障可让两台连接同一普通局域网，避免访客网络隔离。

苹果允许个人 Apple Account 用于个人设备测试；具体设备、签名有效期和能力限制以 Xcode 当前反馈为准。路演前必须重新检查签名是否有效。远程 Mac 或云端构建仍涉及签名和安装，不等于 Windows 可以直接运行 Xcode。优先借用本地 Mac，便于同时连接两台手机调试。

## 现场操作

1. 两台都选择“重置演示”，仅删除这个程序里的测试好友记录。
2. A 选择 Patrick，点击“我是发起方”。B 选择小陈，输入 A 屏幕上的一次性配对码，点击加入。配对码仅用于排除其他设备，准备阶段即可输入；不是 UWB 触发的替代品。
3. 程序通过 Network/Bonjour 连接，交换 Nearby Interaction 会话令牌，显示真实距离读数。未取得距离时显示“等待测距”。
4. 将手机从较远处缓慢靠近。初始实验参数为 ≤ 0.30 m，连续 0.50 s；测量间隔超过 0.35 s 会重置未完成的计时。这些参数尚未实测，不能承诺所有机型都适用。
5. 两端都测到接近后才显示确认卡。核对双方名字，选择愿意分享的**虚构演示字段**，分别确认。不读取系统联系人。
6. 双方同意后才交换字段。每台先持久化收到的名片，再发回执；本机保存和对方保存回执都到达后显示成功。
7. 同时查看两台的成功页与好友列表。没有对方保存回执的记录标为“尚未完成双向确认”，不能算成功。
8. 下一轮两台都重置。不要只重置一台；进入后台、拒绝、失联、3 分钟超时都需要重新开始。

NFC、NameDrop、假距离、定时自动成功、网页模拟均未用于此工程。方向箭头不是本版要求，只使用距离。即便同一对用户重试，本地好友按稳定演示设备 ID 更新，不重复增加。重装程序会更换本地 ID。

## 模块与边界

- `Core/`：接近判定、双向确认状态、消息序号校验和 TCP 分帧，独立于 iOS 硬件。
- `App/`：SwiftUI、Network 通信、Nearby Interaction、受保护的本地 JSON 保存。
- 测距令牌仅识别一次 NI 会话，不作为账号 ID。公开名片也经加密连接交换；联系方式直到双方确认后才发送。
- 配对码为每次发起随机生成的 80-bit 秘密，通过当面屏幕输入共享，不通过网络发送。CryptoKit HKDF 派生密钥，ChaChaPoly 加密并认证消息，序号与会话检查拒绝乱序/重放。此为受控双机演示设计，不是经过安全审计的生产身份系统。知道配对码的人可以加入，不能公开投屏配对码后声称具备实名认证。
- 联系方式固定为明显虚构的 `DEMO_*` 值。它不会在微信/WhatsApp 自动加好友。
- 不存原始距离日志、不访问位置/相机/联系人。诊断仅记录阶段、耗时与错误，不记录名片字段、令牌或配对码。
- 如果未来接入真实账号，必须由平台认证会话绑定用户身份，并重新设计好友同步、删除/撤销、敏感信息存储和连接认证。不要把本地演示关系当成平台关系。

## 检查与测试

在 Mac 的 Terminal 中，进入本文件夹：

```sh
swift test
xcodebuild -project UWBMeetDemo.xcodeproj -scheme UWBMeetDemo -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

`swift test` 测试持续靠近、读数中断、越界读数、双向同意、取消、分帧和消息重放。它不能证明苹果硬件/API 可运行。第二条命令检查整个 iOS 工程能否编译；模拟器里 UWB 应明确显示不支持。真机安装仍需要签名。

Windows 上仅可执行工程结构检查：

```powershell
python tools/check_project.py
```

如增删 Swift 源文件，可运行 `python tools/generate_project.py` 重建工程引用。这个脚本会重新生成项目配置；在 Xcode 手动改过配置后不要随意运行，以免覆盖自己的 Team/Bundle ID 设置。

## 必须完成的真机验收

| 场景 | 期望 | 结果 |
|---|---|---|
| 正常靠近并双方确认，连续 10 轮 | 两端正确配对，真实距离触发，双方保存；记录每轮耗时和失败 | 未测试 |
| 手机保持较远，等待超过 0.5 s | 不显示确认名片 | 未测试 |
| 短暂靠近后移开／距离中断 | 不使用过期读数累计接近时间 | 未测试 |
| 一方未同意／拒绝 | 不交换联系方式，不显示成功 | 未测试 |
| 关闭一方程序或进入后台 | 明确结束；重新开始可恢复 | 未测试 |
| 错误配对码／附近第三台程序 | 不应交换名片；重新配对可恢复 | 未测试 |
| 本地网络或附近交互权限被拒 | 提示错误或受阻，不伪造成功 | 未测试 |
| 同一对用户再操作 | 好友记录不重复 | 未测试 |
| 关闭重开程序 | 已保存好友保留，未完成记录不被标为成功 | 未测试 |
| 未分享任何联系方式 | 仍可交换公开名片，字段保持空 | 未测试 |
| 断开发生在确认或保存过程中 | 无回执一方显示未完成；必须同时检查两台 | 未测试 |
| 清除演示数据 | 仅本程序的测试好友清除 | 未测试 |

分布式断线时不能保证两块屏幕同一瞬间更新。本原型通过本机持久化、对方回执和未完成标记避免静默把中断当成功，但仍需要双机验收。录制真实备用视频前，先完成以上测试。

## 官方依据

- [Nearby Interaction](https://developer.apple.com/documentation/nearbyinteraction/)
- [会话令牌交换流程](https://developer.apple.com/documentation/nearbyinteraction/discovering-peers-with-multipeer-connectivity)
- [Network 点对点接口](https://developer.apple.com/documentation/network/nwparameters/includepeertopeer)
- [从 Multipeer Connectivity 迁移到 Network](https://developer.apple.com/documentation/technotes/tn3213-moving-from-multipeer-connectivity-to-network-framework)
- [设备能力检查](https://developer.apple.com/documentation/nearbyinteraction/nidevicecapability)
- [Xcode 下载](https://apps.apple.com/app/xcode/id497799835)
- [个人账号和设备测试](https://developer.apple.com/support/compare-memberships/)

