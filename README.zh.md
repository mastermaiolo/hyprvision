# HyprVision

[🇵🇹 Português](README.md) · [🇬🇧 English](README.en.md) · 🇨🇳 **简体中文**

**Hyprland 原生视觉体验管理器** —— 用 GLSL 着色器实现色彩配置、色温/亮度/伽马调节、ICC 配置文件，以及可叠加的效果层，全部通过一个 Rofi 菜单操作。完全运行在合成器自带的 Lua 运行时里：不需要后台服务，不需要 Python。

## 目录

[功能](#功能) · [内置配置](#内置配置) · [环境要求](#环境要求) · [安装](#安装) · [使用方法](#使用方法) · [配置](#配置) · [创建自己的配置](#创建自己的配置) · [常见问题](#常见问题) · [架构](#架构) · [鸣谢](#鸣谢) · [许可证](#许可证)

## 功能

- **视觉配置**：用声明式 Lua 定义 —— 着色器 + 色温 + 亮度 + 伽马 + 可选的 ICC
- **可叠加的效果层**，可以叠加在任何配置之上：
  - *纸质纹理*（轻/中/重）—— 电子墨水风格的纸张纹理：双八度颗粒、纸浆斑点、各向异性纤维，以及暖色调的阴影提亮
  - *额外调暗*（10%–50%）—— 通过着色器实现的调暗，可以低于背光的最小亮度
- **8-bit 面板防色带**：合成后的着色器始终启用约 1 LSB 的抖动 + `render:use_fp16`（内部 FP16 曲线）+ `render:icc_vcgt_enabled`（通过 KMS 的 VCGT 色调曲线）
- **无后台服务的自适应**：按时间和电池状态自动切换配置（并在恢复后自动还原之前的配置），通过 Hyprland 原生的 `hl.timer` 实现
- **真正的持久化**：配置在 `hyprctl reload` 后依然保留 —— Lua 运行时会重建，`init.lua` 会在加载时恢复状态
- **社区提供的额外着色器**：`shaders/extras/` 文件夹已接入菜单
- **菜单支持 3 种语言**（英语、葡萄牙语、中文，根据系统语言自动选择），并会跟随当前的主题色：如果你在用 [Caelestia](https://github.com/caelestia-dots/shell)，菜单会自动跟随你壁纸生成的 Material 配色
- **可恢复的紧急重置**（`Super+Shift+H`）：把屏幕恢复到中性状态，并把当前状态存档到 `state.bak` —— 菜单里会出现"恢复上一个状态"
- **平滑过渡**：色温/亮度/伽马的变化通过 wl-gammarelay-rs 实现平滑过渡（按需启动）

## 内置配置

| 配置 | 分类 | 用途 |
|---|---|---|
| ✨ Cinema Desktop | correction（校正） | 日常使用的细腻微对比度 |
| 🖥️ TN Recovery | correction（校正） | 补偿发灰、发白的 TN 面板 |
| 🌌 Cinema OLED | experience（体验） | 纯黑压暗 + 选择性提高鲜艳度 —— 在 LCD 上还原 OLED 的观感 |
| 🧡 Cinema OLED Warm | experience（体验） | 更暖色温的 Cinema OLED —— 夜间看电影不刺眼 |
| 🎬 Cinema Film | experience（体验） | S 形曲线、暗角与胶片颗粒感 |
| 📖 E-Ink | experience（体验） | 电子墨水风格的去饱和效果（可以搭配纸质纹理） |
| 🕯️ E-Ink Warm Dark | experience（体验） | 暖色、更暗的 E-Ink —— 蜡烛光下的 Kindle，黑色更深 |
| 🎯 Focus | experience（体验） | 专注模式，减弱视觉干扰 |
| 🌙 Night | experience（体验） | 夜间模式，暖色调、偏暗 |
| 📄 Paper | experience（体验） | 泛黄的纸张质感，适合阅读和写作 |
| 🌿 Paper Soft | experience（体验） | 比 Paper 更暖、更柔和，适合长时间使用 |
| ⚡ Reset | system（系统） | 恢复到完全中性 |

## 环境要求

- Hyprland ≥ 0.55，**且使用 Lua 配置**（`~/.config/hypr/hyprland.lua`）—— 如果你用的是传统的 `hyprland.conf`，请改用 v4（tag `v4.1.0`）
- rofi
- **推荐安装：**[wl-gammarelay-rs](https://github.com/MaxVerevkin/wl-gammarelay-rs) —— 实现色温/亮度/伽马的平滑过渡
- 可选：libnotify（用于通知）；lua5.4 和 glslangValidator 只有运行测试时才需要

## 安装

```bash
git clone https://github.com/mastermaiolo/hyprvision && cd hyprvision
./install.sh
```

安装程序是交互式的（根据系统语言显示英文或中文），在全新安装时还会：
- 检查 rofi、wl-gammarelay-rs 和 libnotify，并提供安装缺失依赖的选项（通过 pacman/apt/dnf；wl-gammarelay-rs 只在 AUR 中提供，会用 paru/yay 安装）；
- 如果 `Super+H` 或 `Super+Shift+H` 已经被占用，可以让你选择别的按键；
- 询问你想手动切换配置，还是按时间自动切换（一个白天配置，一个夜晚配置）。

完成之后，会把文件复制到 `~/.config/hypr/hyprvision`，在 `hyprland.lua` 里加入 `require("init")`，并重新加载 Hyprland —— 马上就能用。再次运行会更新文件，但不会重新询问，也不会丢失 `config.lua` 或状态。

卸载（恢复屏幕并删除所有文件）：`./uninstall.sh`。

项目自检（状态、配置、合成器交互、日程、电池、所有着色器的 GLSL 校验、菜单的烟雾测试）：`lua5.4 test_hyprvision.lua`。

## 使用方法

`Super+H` 打开菜单；`Super+Shift+H` 是紧急重置。如果要写脚本，可以用菜单背后同样的接口：

```
hyprctl eval "hv.apply('night')"           应用一个配置
hyprctl eval "hv.overlay('paper','medium')"  off | light | medium | heavy
hyprctl eval "hv.overlay('dim', 30)"       0 | 10 | 20 | 30 | 40 | 50
hyprctl eval "hv.apply_extra('x.glsl')"    应用一个额外着色器（在 shaders/extras/ 里）
hyprctl eval "hv.safe_reset()"             紧急重置
hyprctl eval "hv.restore_backup()"         恢复存档的状态
```

当前状态始终可以在 `~/.config/hypr/hyprvision/state/state` 里读到（key=value 格式）。

## 配置

`~/.config/hypr/hyprvision/config.lua` —— 快捷键、日程和电池设置。编辑后执行：`hyprctl reload`。在任何事件里，`profile = "none"` 表示"什么都不做"。要点：

- `battery.restore_after_low` —— 电池电量恢复后，会自动切回电量不足前正在使用的配置
- `schedule.apply_on_start` —— 默认是 `false`：开机时保留你上次的配置；日程只在时间跨过某个时间点时才会触发
- 时间段除了 `hour` 之外还支持 `minute`

## 创建自己的配置

`profiles/my_profile.lua`：

```lua
-- 一句话描述这个配置。
return {
    name = "My Profile", icon = "🔥", category = "experience",
    temperature = 5800,   -- 2500–9000 K
    brightness  = 0.95,   -- 0.05–1.5
    gamma       = 1.0,    -- 0.5–2.0
    shader = "experience/my_profile.glsl",   -- 放在 shaders/ 里；nil = 不用着色器
    -- icc = "my_monitor.icc",                -- 可选，放在 icc/ 里
}
```

**写着色器时要注意：**一定要用 `precision highp float;`。如果用 `mediump`，经典的噪声写法 `fract(sin(x) * 43758.5)` 在 AMD/Mesa 显卡上会超出 fp16 的取值范围，产生 NaN，导致**整个屏幕变黑**。（项目自带的所有着色器都已经修正过这个问题。）

## 常见问题

- **屏幕变黑或看不清** → 按 `Super+Shift+H`（安全重置）；如果是不小心按到的，再在菜单里选"恢复上一个状态"。
- **换主题/改配置后配置"消失了"** → 正常情况下不会发生（`init` 会在 reload 时恢复状态）；可以查看 `state/hyprvision.log`。
- **Hyprland 提示"uniform 'time'"警告** → 动态着色器需要设置 `debug:damage_tracking 0`（会增加一些 GPU 占用）；HyprVision 会自动按正确的顺序处理好这件事。
- 日志文件：`~/.config/hypr/hyprvision/state/hyprvision.log`。

## 架构

```
init.lua        合成器接线：快捷键、定时器、加载时恢复状态
core.lua        核心引擎：状态、配置、GLSL 合成、应用、伽马、定时任务
config.lua      用户配置（快捷键、日程、电池）
profiles/*.lua  声明式的配置文件
ui/launcher.sh  Rofi 菜单（读取 state/，通过 hyprctl eval 发送 "hv.*"）
```

`hyprctl eval` 不会返回任何输出，所以 Lua 端把 `state/state` 和 `state/profiles.menu` 作为供菜单读取的接口。合成后的着色器会生成在 `$XDG_RUNTIME_DIR/hyprvision/` 里。所有在合成器里运行的代码都包在 `pcall` 里 —— 一个出错的配置只会记录到日志，绝不会导致某个处理函数崩溃。

## 鸣谢

`shaders/extras/` 里的着色器都来自 Hyprland 社区 —— 基本保持原样，只做了最小限度的兼容性调整（`highp`，见上文说明）。原作者：

| 作者 | 项目 | 着色器 |
|---|---|---|
| **[snes19xx](https://github.com/snes19xx)** | — | cinema、clarity_inefficient、crt_mode、focus、fuji_acros、gameboy、IBM5151、main、matte、night、night_vision、outdoor、reading_mode、soft、vhs |
| **0x15BA88FF** | [hyprshaders](https://github.com/0x15BA88FF/hyprshaders) | chromatic_abberation、colors、contrast、crt、drugs、extradark、grain、invert、retro、solarized |
| **Sijan-Bhusal** | [HyprShades](https://github.com/sijan-dev/HyprShades) | amoled、blue-light-filter、cyberpunk、matrix、retro |
| **ManofJELLO** | [HyprWindowShade](https://github.com/ManofJELLO/HyprWindowShade) | chromaGlitch、pixelate、wireframe |

着色器文件内部引用的来源：
- `0x15BA88FF_crt.frag` —— © 2023 Maxim Samoliuk，MIT 许可证（完整声明在文件开头）
- `0x15BA88FF_colors.glsl` —— 基于 [Hyprland 仓库的一次讨论](https://github.com/hyprwm/Hyprland/issues/1140#issuecomment-1614863627)和 SweetFX 的 [Vibrance.fx](https://github.com/CeeJayDK/SweetFX/blob/a792aee788c6203385a858ebdea82a77f81c67f0/Shaders/Vibrance.fx#L20-L30)
- `0x15BA88FF_retro.glsl` —— [wessles/GLSL-CRT](https://github.com/wessles/GLSL-CRT/blob/master/shader.frag) 的修改版
- `0x15BA88FF_extradark.frag` —— 数值参考自 [ReShade 论坛的一个帖子](https://reshade.me/forum/shader-discussion/3673-blue-light-filter-similar-to-f-lux)

*（ManofJELLO 的 `HyprWindowShade` 其实是一个按窗口应用着色器的 C++ 插件 —— 并不是这里归在他名下的 3 个着色器文件的真正出处，但这是我们手头能找到、属于他的着色器项目。）*

感谢以上所有作者。如果你是某个着色器的作者，想要更正署名、补充许可证信息，或要求移除，请提交一个 issue。

## 许可证

MIT —— 见 [LICENSE](LICENSE)。`shaders/extras/` 里的第三方着色器保留各自的许可条款，已在上面的"鸣谢"中标注。

版本历史：[CHANGELOG.md](CHANGELOG.md)。
