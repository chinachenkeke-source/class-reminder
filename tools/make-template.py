#!/usr/bin/env python3
"""生成「课表模板.xlsx」：说明页 + 带下拉选择的课表页。"""
import sys
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.worksheet.datavalidation import DataValidation

OUT = sys.argv[1] if len(sys.argv) > 1 else "课表模板.xlsx"

BLUE = "2D6BF0"
SOFT = "5A6472"
HEAD_FILL = PatternFill("solid", fgColor=BLUE)
GREY = PatternFill("solid", fgColor="F5F6F8")
thin = Side(style="thin", color="C9D2E3")
BORDER = Border(left=thin, right=thin, top=thin, bottom=thin)
CENTER = Alignment(horizontal="center", vertical="center")

wb = Workbook()

# ══════════ 说明页 ══════════
ws = wb.active
ws.title = "填写说明"
ws.sheet_view.showGridLines = False
widths = {"A": 2, "B": 12, "C": 16, "D": 15, "E": 15, "F": 15, "G": 12, "H": 12}
for col, w in widths.items():
    ws.column_dimensions[col].width = w

def merged(row, text, font=Font(size=11), fill=None, height=None, wrap=False):
    ws.merge_cells(start_row=row, start_column=2, end_row=row, end_column=8)
    c = ws.cell(row=row, column=2, value=text)
    c.font = font
    c.alignment = Alignment(horizontal="left", vertical="center", wrap_text=wrap)
    if fill:
        for col in range(2, 9):
            ws.cell(row=row, column=col).fill = fill
    if height:
        ws.row_dimensions[row].height = height

merged(2, "上课提醒 · 课表模板", Font(size=20, bold=True, color=BLUE), height=34)
merged(3, "照着下面填，填完 → 打开 App → 菜单栏点「导入课表」选这个文件", Font(size=11, color=SOFT))

merged(5, "① 先看三句话", Font(size=13, bold=True, color=BLUE), height=24)
for i, t in enumerate([
    "一行 = 一节课。照着你自己的课表，一节一节往下填就行。",
    "时间写 07:50 这种（24 小时制）；提醒只看开始时间，节次只是给你自己看的。",
    "「周次」只有学校分单双周才用得上，不分就全填「每周」，或者干脆留空。",
]):
    merged(6 + i, t)

merged(10, "② 每列怎么填", Font(size=13, bold=True, color=BLUE), height=24)
heads = [("列名", 12), ("怎么填", 12), ("可以选（下拉）", 12)]
# 表头三列：B | C:E | F:H
ws.merge_cells("C11:E11"); ws.merge_cells("F11:H11")
for col, text in [("B", "列名"), ("C", "怎么填"), ("F", "可以选（下拉）")]:
    c = ws[f"{col}11"]
    c.value = text
    c.font = Font(bold=True, color="FFFFFF", size=11)
    c.alignment = CENTER
for col in "BCDEFGH":
    ws[f"{col}11"].fill = HEAD_FILL
    ws[f"{col}11"].border = BORDER

rows = [
    ("星期", "周一 ~ 周日", "周一 / 周二 / … / 周日"),
    ("节次", "第几节；早读、晚读、晚自习也行", "早读 / 第1节 … 第13节 / 晚读 / 晚自习"),
    ("开始时间", "这节课几点开始，提醒按它算", "07:50"),
    ("结束时间", "几点下课", "08:30"),
    ("班级", "给哪个班上课", "九3班"),
    ("科目", "上什么课", "历史"),
    ("周次", "只上单周？只上双周？还是每周都有", "每周 / 单周 / 双周 / 单双周"),
]
for i, (a, b, c_) in enumerate(rows):
    r = 12 + i
    ws.merge_cells(start_row=r, start_column=3, end_row=r, end_column=5)
    ws.merge_cells(start_row=r, start_column=6, end_row=r, end_column=8)
    for col in "BCDEFGH":
        cell = ws[f"{col}{r}"]
        cell.border = BORDER
        cell.alignment = Alignment(horizontal="left", vertical="center")
        if r % 2 == 1:
            cell.fill = GREY
    ws[f"B{r}"].value = a
    ws[f"B{r}"].font = Font(size=11, bold=True)
    ws[f"C{r}"].value = b
    ws[f"F{r}"].value = c_
    ws[f"F{r}"].font = Font(size=10, color=SOFT)
    ws.row_dimensions[r].height = 22

merged(20, "③ 单双周怎么填（重点）", Font(size=13, bold=True, color=BLUE), height=24)
for i, t in enumerate([
    "不分单双周：周次全选「每周」，或者留空 —— 每周都上，不会漏。",
    "单周、双周上的课不一样：同一节课填两行，一行「单周」一行「双周」。",
    "单双周都上、只是细节不同：周次选「单双周」，导入时自动拆成两节。",
]):
    merged(21 + i, t)

merged(25, "④ 例子（照着改）", Font(size=13, bold=True, color=BLUE), height=24)
example = [
    ("星期", "节次", "开始时间", "结束时间", "班级", "科目", "周次"),
    ("周一", "第3节", "09:25", "10:05", "九1班", "历史", "每周"),
    ("周四", "第5节", "11:25", "12:05", "九3班", "历史", "每周"),
    ("周三", "第1节", "07:50", "08:30", "九3班", "历史", "单周"),
    ("周三", "第1节", "07:50", "08:30", "九3班", "历史", "双周"),
    ("周五", "早读", "07:30", "07:50", "七1/八2班", "历史早读", ""),
]
for i, row in enumerate(example):
    r = 26 + i
    for j, v in enumerate(row):
        cell = ws.cell(row=r, column=2 + j, value=v)
        cell.border = BORDER
        cell.alignment = CENTER
        cell.font = Font(size=11, bold=(i == 0), color=("FFFFFF" if i == 0 else "333333"))
        if i == 0:
            cell.fill = HEAD_FILL
    ws.row_dimensions[r].height = 22

merged(33, "⑤ 注意", Font(size=13, bold=True, color=BLUE), height=24)
for i, t in enumerate([
    "别改第一行表头；多出来的列会被忽略。",
    "时间必须是「时:分」，7:50 能认，千万别写成 750。",
    "单双周的「第 1 周」按你学校校历算；App 面板里可以手动切周次。",
]):
    merged(34 + i, t)

ws.sheet_properties.tabColor = "9AA6B8"

# ══════════ 课表页 ══════════
sh = wb.create_sheet("课表")
cols = [("星期", 12), ("节次", 14), ("开始时间", 13), ("结束时间", 13),
        ("班级", 16), ("科目", 16), ("周次", 12)]
for i, (name, width) in enumerate(cols, start=1):
    sh.column_dimensions[chr(64 + i)].width = width
    c = sh.cell(row=1, column=i, value=name)
    c.font = Font(bold=True, color="FFFFFF", size=12)
    c.fill = HEAD_FILL
    c.alignment = CENTER
    c.border = BORDER
sh.row_dimensions[1].height = 26
sh.freeze_panes = "A2"

LAST = 200
for r in range(2, LAST + 1):
    for col in range(1, 8):
        c = sh.cell(row=r, column=col)
        c.border = BORDER
        c.alignment = CENTER
        c.font = Font(size=11)
        if r % 2 == 0:
            c.fill = GREY
    sh.cell(row=r, column=3).number_format = "@"
    sh.cell(row=r, column=4).number_format = "@"

for col, items in [
    ("A", "周一,周二,周三,周四,周五,周六,周日"),
    ("B", "早读,第1节,第2节,第3节,第4节,第5节,第6节,第7节,第8节,第9节,第10节,第11节,第12节,第13节,晚读,晚自习"),
    ("G", "每周,单周,双周,单双周"),
]:
    dv = DataValidation(type="list", formula1=f'"{items}"', allow_blank=True)
    dv.error = "从下拉列表里选一个"
    dv.errorTitle = "填错了"
    sh.add_data_validation(dv)
    dv.add(f"{col}2:{col}{LAST}")

sh.sheet_properties.tabColor = BLUE
wb.active = 1
wb.save(OUT)
print("saved", OUT)
