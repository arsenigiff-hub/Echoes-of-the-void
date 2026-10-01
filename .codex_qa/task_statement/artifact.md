# Reference

- Path: C:\Users\arseni\Downloads\Пример постановки задачи (1).docx
- SHA-256: 6D3B63E49EC0FA0B3D90D26941B69303C48233700C98F83D98EA38F0479FB724
- Page count: 1
- Section count: 1
- Visual evidence: D:\godot\GodotGame-main\.codex_qa\task_statement\reference-page.png
- Style evidence: D:\godot\GodotGame-main\.codex_qa\task_statement\reference_styles.json
- Canonical renderer status: unresolved because bundled LibreOffice is absent; reference was exported read-only with Microsoft Word and rasterized with bundled Poppler.

# Page system

- A4 portrait, 8.27 x 11.69 inches.
- Margins: left 1.18 inches, right 0.59 inches, top 0.79 inches, bottom 0.59 inches.
- Header and footer distances: 0.5 inches. No visible header or footer content.
- One section, no columns, no first-page variation.

# Typography

- All visible text uses Times New Roman, 14 pt, black, regular weight.
- First two lines are left aligned, single-spaced, with no paragraph spacing.
- Body paragraphs are justified, single-spaced, first-line indent approximately 0.49 inches, with no paragraph spacing.
- Numbered list paragraphs are justified, single-spaced, left indent approximately 0.74 inches, hanging indent approximately 0.25 inches.

# Lists and tables

- No tables.
- One decimal numbered list using numbering definition numId 1 at level 0.
- Preserve the existing numbering definition, indentation, and number punctuation.

# Components and content flow

- Line 1: editable project name slot; replace “Пример”.
- Line 2: editable document-role slot; retain “Постановка задачи:”.
- Body paragraphs: editable task description, purpose, gameplay loop, controls, and subsystem requirements.
- Lead-in paragraph before the list: editable introduction to additional requirements.
- Numbered list: editable additional functions and quality requirements.
- No images, captions, fields, content controls, headers, footers, comments, or drawings.

# Slot map

- word/document.xml paragraphs 1–2: replace title block while preserving paragraph and run formatting.
- word/document.xml paragraphs 3–8: replace with new body content and clone the same body paragraph pattern for additional paragraphs when needed.
- word/document.xml paragraphs 9–12: replace numbered requirements and clone the numId 1 paragraph pattern when needed.
- Final empty paragraph may remain empty.

# Package preservation

- Preserve numbering.xml, settings.xml, fontTable.xml, styles.xml, relationships, theme, package relationships, and content types.
- The package has no media, headers, footers, comments, footnotes, or custom XML parts.
- Only word/document.xml may change for content and cloned paragraph patterns.

# Fidelity gates

- Reference file must remain unchanged and retain its recorded SHA-256.
- Final document must retain page size, margins, Times New Roman 14 pt typography, justified body text, first-line indents, and numbered-list formatting.
- No clipping, overlap, broken numbering, orphaned heading, or unexpected font substitution.
- The result may extend to a second page because the user explicitly requested a slightly longer document.
