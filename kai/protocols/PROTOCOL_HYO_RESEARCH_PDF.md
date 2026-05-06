# PROTOCOL_HYO_RESEARCH_PDF.md
# Version: 1.0 | Owner: Kai | Created: 2026-05-06
# Reference when creating any Hyo Research PDF document.

---

## Purpose

Every research PDF Hyo expects follows the same design system. This protocol defines the exact
colors, fonts, layout, section structure, and ReportLab patterns to use. Read this before writing
a single line of PDF generation code.

---

## Design System

### Colors

| Name       | Hex       | Usage                                                     |
|------------|-----------|-----------------------------------------------------------|
| Navy       | `#1a1f3a` | Background panels, chapter banners, cover background      |
| Gold       | `#c9a027` | Accent rules, labels (CHAPTER N, HYO RESEARCH), headings  |
| Dark Gold  | `#a07818` | Lighter gold for secondary elements                       |
| White      | `#ffffff`  | Page background                                           |
| Light Gray | `#f0f0f0` | Code block backgrounds, alternating table rows            |
| Mid Gray   | `#888888` | Footer text, captions                                     |
| Dark Text  | `#1a1f3a` | Body text (navy doubles as main text color)               |

### Typography

| Role            | Font Family     | Size    | Weight |
|-----------------|-----------------|---------|--------|
| Cover title     | Helvetica-Bold  | 36pt    | Bold   |
| Cover subtitle  | Helvetica       | 16pt    | Normal |
| Chapter label   | Helvetica-Bold  | 10pt    | Bold   |
| Chapter title   | Helvetica-Bold  | 28pt    | Bold   |
| Section heading | Helvetica-Bold  | 16pt    | Bold   |
| Sub-heading     | Helvetica-Bold  | 13pt    | Bold   |
| Body            | Helvetica       | 11pt    | Normal |
| Footer          | Helvetica       | 8pt     | Normal |
| Code block      | Courier         | 9pt     | Normal |
| Table header    | Helvetica-Bold  | 10pt    | Bold   |
| Table body      | Helvetica       | 9pt     | Normal |

### Page Layout

- **Page size**: Letter (8.5 × 11 in, 612 × 792 pt)
- **Margins**: 72pt top, 72pt bottom, 72pt left, 72pt right (1 inch all sides)
- **Footer height**: 20pt above bottom margin
- **Top rule on non-cover pages**: Gold rule (2pt) at top of content area

---

## Page Structure

### Cover Page (page 1)

Elements in order (top to bottom):
1. **Navy panel** — fills top 45% of page
2. Inside navy panel:
   - `HYO RESEARCH` — gold, 10pt, bold, letter-spacing, centered near top of panel
   - Title — white, 36pt, bold, centered, 40pt below label
   - Gold horizontal rule — 1pt, 420pt wide, 20pt below title
   - Subtitle — white, 16pt, normal, centered, 15pt below rule
3. Gold horizontal rule below panel — 2pt, full content width
4. Author line — navy, 12pt, "Prepared by [author]", left-aligned
5. Date line — gray, 10pt, right-aligned
6. Footer only: "Hyo Research | [document title]" left, "CONFIDENTIAL" right

### Chapter Pages (chapter headings via `##`)

When `##` heading is parsed:
1. Insert `PageBreak()` before the chapter block
2. **Navy rectangle** — full content width × 80pt, navy fill
3. Inside rectangle:
   - `CHAPTER N` — gold, 10pt, bold, all caps, 20pt from left, 20pt from top of rect
   - Chapter title — white, 28pt, bold, 20pt from left, 15pt below label
4. Gold rule — 2pt, full width, immediately after rectangle
5. Body text continues normally below

### Non-Chapter Pages (pages 2+, non-chapter)

- Top: gold rule (2pt, full content width)
- Body flows normally
- Footer: "Hyo Research | [Document Title]" left, "Page N" right, in gray 8pt

---

## Table of Contents

After the cover page, before chapter 1:
- Title: "Table of Contents" — section heading style
- Gold rule below title
- Each chapter as a two-column table row: [CHAPTER N — Title] + [page number placeholder]
- Use `Table` with `LINEBELOW` rule between rows

---

## ReportLab Implementation

### Required Imports

```python
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import inch
from reportlab.lib import colors
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle,
    HRFlowable, PageBreak, KeepTogether
)
from reportlab.lib.colors import HexColor
```

### Color Constants

```python
NAVY      = HexColor('#1a1f3a')
GOLD      = HexColor('#c9a027')
WHITE     = colors.white
LIGHT_GRAY = HexColor('#f0f0f0')
MID_GRAY  = HexColor('#888888')
```

### Canvas Callbacks (Footer + Top Rule)

```python
def on_first_page(canvas, doc):
    """Cover page: footer only, no top rule."""
    canvas.saveState()
    canvas.setFont('Helvetica', 8)
    canvas.setFillColor(MID_GRAY)
    canvas.drawString(doc.leftMargin, doc.bottomMargin - 14,
                      f"Hyo Research | {DOC_TITLE}")
    canvas.drawRightString(doc.width + doc.leftMargin, doc.bottomMargin - 14,
                           "CONFIDENTIAL")
    canvas.restoreState()

def on_page(canvas, doc):
    """Non-cover pages: top gold rule + footer with page number."""
    canvas.saveState()
    # Top rule
    canvas.setStrokeColor(GOLD)
    canvas.setLineWidth(2)
    canvas.line(doc.leftMargin, doc.height + doc.topMargin + 4,
                doc.width + doc.leftMargin, doc.height + doc.topMargin + 4)
    # Footer
    canvas.setFont('Helvetica', 8)
    canvas.setFillColor(MID_GRAY)
    canvas.drawString(doc.leftMargin, doc.bottomMargin - 14,
                      f"Hyo Research | {DOC_TITLE}")
    canvas.drawRightString(doc.width + doc.leftMargin, doc.bottomMargin - 14,
                           f"Page {doc.page}")
    canvas.restoreState()
```

### Cover Page Story Elements

```python
def build_cover(title, subtitle, author):
    story = []
    # Cover block is drawn via canvas (not flowable) in on_first_page override
    # Use a large Spacer to push past the navy panel area
    story.append(Spacer(1, 340))  # adjust to clear navy panel
    story.append(HRFlowable(width='100%', thickness=2, color=GOLD))
    story.append(Spacer(1, 14))
    story.append(Paragraph(f"Prepared by {author}", body_style))
    # TOC starts on next page
    story.append(PageBreak())
    return story
```

NOTE: The navy cover panel must be drawn directly on the canvas in `on_first_page`.
Draw it as a `canvas.rect(...)` with `fill=1, stroke=0` BEFORE any flowables render.

Pattern for drawing cover panel in `on_first_page`:
```python
# Navy panel (top 45% of page)
panel_height = 792 * 0.45
canvas.setFillColor(NAVY)
canvas.rect(0, 792 - panel_height, 612, panel_height, fill=1, stroke=0)

# HYO RESEARCH label
canvas.setFont('Helvetica-Bold', 10)
canvas.setFillColor(GOLD)
canvas.drawCentredString(306, 792 - 80, "HYO RESEARCH")

# Title
canvas.setFont('Helvetica-Bold', 36)
canvas.setFillColor(WHITE)
canvas.drawCentredString(306, 792 - 140, TITLE_LINE_1)  # split long titles

# Gold rule
canvas.setStrokeColor(GOLD)
canvas.setLineWidth(1)
canvas.line(96, 792 - 195, 516, 792 - 195)

# Subtitle
canvas.setFont('Helvetica', 16)
canvas.setFillColor(WHITE)
canvas.drawCentredString(306, 792 - 225, SUBTITLE)
```

### Chapter Block (drawn via flowable Table)

```python
def chapter_block(n, title):
    """Returns a list of flowables for a chapter opening."""
    label = f"CHAPTER {n}"
    # Navy box with label + title inside
    data = [[Paragraph(f'<font color="#c9a027"><b>{label}</b></font><br/>'
                       f'<font color="white"><b><font size="24">{title}</font></b></font>',
                       body_style)]]
    t = Table(data, colWidths=[468])
    t.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,-1), NAVY),
        ('PADDING', (0,0), (-1,-1), 16),
        ('BOX', (0,0), (-1,-1), 0, NAVY),
    ]))
    return [PageBreak(), t,
            HRFlowable(width='100%', thickness=2, color=GOLD),
            Spacer(1, 12)]
```

### Markdown Parsing Rules

When parsing markdown source to generate story flowables:

| Markdown Pattern       | Action                                                      |
|------------------------|-------------------------------------------------------------|
| `## Chapter Title`     | chapter_block(n, title) — increments chapter counter        |
| `### Sub-heading`      | Paragraph with subheading_style                             |
| `- bullet` / `* bullet`| Paragraph with bullet_style, `• ` prefix                  |
| `1. numbered`          | Paragraph with numbered_style, `N. ` prefix                 |
| `> blockquote`         | Paragraph with blockquote_style (left border via padding)   |
| `` `code block` ``     | Code block via Table with LIGHT_GRAY background             |
| `| table |`            | Table with NAVY header row, alternating gray rows           |
| `**bold**`             | `<b>text</b>` in Paragraph XML                              |
| `*italic*`             | `<i>text</i>` in Paragraph XML                              |
| `` `inline code` ``    | `<font name="Courier" size="9">text</font>` in Paragraph XML|

**CRITICAL — Never use Unicode subscript/superscript characters** (₀₁₂, ⁰¹²). Use ReportLab XML tags:
- Subscript: `<sub>2</sub>` (e.g., H<sub>2</sub>O)
- Superscript: `<super>2</super>` (e.g., x<super>2</super>)

### SimpleDocTemplate Setup

```python
doc = SimpleDocTemplate(
    output_path,
    pagesize=letter,
    rightMargin=72, leftMargin=72,
    topMargin=72, bottomMargin=72,
    title=DOC_TITLE,
    author="Hyo Research"
)
doc.build(story, onFirstPage=on_first_page, onLaterPages=on_page)
```

---

## Output Checklist

Before delivering any Hyo Research PDF, verify:

- [ ] Cover: navy panel, "HYO RESEARCH" gold label, title in white, gold rule, subtitle
- [ ] TOC: all chapters listed with page references
- [ ] Each chapter: opens on new page, navy block with CHAPTER N label, gold rule below
- [ ] Non-cover pages: top gold rule present
- [ ] Footer: "Hyo Research | [Title]" left, "Page N" right (except cover)
- [ ] No Unicode subscript/superscript characters — only ReportLab XML tags
- [ ] No broken characters (black boxes) from missing glyphs
- [ ] File opens cleanly in Preview / Acrobat
- [ ] PDF metadata: title and author set correctly

---

## Reference Script

The canonical implementation is at:
`/sessions/gifted-happy-cori/build_marina_pdf.py`

This script generated the first approved Hyo Research PDF (`marina-wyss-complete-course-guide.pdf`).
Use it as a base for any new research PDF. The key functions are:
- `build_cover()` — cover page story
- `build_toc()` — table of contents
- `build_chapter()` — chapter opener block
- `parse_markdown_to_story()` — converts .md source to flowable list
- `on_first_page()` / `on_page()` — canvas callbacks for footer + top rule

---

## Skill Registration

This protocol is registered as a Cowork skill descriptor. When Hyo asks for a research PDF,
Kai reads this file first — every time, no exceptions. The `.claude/skills/` directory is
read-only from the sandbox, so the canonical location is:

`kai/protocols/PROTOCOL_HYO_RESEARCH_PDF.md` (this file)

If a `.claude/skills/hyo-research-pdf/SKILL.md` is ever created on the Mac,
its `description` field should reference this file as the implementation authority.

---

## Trigger

Hyo says: "create a research PDF" / "format this as a Hyo Research document" / "make a PDF like the Marina Wyss one"
→ Kai reads this protocol → copies `build_marina_pdf.py` → modifies title/author/source file → runs → delivers

---

*Last updated: 2026-05-06 | Kai*
