# 小圆的大肥鱼 · iOS

一个**纯客户端**的 AI 聊天 App：直接调用你填写的模型接口，没有任何中转服务器，API Key 只保存在本机 Keychain。界面参考 iOS 版 DeepSeek：居中模型切换、左侧历史、底部胶囊输入框 +「深度思考」开关、助手消息支持 Markdown 与思考过程折叠。

主界面文案以「小圆专属喵」为主题，App 显示名为 **小圆的大肥鱼**。

- 最低系统：**iOS 17.0**
- 开发工具：**Xcode 15 及以上**（Swift 5.9 / SwiftUI）
- 支持协议：**OpenAI 兼容**、**Anthropic Claude 原生**、**Google Gemini 原生**
- 无第三方依赖（不使用 SPM / CocoaPods）

> ⚠️ iOS 应用必须在 macOS 上用 Xcode 编译签名，Windows 无法直接产出 IPA。本仓库提供的是可直接打开的完整 Xcode 工程 + 一键打包脚本，在 Mac 上执行即可得到 IPA。

---

## 一、在 Mac 上跑起来

```bash
# 1. 打开工程
open DeepChat.xcodeproj

# 2. Xcode 里选择 DeepChat Target → Signing & Capabilities
#    Team 选择你的 Apple ID（免费账号也可以，真机运行有效期 7 天）
#    Bundle Identifier 改成唯一的，例如 com.yourname.deepchat

# 3. 选中一台 iOS 17 的真机或模拟器，⌘R 运行
```

首次运行后：

1. 点击右上角模型名 → 或首页「先配置一个 API Key」
2. 进入 **设置 → 模型服务 → 添加服务**，选择服务商
3. 填入 API Key（DeepSeek 在 <https://platform.deepseek.com/api_keys> 获取）
4. 回到首页即可开始对话

---

## 二、打包成 IPA

### 方式 A：脚本一键打包

```bash
chmod +x scripts/build-ipa.sh

# 用免费/付费开发者账号自动签名
TEAM_ID=你的团队ID ./scripts/build-ipa.sh

# 产物：build/ipa/DeepChat.ipa
```

`TEAM_ID` 可以在 Xcode → Settings → Accounts → 你的账号 → Team ID 里看到。

可选环境变量：

| 变量 | 说明 | 默认 |
| --- | --- | --- |
| `TEAM_ID` | 开发者团队 ID | 工程里配置的 |
| `METHOD` | 导出方式：`development` / `ad-hoc` / `app-store` | `development` |

### 方式 B：Xcode 图形界面

1. `Product → Archive`
2. 在 Organizer 里点 `Distribute App`
3. 选择 `Release Testing`(ad-hoc) 或 `Development`，一路 Next
4. 导出得到 `DeepChat.ipa`

### 装到 iPhone 上

- **有付费开发者账号**：用 TestFlight 或 ad-hoc 描述文件直接安装
- **只有免费 Apple ID**：用 [Sideloadly](https://sideloadly.io/) 或 [AltStore](https://altstore.io/) 安装 IPA（7 天需重签一次）
- **已越狱设备**：可直接安装 self-signed IPA

---

## 三、没有 Mac 怎么办（Windows 也能出 IPA）

仓库内置了 GitHub Actions 工作流 `.github/workflows/build-ipa.yml`，用 GitHub 的 macOS 机器打包出**未签名 IPA**：

1. 把这个目录推到一个 GitHub 仓库（私有仓库也可以）
2. 打开仓库的 **Actions → Build unsigned IPA → Run workflow**
3. 约 3～5 分钟后在运行结果的 **Artifacts** 里下载 `DeepChat-unsigned-ipa`
4. 在 Windows 上用 [Sideloadly](https://sideloadly.io/) 选择这个 IPA，填你的 Apple ID 自签安装到 iPhone

> 未签名 IPA 不能直接双击安装，必须经过第 4 步用你的 Apple ID 重新签名（免费账号 7 天有效）。
> 如果你有付费开发者账号，也可以把证书和描述文件配成仓库 Secrets，工作流里改成正常签名导出。

### 全自动版本（本仓库已经跑通）

`scripts/ci-build.js` 用一个 GitHub Token 就能完成：建仓库 → 上传全部源码 → 触发 macOS 编译 → 下载 IPA 到 `dist/`。

```bash
node scripts/ci-build.js .ci-tools/token.txt deepchat-ios
```

Token 需要 `repo` + `workflow` 两个权限。编译失败时会自动把 xcodebuild 的错误行抓回来。



---

## 三、功能

| 功能 | 说明 |
| --- | --- |
| 多服务 / 多模型 | 内置 DeepSeek、OpenAI、Claude、Gemini、OpenRouter、Kimi、智谱、通义、硅基流动、Ollama 预设，也可自定义任意兼容地址 |
| 流式输出 | SSE 逐字渲染，可随时点停止 |
| 深度思考 | 自动识别 `deepseek-reasoner`、R1、GLM-4.6 等推理模型，思考过程折叠展示并显示耗时 |
| Markdown | 标题 / 列表 / 引用 / 表格 / 代码块（带复制按钮） |
| 会话管理 | 历史列表按今天、昨天、最近 7 天分组，支持重命名、删除、搜索模型 |
| 本地持久化 | 会话存 `Application Support/DeepChat/state.json`，Key 存 Keychain |
| 外观 | 跟随系统 / 浅色 / 深色，DeepSeek 同款蓝色主题 |

---

## 四、各服务的配置方式

| 服务 | 协议 | Base URL | 获取 Key |
| --- | --- | --- | --- |
| DeepSeek | OpenAI 兼容 | `https://api.deepseek.com/v1` | platform.deepseek.com |
| OpenAI | OpenAI 兼容 | `https://api.openai.com/v1` | platform.openai.com |
| Claude | Anthropic 原生 | `https://api.anthropic.com/v1` | console.anthropic.com |
| Gemini | Gemini 原生 | `https://generativelanguage.googleapis.com/v1beta` | aistudio.google.com |
| OpenRouter | OpenAI 兼容 | `https://openrouter.ai/api/v1` | openrouter.ai |
| Kimi | OpenAI 兼容 | `https://api.moonshot.cn/v1` | platform.moonshot.cn |
| 智谱 GLM | OpenAI 兼容 | `https://open.bigmodel.cn/api/paas/v4` | open.bigmodel.cn |
| 通义千问 | OpenAI 兼容 | `https://dashscope.aliyuncs.com/compatible-mode/v1` | bailian.console.aliyun.com |
| 硅基流动 | OpenAI 兼容 | `https://api.siliconflow.cn/v1` | cloud.siliconflow.cn |
| 本机 Ollama | OpenAI 兼容 | `http://localhost:11434/v1` | 不需要 Key |

> 中转站也可以：Base URL 填 `https://你的域名/v1`，协议选「OpenAI 兼容」即可。
> 注意 Base URL 一般**只填到 `/v1`**，不要带 `/chat/completions`。

---

## 五、目录结构

```
DeepChat.xcodeproj/           # Xcode 工程（由 scripts/gen_xcode_project.py 生成）
DeepChat/
├── DeepChatApp.swift         # 入口，注入 AppStore / 主题
├── Info.plist                # ATS 允许本地网络等配置
├── Models/
│   └── Models.swift          # 消息、会话、供应商、设置、预设
├── Services/
│   ├── APIClient.swift       # 三种协议的请求构造 + SSE 解析
│   ├── AppStore.swift        # 全局状态、发送/停止/重生成、持久化
│   └── Keychain.swift        # API Key 安全存储
├── Views/
│   ├── ContentView.swift     # 导航栏、顶栏模型切换、Toast
│   ├── ChatView.swift        # 消息列表 + 空状态
│   ├── MessageRow.swift      # 气泡 / Markdown / 思考过程 / 操作
│   ├── ComposerView.swift    # 输入框、深度思考开关、发送
│   ├── HistoryView.swift     # 历史对话
│   ├── ModelPickerView.swift # 模型选择
│   ├── SettingsView.swift    # 设置 + 服务列表 + 服务编辑
│   ├── MarkdownView.swift    # 轻量 Markdown 渲染器
│   └── Theme.swift           # 配色与品牌图标
└── Assets.xcassets/          # App 图标、主题色

scripts/
├── gen_xcode_project.py      # 重新生成 pbxproj（新增 Swift 文件后跑一次）
├── build-ipa.sh              # 归档 + 导出 IPA
├── check_swift.py            # 静态自检（括号、plist、常见笔误）
└── make-appicon.py           # 生成 1024 图标（Pillow）

.github/workflows/build-ipa.yml  # 用 GitHub 的 macOS 打包未签名 IPA
```

---

## 六、常见问题

**401 / 403**
Key 不正确、没有余额，或该 Key 限制了来源。检查设置里的 Key 与 Base URL 是否属于同一家服务。

**404**
Base URL 多了或少了路径。OpenAI 兼容地址以 `/v1` 结尾；Claude 用 `/v1`；Gemini 用 `/v1beta`。

**一直转圈 / 超时**
1. 确认手机能访问该域名（部分海外接口需要网络代理）
2. 换成国产接口或中转地址试一下
3. 关闭「流式输出」再试，可排除 SSE 解析问题

**用 Ollama 连不上**
`Info.plist` 已配置 `NSAllowsLocalNetworking`，Base URL 填 `http://电脑IP:11434/v1`，并确认 Ollama 监听 `0.0.0.0`（`OLLAMA_HOST=0.0.0.0`）。

**为什么没有语音、图片输入？**
这一版是纯文本对话；需要图片理解可以后续接 `image_url` / Gemini `inline_data`。

---

## 七、二次开发

- 换主题色：改 `Views/Theme.swift` 里的 `Theme.accent`
- 改应用名 / Bundle ID：`Info.plist` 的 `CFBundleDisplayName`，以及 Target 的 `PRODUCT_BUNDLE_IDENTIFIER`
- 新增 Swift 文件后执行 `python3 scripts/gen_xcode_project.py` 重新生成工程文件（也可以在 Xcode 里直接拖入）
- 新增服务商预设：编辑 `Models/Models.swift` 的 `ProviderPresets.all`

## 八、隐私

- 无任何统计、上报、第三方 SDK
- 请求只会发往你在设置里填写的 Base URL
- Key 存在 Keychain（`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`，不随 iCloud 备份迁移）
- 卸载 App 后本地数据与 Key 一并清除

## 许可证

MIT
