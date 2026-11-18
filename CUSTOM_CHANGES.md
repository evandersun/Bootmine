# Bootmine-roothide 定制版改动说明

基于 `roothide/Dopamine-roothide`（`3.x` 分支）的本地定制。

> 说明：GitHub 用户 `zpbb` 名下并无 Bootmine RootHide 项目（只有一个 `hello-world`），
> 因此本定制以官方 `roothide/Dopamine-roothide` 为基础完成。

## 已完成的改动

### 1. 主页改为 Bootstrap 风格（四按钮 + 日志）

文件：`Application/Bootmine/UI/DOMainViewController.m`

- 主页重新排布为 **2×2 四个按钮**（图标在上、文字在下）：
  - `Jailbreak`（越狱）
  - `Settings`（设置）
  - `Reboot Userspace`（重启用户空间，仅越狱后可用）
  - `Credits`（关于）
- 按钮下方新增**常驻日志视图** `DOBootstrapLogView`：越狱全过程的进度日志
  （如 "Exploiting Kernel"、"Bypassing PAC" 等）会实时滚动显示在主页，无需再点击
  越狱按钮展开全屏日志。
- 移除了原来的“大号越狱按钮 + 圆角 ActionMenu + 点击后展开全屏日志”的交互。
- 包管理器首次选择流程、越狱互斥检查（roothide）、重启用户空间等原有逻辑均保留。

### 2. 新增设置项：越狱完成后不自动重启用户空间

- 文件：`Application/Bootmine/UI/Settings/DOSettingsController.m`
  - 在“越狱设置”分组中新增开关 **`Settings_No_Auto_Reboot_Userspace`**
    （键名 `noAutoRebootUserspace`，默认关闭 = 保持原有的自动重启行为）。
- 文件：`Application/Bootmine/UI/DOMainViewController.m`
  - `startJailbreak` 成功分支读取该开关：
    - 关闭（默认）：按原逻辑调用 `[jailbreaker finalize]`（内部执行 userspace reboot）。
    - 开启：跳过自动重启，弹出“越狱完成”提示，用户可选择“立即重启用户空间”或稍后手动重启。
- 文件：`Application/Bootmine/UI/DOUIManager.m`
  - `resetSettings` 中同步清理该偏好键。

### 3. 本地化

新增以下文案 key，已写入全部 27 个 `*.lproj/Localizable.strings`：

| Key | 英文 | 简体中文 |
| --- | --- | --- |
| `Settings_No_Auto_Reboot_Userspace` | Don't Reboot Userspace After Jailbreak | 越狱完成后不自动重启用户空间 |
| `Jailbreak_Done_NoReboot_Title` | Jailbreak Complete | 越狱完成 |
| `Jailbreak_Done_NoReboot_Message` | （见文件） | （见文件） |
| `Log_Ready` | Ready. Press Jailbreak to begin. | 准备就绪。点击「越狱」开始。 |
| `Log_Jailbreak_Done_NoReboot` | Jailbreak done. Userspace reboot skipped. | 越狱完成。已跳过重启用户空间。 |

英文外的非中文语言统一回退到英文文案。

## 关于打包为 IPA

当前环境是 Linux，**无法编译** iOS App（需要 macOS + Xcode + iOS SDK + Theos +
ldid + libarchive）。本项目原生的构建产物就是 `.ipa`（同时复制一份为 `.tipa`
供 TrollStore 使用），二者内容完全一致。

请在 **macOS** 上任选一种方式打包：

### 方式 A：一键脚本（推荐）

```bash
cd Bootmine-roothide
chmod +x build_ipa.sh
./build_ipa.sh
```

脚本会依次安装依赖（Homebrew / Theos / iOS 16.5 SDK / trustcache）、拉取子模块、
编译并生成：

```
Application/Bootmine-roothide-<version>.ipa
Application/Bootmine-roothide-<version>.tipa
```

### 方式 B：GitHub Actions（无需本地配置）

1. Fork 本仓库；
2. 进入 `Actions` → `build ipa/tipa file` → `Run workflow`；
3. 构建完成后在 Artifacts 下载（下载的是 zip，解压后得到 `.ipa` / `.tipa`）。

> 该方式与仓库自带 `BUILD.md` 一致，CI 会自动注入签名 entitlements（`ldid -S`）并打包。

### 方式 C：手动（已有完整 Mac 环境时）

```bash
brew install make libarchive
export PATH="$(brew --prefix make)/libexec/gnubin:$PATH"
git submodule update --init --recursive
export THEOS="$PWD/theos"      # 需按 BUILD 流程安装 roothide/theos + iPhoneOS16.5.sdk
gmake -j$(sysctl -n hw.logicalcpu)
# 产物：
#   Application/Bootmine-roothide-<version>.ipa
#   Application/Bootmine-roothide-<version>.tipa
```

`Application/Makefile` 中 `xcodebuild` 后由 `ldid` 进行 ad-hoc 签名，再把
`Bootmine.app` 放入 `Payload/` 并 `zip` 成 `.ipa`，因此产物无需开发者账号即可
通过 TrollStore / 巨魔 等工具安装（首次安装需 TrollStore 环境）。

## 修改文件清单

```
Application/Bootmine/UI/DOMainViewController.m          （主页重写）
Application/Bootmine/UI/Settings/DOSettingsController.m （新增开关）
Application/Bootmine/UI/DOUIManager.m                   （resetSettings 清理键）
Application/Bootmine/*.lproj/Localizable.strings        （新增 5 个文案 key × 27 语言）
build_ipa.sh                                            （新增：Mac 打包脚本）
CUSTOM_CHANGES.md                                       （本文件）
```
