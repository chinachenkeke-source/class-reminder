# 上课提醒 · ClassReminder

macOS 菜单栏小工具：每节课前几分钟，在屏幕右上角弹出置顶大卡片、连响三声、中文女声报一句「九三班历史课，11点20分上课，还有15分钟」。

支持**单双周**课表、**CSV 导入**自己的课、开机自启。单文件 Swift，无第三方依赖。

![菜单栏面板](preview.png)

![上课提醒](preview-alert.png)

## 功能

- **菜单栏常驻**，不占 Dock；点一下弹出面板：下一节倒计时、今天、明天（颜色完全分开）
- **课前提醒**：5 / 10 / 15 / 20 / 30 分钟可选，界面上点一下就生效
- **提醒够响**：620×254 蓝色大卡片置顶所有窗口 + 连响三次 + 中文女声（Tingting）播报两遍
- **单双周**：按「第 1 周是哪天、是单周还是双周」自动推算，随时可在菜单里手动切换
- **CSV 导入**：App 里下载模板 → Excel/Numbers 填好 → 导入，立刻生效
- **开机自启**：写一个 LaunchAgent，重启后自动出现

## 安装

到 [Releases](../../releases) 下载 `ClassReminder-1.0.dmg`（或 zip），双击挂载，把 `上课提醒.app` 拖进 `应用程序`。

没有开发者签名，第一次打开可能被拦：在 App 上**右键 →「打开」**即可。

- 数据：`~/Library/Application Support/ClassReminder/timetable.json`
- 日志：`~/Library/Logs/ClassReminder.log`
- 自启：`~/Library/LaunchAgents/com.mac.classreminder.plist`

卸载：退出 App（面板里「退出」），删掉上面三个位置的文件和 App 即可。

## 从源码构建

需要 Xcode Command Line Tools（有 `swiftc` 就行）：

```bash
./build.sh
```

它会：编译 `Sources/main.swift` → 临时签名 → 装到 `/Applications` → 写 LaunchAgent 并启动。
首次运行会把 `timetable.json` 复制到 `~/Library/Application Support/ClassReminder/` 作为默认课表；
之后改仓库里的 `timetable.json` 不会自动覆盖你正在用的那份，要手动 `cp` 过去。

## 课表格式（JSON）

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

- `weekday`：1=周一 … 7=周日
- `period`：1–13 第几节；0 表示早读 / 晚读
- `weeks`：`"odd"` 单周 / `"even"` 双周 / 不写=每周
- `weekAnchor` + `anchorIsOdd`：第 1 周的周一是哪天、那周是单周还是双周
- `skipDates`：放假、调休，那天完全不提醒

## 用模板填课表（CSV）

菜单栏 →「下载模板」，得到 `课表模板.csv`，用 Excel / Numbers 填：

| 星期 | 节次 | 开始时间 | 结束时间 | 班级 | 科目 | 周次 |
|---|---|---|---|---|---|---|
| 周一 | 第3节 | 09:25 | 10:05 | 九1班 | 历史 | 每周 |
| 周二 | 第4节 | 10:30 | 11:10 | 九3班 | 历史 | 单周 |
| 周二 | 第4节 | 10:30 | 11:10 | 九3班 | 历史 | 双周 |
| 周五 | 早读 | 07:30 | 07:50 | 七1/八2班 | 历史早读 | 单周 |

写法很宽松：

- 星期：`周一` / `星期一` / `1` / `Mon`
- 节次：`第5节` / `5` / `早读` / `晚读` / `晚自习`
- 时间：`07:50` / `7:50` / `0750` / `7点50`
- 周次：`每周`（不写也行）/ `单周` / `双周` / `单双周`（自动拆两条）
- 有逗号的格子用英文引号：`"九3班,培优"`

填完回 App 点「导入课表」选文件即可；写错的会提示「第 N 行：……」。
`课表示例.csv` 是一份填好的完整例子，可以对照。

## 目录结构

```
Sources/main.swift   全部源码（课表逻辑 / 菜单栏 / 面板 / 提醒 / CSV 导入）
Info.plist           App 基本信息（LSUIElement=菜单栏模式）
timetable.json       示例课表，首次运行会复制成用户数据
课表模板.csv          空白模板
课表示例.csv          填好的例子
build.sh             一键编译 + 安装
preview.png          菜单栏面板截图
preview-alert.png    提醒弹窗截图
```

## 命令行小工具

```bash
/Applications/上课提醒.app/Contents/MacOS/ClassReminder --dump           # 打印未来 8 天课表
/Applications/上课提醒.app/Contents/MacOS/ClassReminder --parse x.csv    # 只校验 CSV 能不能读懂
/Applications/上课提醒.app/Contents/MacOS/ClassReminder --import x.csv   # 无界面导入
/Applications/上课提醒.app/Contents/MacOS/ClassReminder --voice          # 看当前用的中文嗓音
/Applications/上课提醒.app/Contents/MacOS/ClassReminder --shotalert a.png # 渲染提醒弹窗预览图
```

## 已知限制

- 没有开发者证书，系统通知中心不让发通知（`Notifications are not allowed for this application`），
  所以提醒走的是「置顶窗口 + 声音 + 语音」，反而不会被勿扰模式吞掉。
- 音量上限就是系统音量，系统音量调很低时声音也会小，但窗口一定在右上角最前面。
- 语音用系统自带的 `say`（优先 Tingting），不需要联网。

## 许可

暂未指定。想开源（MIT / Apache-2.0）说一声，我加上 LICENSE。
