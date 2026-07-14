<!--
  Mirrored into this repo so Grok Build auto-loads path-scoped rules.
  Grok scans <repo>/.claude/rules/ but not ~/.claude/rules/.
  Source of truth for Claude Code multi-machine sync: ~/.claude/rules/ (claude-config).
  When you change a rule, update both locations (or re-copy from global).
-->
---
---

# CLI Tools

- **markitdown** (pip, installed) — converts documents to Markdown for AI sessions: `python -m markitdown <file>`. Supports PDF, DOCX, PPTX, XLSX, HTML, CSV, JSON, images, ZIP. Use this when reading any document during a session rather than ad-hoc Python scripts.
  - **Windows only: prefix with `PYTHONIOENCODING=utf-8`** — without it, special characters (ligatures like `fi`, em dashes, etc.) cause `UnicodeEncodeError` due to cp1252 console encoding. Linux defaults to UTF-8 and doesn't need this.
  - **Does not extract embedded images from PDFs** — only extracts text. If a PDF contains important images (screenshots, email snippets), use PyMuPDF to extract them: `python -c "import fitz; doc=fitz.open('file.pdf'); [fitz.Pixmap(doc, img[0]).save(f'img_{i}.png') for page in doc for i,img in enumerate(page.get_images())]"` then use the Read tool to OCR the extracted PNGs
- **yt-dlp** (winget/pacman, install on demand) — extract YouTube transcripts and audio: `yt-dlp --write-auto-subs --sub-lang en --skip-download "URL"`. VTT output includes timestamps — strip with sed for clean text. Use `--extract-audio --audio-format wav` for audio-only download.
- **CLI tools** — see `~/.claude/CLI_TOOLS.md` for the full reference (jq, fzf, qsv, xh, zoxide, bat, rg, fd, delta, pandoc, gron, fx, yt-dlp) and tool discovery workflow

