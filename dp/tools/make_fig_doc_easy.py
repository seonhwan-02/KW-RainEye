"""DP 단계별 결과 그림 해설, 쉬운 판(핵심 문장 + 고등학생 눈높이 설명) Word 문서를 만든다.
사용: python make_fig_doc_easy.py <쉬운 해설 JSON> <K-RainEye 폴더> <출력 docx>
쉬운 해설 JSON은 그림마다 {id, step, img, title, keypoints[], sections[{heading, text}], one_key} 목록이다.
자세한 판은 make_fig_doc.py 가 만든다.
"""
import sys, json, os
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
GRAY = RGBColor(0x5C, 0x6B, 0x7A)

doc = Document()
sec = doc.sections[0]
sec.page_height, sec.page_width = Cm(29.7), Cm(21.0)
sec.left_margin = sec.right_margin = Cm(2.2)
sec.top_margin = sec.bottom_margin = Cm(2.0)

st = doc.styles['Normal']
st.font.name = FONT
st.font.size = Pt(10.5)
st.element.rPr.rFonts.set(qn('w:eastAsia'), FONT)
st.paragraph_format.space_after = Pt(4)
st.paragraph_format.line_spacing = 1.35
for name, size in [('Heading 1', 15), ('Heading 2', 13), ('Heading 3', 11)]:
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


def para(text, bold=False, size=None, color=None, align=None):
    p = doc.add_paragraph()
    r = p.add_run(text)
    r.bold = bold
    if size: r.font.size = Pt(size)
    if color: r.font.color.rgb = color
    if align is not None: p.alignment = align
    return p


def heading(text, level):
    h = doc.add_heading(text, level=level)
    h.paragraph_format.keep_with_next = True
    return h


def keybox(title, lines, fill='EAF2FB'):
    """핵심 문장 상자: 제목 한 줄 + '- 문장' 목록."""
    t = doc.add_table(rows=1, cols=1)
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    c = t.cell(0, 0)
    shade(c, fill)
    p = c.paragraphs[0]
    r = p.add_run(title); r.bold = True; r.font.color.rgb = NAVY
    for ln in lines:
        q = c.add_paragraph()
        q.paragraph_format.space_after = Pt(2)
        q.add_run('- ' + ln).bold = True
    doc.add_paragraph().paragraph_format.space_after = Pt(0)


def table(header, rows, widths):
    t = doc.add_table(rows=1, cols=len(header))
    t.style = 'Table Grid'
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    for i, h in enumerate(header):
        c = t.rows[0].cells[i]
        c.paragraphs[0].add_run(h).bold = True
        shade(c, 'D9E2EC')
    for row in rows:
        cells = t.add_row().cells
        for i, v in enumerate(row):
            cells[i].paragraphs[0].add_run(str(v)).font.size = Pt(9.5)
    for row in t.rows:
        for i, w in enumerate(widths):
            row.cells[i].width = Cm(w)
    doc.add_paragraph().paragraph_format.space_after = Pt(0)


# ---------------- 앞부분
para('DP 지향 계획 결과 그림, 쉽게 읽기', bold=True, size=20, color=NAVY)
para('K-RainEye 시뮬레이션 1~4단계 그림 8장을 핵심 문장과 쉬운 설명으로 정리했어요.', size=11)
para('작성 2026-10-25 · 숫자는 모두 결과 파일에서 확인한 값을 읽기 쉽게 반올림했어요. 자세한 판: DP_단계별_그림_해설_상세.docx',
     size=9, color=GRAY)

heading('이 실험, 한마디로', 1)
keybox('핵심', [
    '작은 위성이 몸을 기울여 센 비를 겨냥한다.',
    '30~60분 묵은 비 지도(힌트)를 보고 어디를 볼지 정한다.',
    'DP는 기울이는 순서 전체를 미리 짜는 계산법이다.',
    '바로 아래만 볼 때보다 센 비를 약 2배 더 잡았다.',
])
para('K-RainEye 위성은 장마철에 한반도 서쪽 바다 위를 몇 분 만에 휙 지나가요. 레이더는 손전등처럼 좁은 곳만 비추기 때문에, '
     '그냥 바로 아래만 보면 센 비구름을 그냥 지나치기 쉬워요. 그래서 위성이 몸을 최대 10°까지 기울여 비구름 쪽을 비추게 해요.')
para('문제는 "어디로 기울일지"예요. 위성은 미리 받은 비 지도(힌트)를 보고 정하는데, 이 지도는 30~60분 전 모습이라 그사이 비가 '
     '움직이거나 약해져요. 또 한 번 기울이면 자리 잡는 데 몇 초가 걸리고 그동안은 못 재요. DP는 이런 사정을 다 따져서 '
     '"언제 몇 도로 기울일지" 길 전체를 미리 짜 주는 계산법이에요. 아래 그림 8장은 이 방법이 정말 효과가 있는지 단계별로 확인한 결과예요.')

heading('1~4단계, 이렇게 진행했어요', 1)
keybox('핵심', [
    '1단계 train: 힌트를 얼마나 믿을지 점수표를 만든다.',
    '2단계 demo: 한 번 지나가는 장면으로 원리를 본다.',
    '3단계 validate: 장마철 전체로 성적을 매긴다.',
    '4단계 realistic: 거친 실시간 힌트로 다시 시험한다.',
])
para('네 단계는 시험 준비 과정과 비슷해요. 공부하고(1), 예제 한 문제를 풀어 보고(2), 모의고사를 보고(3), '
     '실전과 비슷한 조건에서 한 번 더 봐요(4).')
heading('1단계 train: 점수표 만들기', 3)
para('2023년 장마철 자료로 "힌트 지도에서 이만큼 세게 보인 곳이 30분 뒤 실제로 센 비였을 확률"을 세어 표로 만들어요. '
     '예를 들어 힌트가 "막 센 비"라고 한 곳은 실제로 약 52%만 센 비였어요. 이 표가 DP가 "여기를 보면 몇 점"을 매기는 점수표가 돼요.')
heading('2단계 demo: 한 번 지나가는 장면으로 원리 보기', 3)
para('위성이 바다 위를 한 번 지나가는 몇 분을 골라, DP가 언제 몇 도로 기울이는지 그림으로 들여다봐요. '
     '이 장면에서는 센 비가 마침 바로 아래에 있어서 DP(10번)가 바로 아래만 보기(11번)보다 1번 덜 잡았어요. '
     '한 장면은 운이 크게 작용하니, 진짜 실력은 3·4단계에서 봐요.')
heading('3단계 validate: 장마철 전체 성적표', 3)
para('2023년과 2024년 장마철 전체에서 몇 번 센 비를 잡았는지 방식끼리 비교해요. 2024년은 점수표를 만들 때 쓰지 않은 '
     '"처음 보는 해"라서 진짜 실력을 확인할 수 있어요. 제안 방식은 바로 아래만 볼 때보다 2.45배(2023), 2.73배(2024) 잡았어요. '
     '다만 힌트로도 정확한 정밀판 지도를 써서 실제보다 유리한 조건이에요.')
heading('4단계 realistic: 거친 힌트로 다시 시험', 3)
para('힌트를 실제 운용에 가까운, 바로 만든 거친 지도(실시간판)로 바꿔서 3단계를 다시 해요. 성적은 조금 내려갔지만 '
     '여전히 바로 아래만 볼 때보다 센 비를 약 2배 잡았어요. 힌트에서 센 점 하나씩 찍는 기존 방식은 1.1~1.2배에 그쳤어요.')

heading('알아 두면 좋은 말', 1)
table(['말', '쉬운 뜻'], [
    ['힌트(큐)', '관측 전에 받는 비 지도. "여기를 보라"는 쪽지 같은 것. 30~60분 묵은 정보예요'],
    ['호우 / 강수', '호우 = 1시간에 10 mm 넘게 오는 센 비, 강수 = 1시간에 1 mm 넘게, 비가 오기는 하는 상태'],
    ['천저 고정', '기울이지 않고 바로 아래만 보기. 다른 방법을 잴 때 기준(1배)이에요'],
    ['기존 방식', '힌트 지도에서 센 점을 하나씩 찍어서 겨냥하기'],
    ['DP', '기울이는 순서 전체를 미리 짜서 점수 합이 가장 큰 길을 고르는 계산법(동적계획법)'],
    ['위치고정 / 나우캐스트', '위치고정 = 힌트 지도를 그대로 믿기, 나우캐스트 = 비구름이 움직이는 방향으로 지도를 옮겨서 쓰기'],
    ['완벽 정보', '실제 비를 미리 안다고 쳤을 때의 최고 기록. 넘을 수 없는 천장이에요'],
    ['정밀판 / 실시간판', '정밀판(Final) = 나중에 보정한 정확한 비 지도(채점용 정답), 실시간판(Early) = 바로 만든 거친 비 지도'],
    ['몇 배(이득)', '장마철 동안 잡은 센 비 관측 수 ÷ 바로 아래만 봤을 때의 수'],
], [3.6, 13.0])

# ---------------- 그림별
ORDER = [
    ('1단계 train: 힌트 믿을 만한지 점수표 만들기', '2023년 자료로 "힌트에서 이만큼 세게 보이면 실제로 센 비일 확률"을 세어 점수표를 만들어요.', ['s1_calib']),
    ('2단계 demo: 한 번 지나가는 장면으로 원리 보기', '위성이 한 번 지나가는 몇 분 동안 DP가 어떤 길을 고르는지 들여다봐요.', ['s2_reward', 's2_map']),
    ('3단계 validate: 장마철 전체 성적표', '2023년과 2024년 장마철 전체로 성적을 매겨요. 힌트도 정밀판이라 유리한 조건이에요.', ['s3_gain', 's3_bands']),
    ('4단계 realistic: 거친 힌트로 다시 시험', '힌트를 실제 운용에 가까운 거친 실시간판으로 바꿔서 다시 시험해요.', ['s4_calib', 's4_example', 's4_gain']),
]
fig_no = 0
summary_rows = []
for step_title, step_intro, ids in ORDER:
    doc.add_page_break()
    heading(step_title, 1)
    para(step_intro, color=GRAY)
    for fid in ids:
        n = notes.get(fid)
        if n is None:
            para(f'(그림 {fid} 해설 없음)')
            continue
        fig_no += 1
        heading(f'그림 {fig_no}. {n["title"]}', 2)
        keybox('핵심', n['keypoints'])
        p = doc.add_paragraph(); p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.add_run().add_picture(os.path.join(root, n['img']), width=Cm(15.5))
        para(f'그림 {fig_no}. {n["img"].replace(chr(92), "/")}', size=8.5, color=GRAY, align=WD_ALIGN_PARAGRAPH.CENTER)
        for s in n['sections']:
            heading(s['heading'], 3)
            para(s['text'])
        summary_rows.append([f'그림 {fig_no}', n['step'], n['one_key']])

doc.add_page_break()
heading('한눈에 정리', 1)
table(['그림', '단계', '가장 중요한 한 문장'], summary_rows, [1.7, 3.0, 11.9])

# ---------------- 묻고 답하기 (공부하며 나온 질문)
if len(sys.argv) > 4 and os.path.exists(sys.argv[4]):
    qa = json.load(open(sys.argv[4], encoding='utf-8'))
    doc.add_page_break()
    heading('묻고 답하기: 공부하면서 나온 질문', 1)
    para('그림과 제안서를 공부하면서 실제로 나온 질문과 답이에요.', color=GRAY)
    qn_no = 0
    for g in qa:
        heading(g['group'], 2)
        for it in g['items']:
            qn_no += 1
            q = doc.add_paragraph()
            q.paragraph_format.space_before = Pt(8)
            q.paragraph_format.keep_with_next = True
            r = q.add_run(f'Q{qn_no}. {it["q"]}'); r.bold = True; r.font.color.rgb = NAVY
            for line in it['a']:
                if line.startswith('- '):
                    doc.add_paragraph(line[2:], style='List Bullet')
                else:
                    para(line)
doc.save(out_path)
print('saved', out_path, 'figures', fig_no)
