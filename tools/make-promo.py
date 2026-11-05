import os
BASE = "/Users/mac/Documents/deepseek-harness/default-workspace/class-reminder"
OUT = os.path.join(BASE, "promo")

def p(path): return "file://" + os.path.join(BASE, path)

CSS = """
*{margin:0;padding:0;box-sizing:border-box}
body{width:1200px;height:800px;font-family:-apple-system,"PingFang SC","Helvetica Neue",sans-serif;background:#0B1B3A;overflow:hidden}
.card{position:relative;width:1200px;height:800px;color:#fff;overflow:hidden;
  background:linear-gradient(150deg,#12306E 0%,#0C1F4E 55%,#070F27 100%)}
.dots{position:absolute;inset:0;opacity:.14;
  background-image:radial-gradient(rgba(255,255,255,.9) 1.2px,transparent 1.2px);
  background-size:28px 28px;mask-image:linear-gradient(to bottom right,#000,transparent 72%)}
.glow{position:absolute;width:1000px;height:1000px;border-radius:50%;right:-300px;top:-380px;
  background:radial-gradient(circle,rgba(88,150,255,.28),rgba(88,150,255,0) 62%)}
.kicker{position:absolute;left:84px;top:64px;font-size:18px;letter-spacing:3px;
  color:rgba(255,255,255,.66);font-weight:700}
h2{position:absolute;left:84px;top:98px;width:1030px;font-size:46px;line-height:1.25;
  font-weight:800;letter-spacing:-.5px}
.stage{position:absolute;left:0;right:0;top:180px;height:452px;display:flex;justify-content:center;align-items:center}
.stage img{border-radius:18px;box-shadow:0 40px 90px rgba(0,0,0,.55),0 0 0 1px rgba(255,255,255,.16)}
.row3{position:absolute;left:84px;right:84px;bottom:64px;display:flex;gap:26px}
.cell{flex:1;font-size:18.5px;line-height:1.55;color:rgba(255,255,255,.9);padding-left:26px;position:relative}
.cell:before{content:"";position:absolute;left:0;top:7px;width:12px;height:12px;border-radius:4px;
  background:#FFB020;box-shadow:0 0 0 5px rgba(255,176,32,.16)}
.center{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center}
.chip{font-size:19px;font-weight:600;padding:9px 18px;border-radius:999px;
  background:rgba(255,255,255,.14);border:1px solid rgba(255,255,255,.24)}
.foot{position:absolute;left:0;right:0;bottom:34px;text-align:center;font-size:16px;
  color:rgba(255,255,255,.5);letter-spacing:.5px}
.steps{position:absolute;left:84px;top:250px;display:flex;flex-direction:column;gap:22px}
.step{display:flex;align-items:center;gap:16px;font-size:23px;color:rgba(255,255,255,.94)}
.num{width:38px;height:38px;border-radius:12px;background:#FFB020;color:#3A2400;font-weight:800;
  display:flex;align-items:center;justify-content:center;font-size:19px}
.side{position:absolute;right:96px;top:150px}
.side img{border-radius:16px;box-shadow:0 30px 70px rgba(0,0,0,.45),0 0 0 1px rgba(255,255,255,.12)}
"""

def page(body):
    return f"<html><head><meta charset='utf-8'><style>{CSS}</style></head><body><div class='card'>{body}</div></body></html>"

def write(name, body):
    open(os.path.join(OUT, name + ".html"), "w").write(page(body))
    print("wrote", name)

ICON = p("AppIcon-rounded.png")

# 封面
write("01-cover", f"""
<div class="dots"></div><div class="glow"></div>
<div class="center">
  <img src="{ICON}" style="width:176px;height:176px;border-radius:40px;box-shadow:0 36px 80px rgba(0,0,0,.45)">
  <div style="font-size:78px;font-weight:800;margin-top:40px;letter-spacing:-1px">上课提醒</div>
  <div style="font-size:26px;color:rgba(255,255,255,.86);margin-top:20px">课表装进去 · 课前 15 分钟叫一次 · 到点再叫一次</div>
  <div style="display:flex;gap:14px;margin-top:44px">
    <div class="chip">教师</div><div class="chip">macOS</div><div class="chip">课表</div><div class="chip">提醒</div>
  </div>
</div>
<div class="foot">开源 MIT · github.com/chinachenkeke-source/class-reminder</div>
""")

# 功能1
write("02-lead", f"""
<div class="dots"></div><div class="glow"></div>
<div class="kicker">功能 ① · 课前提醒</div>
<h2>提前 15 分钟，屏幕右上角弹一张大卡片</h2>
<div class="stage"><img src="{p('preview-alert.png')}" style="width:720px"></div>
<div class="row3">
  <div class="cell">54 号字的上课时间 + 班级科目，隔几米也看得清</div>
  <div class="cell">三声提示音 + 中文女声念一遍，不用盯着屏幕</div>
  <div class="cell">置顶在所有窗口之上，写教案时也不会被盖住</div>
</div>
""")

# 功能2
write("03-start", f"""
<div class="dots"></div><div class="glow"></div>
<div class="kicker">功能 ② · 到点提醒</div>
<h2>上课时间到了，再提醒一次</h2>
<div class="stage"><img src="{p('preview-alert-start.png')}" style="width:720px"></div>
<div class="row3">
  <div class="cell">换成琥珀色卡片：「现在上课 · 第5节」</div>
  <div class="cell">只响三声、不语音，不打断你讲课</div>
  <div class="cell">顺带写上下课时间，一眼知道上到几点</div>
</div>
""")

# 功能3 单双周
write("04-week", f"""
<div class="dots"></div><div class="glow"></div>
<div class="kicker">功能 ③ · 单双周</div>
<h2>单周双周自动算，不用自己排</h2>
<div class="stage"><img src="{p('preview.png')}" style="height:430px"></div>
<div class="row3">
  <div class="cell">设一次「第 1 周是哪天」，之后自动切换</div>
  <div class="cell">周次算错了，面板里点一下整体挪一周</div>
  <div class="cell">今天蓝灰、明天琥珀，一眼分清哪天是哪天</div>
</div>
""")

# 功能4 导入
tpl = """
<div style="width:560px;background:#fff;border-radius:16px;overflow:hidden;color:#19233A;
     box-shadow:0 34px 80px rgba(0,0,0,.45)">
  <div style="background:#2D6BF0;color:#fff;font-size:15px;font-weight:700;display:flex">
    <div style="flex:1;padding:12px 4px;text-align:center">星期</div>
    <div style="flex:1;padding:12px 4px;text-align:center">节次</div>
    <div style="flex:1;padding:12px 4px;text-align:center">开始</div>
    <div style="flex:1;padding:12px 4px;text-align:center">结束</div>
    <div style="flex:1.2;padding:12px 4px;text-align:center">班级</div>
    <div style="flex:1;padding:12px 4px;text-align:center">科目</div>
    <div style="flex:1;padding:12px 4px;text-align:center">周次</div>
  </div>
  <div style="display:flex;font-size:15px;border-top:1px solid #E7EDF8"><div style="flex:1;padding:13px 4px;text-align:center">周一</div><div style="flex:1;padding:13px 4px;text-align:center">第3节</div><div style="flex:1;padding:13px 4px;text-align:center">09:25</div><div style="flex:1;padding:13px 4px;text-align:center">10:05</div><div style="flex:1.2;padding:13px 4px;text-align:center">九1班</div><div style="flex:1;padding:13px 4px;text-align:center">历史</div><div style="flex:1;padding:13px 4px;text-align:center">每周</div></div>
  <div style="display:flex;font-size:15px;border-top:1px solid #E7EDF8;background:#F6F8FC"><div style="flex:1;padding:13px 4px;text-align:center">周四</div><div style="flex:1;padding:13px 4px;text-align:center">第5节</div><div style="flex:1;padding:13px 4px;text-align:center">11:25</div><div style="flex:1;padding:13px 4px;text-align:center">12:05</div><div style="flex:1.2;padding:13px 4px;text-align:center">九3班</div><div style="flex:1;padding:13px 4px;text-align:center">历史</div><div style="flex:1;padding:13px 4px;text-align:center">每周</div></div>
  <div style="display:flex;font-size:15px;border-top:1px solid #E7EDF8"><div style="flex:1;padding:13px 4px;text-align:center">周三</div><div style="flex:1;padding:13px 4px;text-align:center">第1节</div><div style="flex:1;padding:13px 4px;text-align:center">07:50</div><div style="flex:1;padding:13px 4px;text-align:center">08:30</div><div style="flex:1.2;padding:13px 4px;text-align:center">九3班</div><div style="flex:1;padding:13px 4px;text-align:center">历史</div><div style="flex:1;padding:13px 4px;text-align:center">单周</div></div>
  <div style="display:flex;font-size:15px;border-top:1px solid #E7EDF8;background:#F6F8FC"><div style="flex:1;padding:13px 4px;text-align:center">周三</div><div style="flex:1;padding:13px 4px;text-align:center">第1节</div><div style="flex:1;padding:13px 4px;text-align:center">07:50</div><div style="flex:1;padding:13px 4px;text-align:center">08:30</div><div style="flex:1.2;padding:13px 4px;text-align:center">九3班</div><div style="flex:1;padding:13px 4px;text-align:center">历史</div><div style="flex:1;padding:13px 4px;text-align:center">双周</div></div>
</div>
"""
write("05-import", f"""
<div class="dots"></div><div class="glow"></div>
<div class="kicker">功能 ④ · 自己的课表</div>
<h2>填个 Excel 模板，五分钟导入</h2>
<div class="stage">{tpl}</div>
<div class="row3">
  <div class="cell">星期 / 节次 / 周次 全是下拉选择</div>
  <div class="cell">单双周可选：不分就全填「每周」或留空</div>
  <div class="cell">导入立刻生效，也认 CSV 和 JSON</div>
</div>
""")

# 安装
write("06-install", f"""
<div class="dots"></div><div class="glow"></div>
<div class="kicker">三步装好</div>
<h2>装一次，用一学期</h2>
<div class="steps">
  <div class="step"><div class="num">1</div>下载 ClassReminder 安装包</div>
  <div class="step"><div class="num">2</div>拖进「应用程序」，右键打开</div>
  <div class="step"><div class="num">3</div>导入课表，菜单栏开始工作</div>
</div>
<div class="side"><img src="{p('preview.png')}" style="width:392px;height:auto"></div>
<div class="foot">macOS 13+ · 开源 MIT · 不联网 · 无第三方依赖</div>
""")
