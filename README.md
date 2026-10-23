<p align="center">
  <img src="Assets/AppIcon.png" width="128" alt="MusicBar icon">
</p>

# MusicBar

轻巧的 macOS 菜单栏音乐控件，直接控制 Apple Music。

菜单栏显示当前歌名，点击展开紧凑面板。上一首、播放/暂停、下一首位于歌名右侧，下方显示歌手及播放进度。正常状态只保留“打开音乐”和“退出控件”，连接出错时才显示错误提示与“重试”。

## 下载与使用

从 [Releases](https://github.com/blueroy00/MusicBar/releases/latest) 下载 `MusicBar-1.0.0-arm64.zip`，解压后将 `MusicBar.app` 放入“应用程序”，双击启动。

- 当前预编译版本适用于 **Apple Silicon Mac**。
- 编译目标为 macOS 13 及以上；目前仅在开发机器的 macOS 27.2 上实测，旧版本兼容性尚未实机验证。
- 首次使用需要允许 MusicBar 控制“音乐”。如曾拒绝，在“系统设置 → 隐私与安全性 → 自动化”中允许，回到控件点击“重试”。
- 应用使用本地临时签名，尚未经过 Apple 开发者签名和公证。下载版可能被 Gatekeeper 拦截；可选择阅读源码并在本机构建。
- 退出 MusicBar 不会停止音乐播放。不会自动添加登录启动项。

## 功能

- 菜单栏歌名与播放状态。
- 300 × 176 pt 紧凑面板，长歌名省略显示，悬停可查看完整标题。
- 上一首、播放/暂停、下一首。
- 歌手、当前时间、歌曲时长、播放进度。
- 出错时提供重试和授权说明。
- 原生 Swift / AppKit，无第三方运行依赖。

MusicBar 通过 Music 自带的 AppleScript 接口通信，不修改系统 Music.app，不注入进程，不读取账号凭据，也不向外部服务器发送数据。本项目是独立的伴随工具，与 Apple 无关联。

## 本机构建

安装 Xcode Command Line Tools，然后执行：

```sh
git clone https://github.com/blueroy00/MusicBar.git
cd MusicBar
zsh build.sh
open MusicBar.app
```

构建脚本使用当前 Mac 的 CPU 架构，输出 `MusicBar.app`，复制图标并完成本地临时签名，最后运行 8 项基础自检。无需 Xcode 项目或包管理器。

## 目录

```text
Source/main.swift     界面、Music 通信及基础自检
Source/Info.plist     应用信息和自动化权限说明
Assets/AppIcon.png   图标原图
Assets/AppIcon.icns  macOS 应用图标
Assets/Design.md     图标设计记录
build.sh             构建、签名及自检
```

## 验证与已知边界

已验证编译、基础自检、真实歌曲信息读取、播放/暂停和恢复播放、上一首在歌曲中途返回开头，以及紧凑面板的实际显示。

状态约每两秒更新，进度条仅供显示。尚未完成下一首、拒绝授权、连接故障、Intel 和各旧版 macOS 的完整实机回归。
