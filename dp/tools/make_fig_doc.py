"""DP 단계별 결과 그림 해설 Word 문서를 만든다.
사용: python make_fig_doc.py <해설 JSON> <K-RainEye 폴더> <출력 docx>
해설 JSON은 그림마다 {id, step, img, title, one_line, what, axes, legend, how_to_read,
findings[{text, source}], caution, proposal_link} 를 담은 목록이다.
"""
import sys, json, os, re
from docx import Document
from docx.shared import Pt, Cm, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

notes_path, root, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
notes = {n['id']: n for n in json.load(open(notes_path, encoding='utf-8'))}

FONT = 'Malgun Gothic'
NAVY = RGBColor(0x1F, 0x3B, 0x57)

doc = Document()
sec = doc.sections[0]
sec.page_height, sec.page_width = Cm(29.7), Cm(21.0)
sec.left_margin = sec.right_margin = Cm(2.0)
sec.top_margin = sec.bottom_margin = Cm(2.0)

st = doc.styles['Normal']
st.font.name = FONT
st.font.size = Pt(10)
st.element.rPr.rFonts.set(qn('w:eastAsia'), FONT)
st.paragraph_format.space_after = Pt(3)
st.paragraph_format.line_spacing = 1.25
for name, size in [('Title', 20), ('Heading 1', 15), ('Heading 2', 12.5), ('Heading 3', 10.5)]:
    s = doc.styles[name]
    s.font.name = FONT
    s.font.size = Pt(size)
    s.font.color.rgb = NAVY
    s.element.rPr.rFonts.set(qn('w:eastAsia'), FONT)


def shade(cell, hex_fill):
    tcPr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement('w:shd')
    shd.set(qn('w:val'), 'clear'); shd.set(qn('w:color'), 'auto'); shd.set(qn('w:fill'), hex_fill)
    tcPr.append(shd)


def para(text, bold=False, size=None, color=None, align=None, style=None):
    p = doc.add_paragraph(style=style)
    r = p.add_run(text)
    r.bold = bold
    if size: r.font.size = Pt(size)
    if color: r.font.color.rgb = color
    if align: p.alignment = align
    return p


def heading(text, level):
    h = doc.add_heading(text, level=level)
    h.paragraph_format.keep_with_next = True
    return h


def label(text):
    p = para(text, bold=True, size=10.5, color=NAVY)
    p.paragraph_format.space_before = Pt(6)
    p.paragraph_format.keep_with_next = True


def bullets(items, numbered=False):
    for t in items:
        doc.add_paragraph(t, style='List Number' if numbered else 'List Bullet')


def callout(text):
    t = doc.add_table(rows=1, cols=1)
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    c = t.cell(0, 0)
    shade(c, 'E8F0F8')
    c.paragraphs[0].add_run(text).bold = True
    doc.add_paragraph().paragraph_format.space_after = Pt(0)


def table(header, rows, widths, head_fill='D9E2EC'):
    t = doc.add_table(rows=1, cols=len(header))
    t.style = 'Table Grid'
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    for i, h in enumerate(header):
        c = t.rows[0].cells[i]
        c.paragraphs[0].add_run(h).bold = True
        shade(c, head_fill)
    for row in rows:
        cells = t.add_row().cells
        for i, v in enumerate(row):
            cells[i].paragraphs[0].add_run(str(v)).font.size = Pt(9)
    for row in t.rows:
        for i, w in enumerate(widths):
            row.cells[i].width = Cm(w)
    doc.add_paragraph().paragraph_format.space_after = Pt(0)
    return t


# ---------------- 표지와 개요
para('DP 지향 계획 단계별 결과 그림 해설', bold=True, size=20, color=NAVY)
para('K-RainEye 표적 지향 관측 시뮬레이션 1~4단계 그림 8장을 하나씩 읽는 법', size=11)
para('작성 2026-10-25 · 숫자는 모두 out 폴더의 결과 파일(summary.txt, key_*.json, methods.csv)에서 확인한 값', size=9,
     color=RGBColor(0x5C, 0x6B, 0x7A))

heading('먼저 알아 둘 것', 1)
label('단계와 파일')
table(['단계', '스크립트', '결과 폴더', '하는 일', '그림'], [
    ['1 train', 'dp_step1_train.m', 'out/dp_step1_train', '2023 자료로 "큐 강도 → 30·60분 뒤 실제 호우 확률" 학습표 만들기', '1장'],
    ['2 demo', 'dp_step2_demo.m', 'out/dp_step2_demo', '통과 한 번으로 DP 원리 보기', '2장'],
    ['3 validate', 'dp_step3_validate.m', 'out/dp_step3_validate', '2023(학습한 해)·2024(처음 보는 해) 시즌 전체 성능', '2장'],
    ['4 realistic', 'dp_step4_realistic.m', 'out/dp_step4_realistic', '큐만 실시간판(IMERG Early)으로 바꿔 다시 계산', '3장'],
], [2.0, 3.6, 3.6, 6.0, 1.2])

label('용어')
table(['용어', '뜻'], [
    ['큐', '관측 전에 받는 비 지도. "여기를 보라"는 정보. 여기서는 위성 강수 자료 IMERG로 흉내 낸다'],
    ['큐 장면 나이', '큐 지연 15분이라 큐 장면은 관측보다 30분 또는 60분 앞선 IMERG 30분 칸이다'],
    ['강수 / 호우', '강수 = 시간당 1 mm 이상, 호우 = 시간당 10 mm 이상'],
    ['천저 고정', '위성을 기울이지 않고 바로 아래만 보는 방식. 이득 계산의 기준(1.00배)'],
    ['기존 방식', '큐에서 시간당 10 mm 이상인 센 점을 하나씩 찍어 겨냥하는 방식'],
    ['DP 위치고정 / 나우캐스트', 'DP(동적계획법)로 빔 경로 전체를 계획. 위치고정은 큐 장면을 그대로, 나우캐스트는 비구름 이동 방향으로 옮겨서 쓴다'],
    ['DP 완벽 정보', '실제 비를 미리 안다고 친 DP. 기동 제약 안에서 낼 수 있는 상한'],
    ['IMERG Final / Early', 'Final = 앞뒤 시간 자료와 우량계로 보정한 정밀판(채점용 정답). Early = 그 시각까지 자료로 만든 거친 실시간판'],
    ['이득(배수)', '시즌 동안 잡은 호우 프로파일 수 ÷ 천저 고정의 수'],
], [4.0, 12.4])

# ---------------- 그림별 해설
ORDER = [
    ('1단계 train: 학습표 만들기', ['s1_calib']),
    ('2단계 demo: 통과 한 번으로 원리 보기', ['s2_reward', 's2_map']),
    ('3단계 validate: 시즌 전체 성능 (정밀판 큐)', ['s3_gain', 's3_bands']),
    ('4단계 realistic: 실시간판 큐로 다시 시험', ['s4_calib', 's4_example', 's4_gain']),
]
fig_no = 0
summary_rows = []
for si, (step_title, ids) in enumerate(ORDER, start=1):
    doc.add_page_break()
    heading(step_title, 1)
    for fid in ids:
        n = notes.get(fid)
        if n is None:
            para(f'(그림 {fid} 해설 없음)')
            continue
        fig_no += 1
        title = re.sub(r'\s*\(\d단계\)$', '', re.sub(r'^\d단계[^:]*:\s*', '', n['title']))
        heading(f'그림 {fig_no}. {title}', 2)
        callout('한 줄 결론: ' + n['one_line'])
        img = os.path.join(root, n['img'])
        p = doc.add_paragraph(); p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.add_run().add_picture(img, width=Cm(16.0))
        cap = para(f'그림 {fig_no}. {n["img"].replace(chr(92), "/")}', size=8.5, color=RGBColor(0x5C, 0x6B, 0x7A),
                   align=WD_ALIGN_PARAGRAPH.CENTER)
        label('무엇을 보여 주나'); para(n['what'])
        label('축'); bullets(n['axes'])
        label('선·색·기호'); bullets(n['legend'])
        label('읽는 순서'); bullets(n['how_to_read'], numbered=True)
        label('핵심 발견')
        table(['내용', '숫자 출처'], [[f['text'], f['source']] for f in n['findings']], [12.4, 4.0])
        label('주의할 점'); bullets(n['caution'])
        label('제안서에 쓰는 법'); para(n['proposal_link'])
        summary_rows.append([f'그림 {fig_no}', n['step'], n['one_line']])

doc.add_page_break()
heading('한눈에 정리', 1)
table(['그림', '단계', '한 줄 결론'], summary_rows, [1.6, 2.8, 12.0])
doc.save(out_path)
print('saved', out_path, 'figures', fig_no)
