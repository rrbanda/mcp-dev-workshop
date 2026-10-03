---
name: workshop-certificate
description: Generates a Red Hat branded workshop completion certificate as downloadable HTML and PDF. Asks the participant for their name, collects scores from the scoring system, and produces a professional certificate. Load at workshop completion.
---

# Workshop Completion Certificate

Generate a Red Hat branded certificate of completion for participants who finish the workshop.
The certificate includes their name, date, score breakdown, tier, and achievements.

## CRITICAL RULES

1. **NEVER hardcode or assume the participant's name.**
2. **NEVER use Helm values, $USER, env vars, or any system value as the name.**
3. **ALWAYS ask the participant** using the question tool:
   "What name would you like on your certificate? (Type your full name as you'd like it to appear)"
4. **Use their response EXACTLY as typed** — preserve capitalization, spacing, accents.
5. If the response is empty or unclear, ask again.
6. Collect the score from the todowrite scoring state before generating.

## FLOW

### Step 1: Collect Name

Use the question tool:

```
╔══════════════════════════════════════════════════════╗
║  🎓 Workshop Complete! Let's create your certificate ║
╚══════════════════════════════════════════════════════╝

Before I generate your certificate, I need one thing:
```

**Question:** "What name would you like on your certificate?"
*(Free text input — the participant types their full name)*

### Step 2: Collect Scores

Read the current scoring state from the todowrite items:
- score-mastery → 🧠 MCP Mastery points
- score-build → 🔨 Build Completeness points
- score-quality → 🎯 Code Quality points
- score-fluency → 🚀 Agentic Fluency points
- score-exploration → ⭐ Exploration Bonus points
- score-total → Total and tier

### Step 3: Generate HTML Certificate

Write the certificate to `/projects/mcp-dev-workshop/certificate.html`

The HTML MUST use:
- **Red Hat Display** font for headings (Google Fonts)
- **Red Hat Text** font for body (Google Fonts)
- **Colors:** `#EE0000` (Red Hat Red), `#151515` (Dark), `#FFFFFF` (White), `#3E8635` (Green for bars)
- **Layout:** Landscape letter (11in × 8.5in)
- **Print CSS:** `@page { size: landscape; margin: 0; }` with `-webkit-print-color-adjust: exact`
- **Red Hat logo:** Inline SVG fedora hat in `#EE0000`

### Step 4: Generate PDF

Use Python to create a PDF directly:

```bash
cd /projects/mcp-dev-workshop
pip install -q fpdf2 2>/dev/null

python3 << 'CERTEOF'
import os
from fpdf import FPDF
from datetime import datetime

# Variables injected by the agent
PARTICIPANT_NAME = "PLACEHOLDER_NAME"
TOTAL_SCORE = 0
TIER = "MCP Curious"
MASTERY = 0
BUILD = 0
QUALITY = 0
FLUENCY = 0
EXPLORATION = 0
ACHIEVEMENTS = []

class CertPDF(FPDF):
    pass

pdf = CertPDF(orientation='L', unit='in', format='letter')
pdf.set_auto_page_break(auto=False)
pdf.add_page()

# Red Hat Red header bar
pdf.set_fill_color(238, 0, 0)
pdf.rect(0, 0, 11, 0.6, 'F')

# White text in header
pdf.set_font('Helvetica', 'B', 14)
pdf.set_text_color(255, 255, 255)
pdf.set_xy(0.5, 0.15)
pdf.cell(0, 0.3, 'Red Hat', align='L')

# Title
pdf.set_text_color(21, 21, 21)
pdf.set_font('Helvetica', 'B', 28)
pdf.set_xy(0, 1.2)
pdf.cell(11, 0.5, 'CERTIFICATE OF COMPLETION', align='C')

# Subtitle
pdf.set_font('Helvetica', '', 16)
pdf.set_xy(0, 1.8)
pdf.cell(11, 0.4, 'MCP Developer Workshop', align='C')

pdf.set_font('Helvetica', '', 11)
pdf.set_text_color(100, 100, 100)
pdf.set_xy(0, 2.2)
pdf.cell(11, 0.3, 'Model Context Protocol on OpenShift AI', align='C')

# Red divider
pdf.set_draw_color(238, 0, 0)
pdf.set_line_width(0.02)
pdf.line(2, 2.7, 9, 2.7)

# Awarded to
pdf.set_text_color(100, 100, 100)
pdf.set_font('Helvetica', '', 12)
pdf.set_xy(0, 2.9)
pdf.cell(11, 0.3, 'Awarded to', align='C')

# Participant name
pdf.set_text_color(21, 21, 21)
pdf.set_font('Helvetica', 'B', 24)
pdf.set_xy(0, 3.3)
pdf.cell(11, 0.5, PARTICIPANT_NAME, align='C')

# Red divider under name
pdf.line(3, 3.9, 8, 3.9)

# Score section
pdf.set_font('Helvetica', 'B', 14)
pdf.set_text_color(21, 21, 21)
pdf.set_xy(1, 4.3)
pdf.cell(4, 0.3, f'Score: {TOTAL_SCORE}/100', align='L')
pdf.set_xy(6, 4.3)
pdf.cell(4, 0.3, TIER, align='R')

# Score bars
bar_y = 4.8
bar_data = [
    ("MCP Mastery", MASTERY, 20),
    ("Build Completeness", BUILD, 25),
    ("Code Quality", QUALITY, 20),
    ("Agentic Fluency", FLUENCY, 20),
    ("Exploration Bonus", EXPLORATION, 15),
]
pdf.set_font('Helvetica', '', 9)
for label, score, max_score in bar_data:
    pdf.set_xy(1.5, bar_y)
    pdf.set_text_color(21, 21, 21)
    pdf.cell(2, 0.2, label, align='L')
    # Background bar
    pdf.set_fill_color(224, 224, 224)
    pdf.rect(3.8, bar_y, 4, 0.18, 'F')
    # Filled bar
    if max_score > 0 and score > 0:
        fill_width = (score / max_score) * 4
        pdf.set_fill_color(62, 134, 53)
        pdf.rect(3.8, bar_y, fill_width, 0.18, 'F')
    # Score text
    pdf.set_xy(8, bar_y)
    pdf.cell(1.5, 0.2, f'{score}/{max_score}', align='L')
    bar_y += 0.3

# Skills demonstrated
pdf.set_font('Helvetica', 'B', 10)
pdf.set_xy(1.5, 6.4)
pdf.cell(4, 0.25, 'Skills Demonstrated:', align='L')
pdf.set_font('Helvetica', '', 9)
skills = [
    "MCP Protocol & Architecture", "Python MCP SDK",
    "OpenShift Container Builds", "AI Agent Tool Design",
    "MCP Server Deployment", "Agentic Development"
]
sx, sy = 1.5, 6.7
for i, skill in enumerate(skills):
    col = i % 2
    row = i // 2
    pdf.set_xy(sx + col * 4.5, sy + row * 0.25)
    pdf.cell(4, 0.2, f"  {skill}", align='L')

# Date and footer
pdf.set_font('Helvetica', '', 10)
pdf.set_text_color(100, 100, 100)
pdf.set_xy(1.5, 7.6)
pdf.cell(4, 0.25, datetime.now().strftime('%B %d, %Y'), align='L')
pdf.set_xy(5.5, 7.6)
pdf.cell(4, 0.25, 'Red Hat AI', align='R')

# Bottom red bar
pdf.set_fill_color(238, 0, 0)
pdf.rect(0, 7.9, 11, 0.6, 'F')
pdf.set_font('Helvetica', '', 9)
pdf.set_text_color(255, 255, 255)
pdf.set_xy(0.5, 8.05)
pdf.cell(5, 0.3, 'redhat.com/ai', align='L')
pdf.set_xy(5.5, 8.05)
pdf.cell(5, 0.3, 'MCP Developer Workshop', align='R')

pdf.output('certificate.pdf')
print("Certificate generated: /projects/mcp-dev-workshop/certificate.pdf")
CERTEOF
```

**IMPORTANT:** Before running this script, the agent MUST replace:
- `PARTICIPANT_NAME` with the actual name from Step 1 (properly escaped)
- All score variables with actual values from Step 2
- `TIER` with the actual tier from the scoring system
- `ACHIEVEMENTS` with the actual achievements earned

### Step 5: Also Generate HTML Version

Write an HTML version to `/projects/mcp-dev-workshop/certificate.html` with:
- Full Red Hat branding (Google Fonts, color palette)
- Interactive score bars (CSS only, no JS)
- Print-optimized CSS for browser Print → Save as PDF
- Responsive for screen viewing too

### Step 6: Present to Participant

```
╔══════════════════════════════════════════════════════╗
║  🎓 Your Certificate is Ready!                       ║
╚══════════════════════════════════════════════════════╝

  📄 PDF:  /projects/mcp-dev-workshop/certificate.pdf
  📄 HTML: /projects/mcp-dev-workshop/certificate.html

  To download your certificate:
  1. Open the DevSpaces file explorer (left sidebar)
  2. Navigate to mcp-dev-workshop/
  3. Right-click certificate.pdf → Download

  Or open certificate.html in your browser and
  use Cmd+P / Ctrl+P → Save as PDF
```

## CERTIFICATE DATA REQUIREMENTS

The certificate MUST include:
- Participant's name (from question tool — NEVER assumed)
- Date of completion (generated dynamically)
- Total score and tier
- Score breakdown for all 5 dimensions with visual bars
- Skills demonstrated checklist
- Achievements unlocked (if achievement-system skill was used)
- Red Hat branding (logo, fonts, colors)
- Unique certificate ID (generate: first 8 chars of hash of name + date + score)
