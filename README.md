# macOS Countdown Screen Saver / macOS 倒计时屏幕保护程序

## English

A planned native macOS screen saver that displays a countdown to up to five events, inspired by the minimal black-background design of [Countdown](https://github.com/zfdang/Countdown).

### Planned Features

- Configure up to five target dates and times, with precision down to seconds.
- Choose Gregorian or Chinese lunar dates, including leap months.
- Sort events chronologically and automatically advance to the next event.
- Display days, hours, minutes, and seconds using large digits on a black background.
- Support explicit event time zones and a completion state after all events expire.
- Provide English and Chinese interfaces. By default, use Chinese when the primary system language is Chinese and English for every other language.
- Allow manual language selection: System, English, or Chinese. The initial Chinese translation uses Simplified Chinese for all Chinese system-language variants.

### Project Status

The project is in the design phase. No installable screen saver is available yet. Build and installation instructions will be added when the implementation is ready.

### Documentation

The [design proposal](doc/design-proposal.md) covers UI layouts, event behavior, calendar conversion, language selection, architecture, and acceptance criteria. All project design documents are written in English; this README is maintained in both English and Chinese.

## 中文

计划开发一款原生 macOS 屏幕保护程序，显示最多五个目标时间的倒计时，界面参考 [Countdown](https://github.com/zfdang/Countdown) 的黑底简洁风格。

### 计划功能

- 最多设置五个目标日期和时间，精确到秒。
- 支持公历和中国农历日期，包括闰月。
- 按目标时间自动排序，到期后切换到下一个目标。
- 采用黑色背景和大数字，显示天、小时、分、秒。
- 支持为每个目标设置明确的时区，全部到期后显示完成状态。
- 提供中英文界面。默认检测系统的首选语言：中文显示中文，其他语言一律显示英文。
- 支持手动选择“跟随系统”“English”或“中文”。首版中文界面统一使用简体中文，包括繁体中文系统环境。

### 项目状态

目前处于设计阶段，尚未提供可安装的屏幕保护程序。实现完成后将补充构建与安装说明。

### 文档

[设计方案](doc/design-proposal.md) 包含界面布局、目标切换、历法转换、语言选择、技术架构及验收标准。项目设计文档统一使用英文；本 README 保持中英文双语。
