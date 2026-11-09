import os
import sys

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8')

import docx
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_ALIGN_VERTICAL
from docx.oxml import parse_xml, OxmlElement
from docx.oxml.ns import nsdecls, qn

class DocxReportBuilder:
    def __init__(self, title, subtitle):
        self.doc = docx.Document()
        self._setup_page()
        self._setup_styles()
        self._add_header(title, subtitle)

    def _setup_page(self):
        for section in self.doc.sections:
            section.top_margin = Pt(50.4)
            section.bottom_margin = Pt(50.4)
            section.left_margin = Pt(57.6)
            section.right_margin = Pt(57.6)
            section.page_width = Pt(612.0)
            section.page_height = Pt(792.0)

    def _setup_styles(self):
        styles = self.doc.styles

        # Normal
        normal = styles['Normal']
        normal.font.name = 'Times New Roman'
        normal.font.size = Pt(12)
        normal.font.color.rgb = RGBColor(0, 0, 0)
        normal.paragraph_format.line_spacing = 1.15
        normal.paragraph_format.space_after = Pt(4)

        # Title
        try:
            title_s = styles['Title']
        except KeyError:
            title_s = styles.add_style('Title', docx.enum.style.WD_STYLE_TYPE.PARAGRAPH)
        title_s.font.name = 'Times New Roman'
        title_s.font.size = Pt(22)
        title_s.font.bold = True
        title_s.font.color.rgb = RGBColor(0, 0, 0)
        title_s.paragraph_format.space_before = Pt(0)
        title_s.paragraph_format.space_after = Pt(6)

        # Heading 1
        h1 = styles['Heading 1']
        h1.font.name = 'Times New Roman'
        h1.font.size = Pt(16)
        h1.font.bold = True
        h1.font.color.rgb = RGBColor(0, 0, 0)
        h1.paragraph_format.space_before = Pt(14)
        h1.paragraph_format.space_after = Pt(6)
        h1.paragraph_format.keep_with_next = True

        # Heading 2
        h2 = styles['Heading 2']
        h2.font.name = 'Times New Roman'
        h2.font.size = Pt(12)
        h2.font.bold = True
        h2.font.color.rgb = RGBColor(0, 0, 0)
        h2.paragraph_format.space_before = Pt(10)
        h2.paragraph_format.space_after = Pt(4)
        h2.paragraph_format.keep_with_next = True

        # Caption
        try:
            caption_s = styles['Caption']
        except KeyError:
            caption_s = styles.add_style('Caption', docx.enum.style.WD_STYLE_TYPE.PARAGRAPH)
        caption_s.font.name = 'Times New Roman'
        caption_s.font.size = Pt(10)
        caption_s.font.bold = True
        caption_s.font.color.rgb = RGBColor(0, 0, 0)
        caption_s.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
        caption_s.paragraph_format.space_before = Pt(4)
        caption_s.paragraph_format.space_after = Pt(8)

    def _add_header(self, title, subtitle):
        p_title = self.doc.add_paragraph(title, style='Title')
        p_title.alignment = WD_ALIGN_PARAGRAPH.LEFT
        
        p_sub = self.doc.add_paragraph(subtitle, style='Normal')
        p_sub.runs[0].font.name = 'Times New Roman'
        p_sub.runs[0].font.size = Pt(12)
        p_sub.paragraph_format.space_after = Pt(8)

    def add_heading_1(self, text):
        return self.doc.add_paragraph(text, style='Heading 1')

    def add_heading_2(self, text):
        return self.doc.add_paragraph(text, style='Heading 2')

    def add_paragraph(self, text, bold_prefix=None, space_after=4):
        p = self.doc.add_paragraph(style='Normal')
        p.paragraph_format.space_after = Pt(space_after)
        p.paragraph_format.line_spacing = 1.15
        if bold_prefix:
            r_bold = p.add_run(bold_prefix)
            r_bold.font.name = 'Times New Roman'
            r_bold.font.size = Pt(12)
            r_bold.font.bold = True
        r_text = p.add_run(text)
        r_text.font.name = 'Times New Roman'
        r_text.font.size = Pt(12)
        return p

    def add_image_with_caption(self, image_path, caption_text, width_inches=6.7):
        if not os.path.exists(image_path):
            print(f"[WARNING] Image path not found: {image_path}")
            # Try to see if it exists relative to workspace
            rel_path = os.path.join(os.getcwd(), image_path)
            if os.path.exists(rel_path):
                image_path = rel_path
            else:
                p_warn = self.doc.add_paragraph(f"[Изображение {image_path} временно недоступно]", style='Normal')
                p_warn.alignment = WD_ALIGN_PARAGRAPH.CENTER
                p_cap = self.doc.add_paragraph(caption_text, style='Caption')
                return

        p_img = self.doc.add_paragraph()
        p_img.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p_img.paragraph_format.space_before = Pt(6)
        p_img.paragraph_format.space_after = Pt(2)
        run = p_img.add_run()
        run.add_picture(image_path, width=Inches(width_inches))

        p_cap = self.doc.add_paragraph(caption_text, style='Caption')
        p_cap.alignment = WD_ALIGN_PARAGRAPH.CENTER

    def add_code_listing(self, label, code_text):
        p_label = self.doc.add_paragraph(style='Normal')
        p_label.paragraph_format.space_before = Pt(6)
        p_label.paragraph_format.space_after = Pt(2)
        r_lbl = p_label.add_run(label)
        r_lbl.font.name = 'Times New Roman'
        r_lbl.font.size = Pt(12)
        r_lbl.font.bold = True

        tbl = self.doc.add_table(rows=1, cols=1)
        tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
        cell = tbl.cell(0, 0)
        cell.width = Inches(6.8)

        # Style cell background and border
        tcPr = cell._tc.get_or_add_tcPr()
        shd = parse_xml(f'<w:shd {nsdecls("w")} w:fill="F4F5F7"/>')
        tcPr.append(shd)

        # subtle gray border
        borders = parse_xml(
            f'<w:tcBorders {nsdecls("w")}>\n'
            f'  <w:top w:val="single" w:sz="4" w:space="0" w:color="CCCCCC"/>\n'
            f'  <w:left w:val="single" w:sz="18" w:space="0" w:color="007ACC"/>\n'
            f'  <w:bottom w:val="single" w:sz="4" w:space="0" w:color="CCCCCC"/>\n'
            f'  <w:right w:val="single" w:sz="4" w:space="0" w:color="CCCCCC"/>\n'
            f'</w:tcBorders>'
        )
        tcPr.append(borders)

        # Add code lines
        p_code = cell.paragraphs[0]
        p_code.paragraph_format.space_before = Pt(4)
        p_code.paragraph_format.space_after = Pt(4)
        p_code.paragraph_format.line_spacing = 1.05
        
        # Clean formatting
        r_code = p_code.add_run(code_text.strip())
        r_code.font.name = 'Consolas'
        r_code.font.size = Pt(9.5)
        r_code.font.color.rgb = RGBColor(30, 30, 30)

        # spacer after table
        p_sp = self.doc.add_paragraph()
        p_sp.paragraph_format.space_before = Pt(0)
        p_sp.paragraph_format.space_after = Pt(4)

    def add_table(self, headers, rows, col_widths=None):
        tbl = self.doc.add_table(rows=len(rows) + 1, cols=len(headers))
        tbl.style = 'Table Grid'
        tbl.alignment = WD_TABLE_ALIGNMENT.CENTER

        # Headers
        hdr_row = tbl.rows[0]
        for col_idx, heading in enumerate(headers):
            cell = hdr_row.cells[col_idx]
            cell.text = heading
            tcPr = cell._tc.get_or_add_tcPr()
            shd = parse_xml(f'<w:shd {nsdecls("w")} w:fill="E8ECF0"/>')
            tcPr.append(shd)
            p = cell.paragraphs[0]
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER
            p.paragraph_format.space_before = Pt(3)
            p.paragraph_format.space_after = Pt(3)
            if p.runs:
                p.runs[0].font.name = 'Times New Roman'
                p.runs[0].font.size = Pt(11)
                p.runs[0].font.bold = True

        # Data rows
        for row_idx, row_data in enumerate(rows):
            r = tbl.rows[row_idx + 1]
            for col_idx, cell_value in enumerate(row_data):
                cell = r.cells[col_idx]
                cell.text = str(cell_value)
                p = cell.paragraphs[0]
                p.paragraph_format.space_before = Pt(3)
                p.paragraph_format.space_after = Pt(3)
                if p.runs:
                    p.runs[0].font.name = 'Times New Roman'
                    p.runs[0].font.size = Pt(10.5)

        if col_widths:
            for row in tbl.rows:
                for idx, w in enumerate(col_widths):
                    row.cells[idx].width = Inches(w)

        # spacer after table
        p_sp = self.doc.add_paragraph()
        p_sp.paragraph_format.space_before = Pt(0)
        p_sp.paragraph_format.space_after = Pt(4)

    def save(self, filepath):
        os.makedirs(os.path.dirname(os.path.abspath(filepath)), exist_ok=True)
        self.doc.save(filepath)
        print(f"Report saved successfully: {filepath}")
