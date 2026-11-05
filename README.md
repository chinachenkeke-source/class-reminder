# ⏰ 上课提醒 · ClassReminder

> 🎓 一节课快开始时，它会在屏幕**右上角**喊你一句：
> **「九三班历史课，11点20分上课，还有15分钟」**

![version](https://img.shields.io/badge/version-1.1.0-blue)
![platform](https://img.shields.io/badge/macOS-13%2B-black)
![swift](https://img.shields.io/badge/Swift-5-orange)
![deps](https://img.shields.io/badge/dependencies-0-green)

macOS 菜单栏小工具，写给一线老师用的：**单双周**课表、**CSV 导入**、课前大卡片提醒 + 中文语音播报。
单文件 Swift，零第三方依赖，不联网。

---

## ✨ 能做什么

| | |
|---|---|
| 🕘 **菜单栏常驻** | 不占 Dock，点一下弹出面板：下一节倒计时 + 今天 + 明天 |
| ⏰ **课前提醒** | 5 / 10 / 15 / 20 / 30 分钟可选，界面上点一下就生效 |
| 🔊 **够响够醒目** | 620×254 蓝色大卡片置顶所有窗口 + 三连提示音 + 中文女声播报两遍 |
| 🗓️ **单双周** | 按「第 1 周是哪天、那周是单周还是双周」自动推算，可手动切换 |
| 📥 **CSV 导入** | App 内下载模板 → Excel/Numbers 填好 → 导入，立刻生效 |
| 🚀 **开机自启** | 写 LaunchAgent，重启后自动回来 |
| 🎨 **今天/明天分色** | 今天蓝灰、明天琥珀，一眼分清 |

---

## 📸 长什么样

### 🕘 菜单栏

![状态栏](statusbar.png)

> 时钟图标 + 下一节「时间 + 班级」。此图为渲染示意图（系统截图需要录屏权限）。

### 🗂 点开面板

![面板](preview.png)

> 蓝色大卡是下一节（含倒计时和几点提醒）；「进行中」的课会高亮；上完的打 ✓ 变淡；
> 明天那张卡换成琥珀色，不会和今天看混。

### 🚨 课前提醒

![提醒](preview-alert.png)

> 屏幕右上角，置顶所有窗口；三行字：`即将上课 · 第5节` / `九3班 · 历史` / **`11:20 上课`**。

---

## 📦 安装

1. 到 [Releases](../../releases) 下载 `ClassReminder-1.1.0.dmg`（或 `.zip`）
2. 双击挂载，把 `上课提醒.app` 拖进 `应用程序`
3. 第一次打开被拦 → 在 App 上**右键 →「打开」**（没有开发者签名）

数据都放这几个地方：

| 东西 | 位置 |
|---|---|
| 📄 课表数据 | `~/Library/Application Support/ClassReminder/timetable.json` |
| 🧾 日志 | `~/Library/Logs/ClassReminder.log` |
| 🚀 开机自启 | `~/Library/LaunchAgents/com.mac.classreminder.plist` |

卸载：面板里「退出」→ 删掉上表三项 + `应用程序` 里的 App。

---

## 🔧 从源码构建

需要 Xcode Command Line Tools（有 `swiftc` 即可）：

```bash
./build.sh
```

它会：编译 → 临时签名 → 装到 `/Applications` → 写 LaunchAgent 并启动。
首次运行把仓库里的 `timetable.json` 复制成你的数据；之后改仓库那份**不会**自动覆盖你在用的，要手动 `cp`。

---

## 📝 课表格式（JSON）

```json
{
  "weekAnchor": "2026-08-31",
  "anchorIsOdd": true,
  "leadMinutes": 10,
  "skipDates": ["2026-11-20"],
  "lessons": [
    { "weekday": 4, "period": 2, "start": "08:35", "end": "09:15", "klass": "八2班", "subject": "历史" },
    { "weekday": 4, "period": 1, "start": "07:50", "end": "08:30", "klass": "七1班", "subject": "历史", "weeks": "odd" }
  ]
}
```

- 🗓 `weekday`：1=周一 … 7=周日
- 🔢 `period`：1–13 第几节；0 表示早读 / 晚读
- 🔁 `weeks`：`"odd"` 单周 / `"even"` 双周 / 不写 = 每周
- ⚓ `weekAnchor` + `anchorIsOdd`：第 1 周的周一是哪天、那周算单周还是双周
- 🏖 `skipDates`：放假、调休，那天完全不提醒

---

## 📥 用模板填课表（CSV）

菜单栏 →「下载模板」得到 `课表模板.csv`，用 Excel / Numbers 填：

| 星期 | 节次 | 开始时间 | 结束时间 | 班级 | 科目 | 周次 |
|---|---|---|---|---|---|---|
| 周一 | 第3节 | 09:25 | 10:05 | 九1班 | 历史 | 每周 |
| 周二 | 第4节 | 10:30 | 11:10 | 九3班 | 历史 | 单周 |
| 周二 | 第4节 | 10:30 | 11:10 | 九3班 | 历史 | 双周 |
| 周五 | 早读 | 07:30 | 07:50 | 七1/八2班 | 历史早读 | 单周 |

写法很宽松 👇

- 📅 星期：`周一` / `星期一` / `1` / `Mon`
- 🔢 节次：`第5节` / `5` / `早读` / `晚读` / `晚自习`
- ⏱ 时间：`07:50` / `7:50` / `0750` / `7点50`
- 🔁 周次：`每周`（不写也行）/ `单周` / `双周` / `单双周`（自动拆两条）
- 💬 有逗号的格子加英文引号：`"九3班,培优"`

填完回 App 点「导入课表」选文件；写错会提示「第 N 行：……」。
🚫 表头顺序随便调，多出来的列会被忽略。

---

## 🗂 目录结构

```
Sources/main.swift   💻 全部源码（课表 / 菜单栏 / 面板 / 提醒 / CSV 导入）
Info.plist           🪪 App 信息（LSUIElement = 菜单栏模式）
timetable.json       📄 示例课表，首次运行复制成用户数据
课表模板.csv          📥 空白模板
课表示例.csv          📚 填好的完整例子（27 条）
build.sh             🔧 一键编译 + 安装
preview.png          🗂 面板截图
preview-alert.png    🚨 提醒截图
statusbar.png        🕘 菜单栏示意
CHANGELOG.md         🗒 版本记录
```

---

## 💻 命令行小工具

```bash
ClassReminder --dump            # 📅 打印未来 8 天课表
ClassReminder --parse x.csv     # 🔍 只校验 CSV 能不能读懂
ClassReminder --import x.csv    # 📥 无界面导入
ClassReminder --voice           # 🎙 看当前用的中文嗓音
ClassReminder --shot out.png    # 🖼 渲染面板预览图
ClassReminder --shotalert o.png # 🖼 渲染提醒预览图
ClassReminder --shotbar o.png   # 🖼 渲染菜单栏示意
```

---

## 🚧 已知限制

- 🔕 没有开发者证书，系统通知中心不让发通知（`Notifications are not allowed for this application`），
  所以走「置顶窗口 + 声音 + 语音」这条路，反而不会被勿扰模式吞掉。
- 🔊 音量上限就是系统音量；系统音量很低时声音也小，但窗口一定在右上角最前面。
- 🎙 语音用系统自带 `say`（优先 Tingting），不联网、不装东西。

---

## 🗒 版本记录

完整记录见 [CHANGELOG.md](CHANGELOG.md)。

- **v1.1.0** · 2026-11-05 —— 📥 CSV 导入与模板｜🚨 提醒卡片改版（上课时间最大）｜⚙️ 提前分钟可选｜🕘 菜单栏图标
- **v1.0.0** · 2026-11-04 —— 🎉 首个版本：菜单栏面板、单双周、课前提醒、语音播报

---

## 📄 许可

暂未指定。想开源（MIT / Apache-2.0）说一声，我加 LICENSE。
