#!/usr/bin/env python3
"""Pré-vérification d'un fichier markdown pour conversion PDF.
Usage: pdf-check.py <fichier.md> <memory_dir> <repo_root>
Sortie: format structuré pour consommation par Claude."""

import re
import shutil
import sys
import os

def main():
    md_file = sys.argv[1]
    memory_dir = sys.argv[2] if len(sys.argv) > 2 else ""
    repo_root = sys.argv[3] if len(sys.argv) > 3 else os.path.dirname(md_file)

    md_dir = os.path.dirname(md_file)
    md_base = os.path.splitext(os.path.basename(md_file))[0]
    pdf_file = os.path.join(md_dir, md_base + ".pdf")

    # --- Prérequis ---
    errors = []

    # pandoc dans le PATH
    pandoc_path = shutil.which("pandoc")
    if not pandoc_path:
        errors.append("ERREUR: pandoc introuvable dans le PATH")

    # xelatex dans le PATH
    xelatex_path = shutil.which("xelatex")
    if not xelatex_path:
        errors.append("ERREUR: xelatex introuvable dans le PATH")

    # fichier markdown existe
    if not os.path.isfile(md_file):
        errors.append(f"ERREUR: fichier markdown introuvable: {md_file}")

    # PDF existant : vérifier qu'il est modifiable
    if os.path.isfile(pdf_file):
        try:
            with open(pdf_file, "a"):
                pass
        except (PermissionError, OSError):
            errors.append(f"ERREUR: le fichier PDF existe et n'est pas modifiable (ouvert ?): {pdf_file}")

    if errors:
        for e in errors:
            print(e)
        sys.exit(1)

    # --- Résolution .tex ---
    tex_file = ""
    tex_source = ""
    doc_tex = os.path.join(md_dir, md_base + ".tex")
    proj_tex = os.path.join(repo_root, "overrides.tex")
    global_tex = os.path.expanduser("~/.claude/skills/pdf/overrides.tex")

    if os.path.isfile(doc_tex):
        tex_file, tex_source = doc_tex, "document"
    elif os.path.isfile(proj_tex):
        tex_file, tex_source = proj_tex, "project"
    elif os.path.isfile(global_tex):
        tex_file, tex_source = global_tex, "global"

    # --- First-run flag ---
    first_run = True
    flag = f"pdf_first_run_done:{os.path.basename(md_file)}"
    if memory_dir and os.path.isdir(memory_dir):
        for fname in os.listdir(memory_dir):
            if not fname.endswith(".md"):
                continue
            fpath = os.path.join(memory_dir, fname)
            with open(fpath, "r", encoding="utf-8") as f:
                if flag in f.read():
                    first_run = False
                    break

    # --- Lecture markdown ---
    with open(md_file, "r", encoding="utf-8") as f:
        lines = f.readlines()

    # Identifier les blocs de code
    in_code = False
    code_ranges = []
    code_start = 0
    for i, line in enumerate(lines):
        if line.strip().startswith("```"):
            if not in_code:
                in_code = True
                code_start = i + 1
            else:
                in_code = False
                code_ranges.append((code_start, i))

    def in_code_block(line_idx):
        return any(s <= line_idx < e for s, e in code_ranges)

    violations = []

    # 1. Box-drawing Unicode dans les blocs de code
    for s, e in code_ranges:
        for i in range(s, e):
            for ch in lines[i]:
                if 0x2500 <= ord(ch) <= 0x257F:
                    violations.append(f"L{i+1}: caractère box-drawing Unicode dans bloc de code")
                    break

    # 2. Ligne vide manquante entre paragraphe et liste
    for i in range(1, len(lines)):
        if in_code_block(i):
            continue
        line = lines[i]
        if not re.match(r"^(\s*[-*+]|\s*\d+\.)\s", line):
            continue
        prev = lines[i - 1].strip()
        if prev == "":
            continue
        if re.match(r"^(\s*[-*+]|\s*\d+\.)\s", lines[i - 1]):
            continue
        if prev.startswith("#") or prev.startswith("|") or prev.startswith(">"):
            continue
        violations.append(f"L{i+1}: ligne vide manquante entre paragraphe et liste")

    # 3. Lignes longues dans les blocs de code
    for s, e in code_ranges:
        for i in range(s, e):
            length = len(lines[i].rstrip())
            if length > 80:
                violations.append(f"L{i+1}: ligne de {length} car dans bloc de code (max 80)")

    # 4. Accents dans les blocs de code
    for s, e in code_ranges:
        for i in range(s, e):
            if re.search(r"[àâäéèêëïîôùûüçÀÂÄÉÈÊËÏÎÔÙÛÜÇ]", lines[i]):
                violations.append(f"L{i+1}: accents dans bloc de code")

    # --- Sortie ---
    print(f"TEX_FILE={tex_file}")
    print(f"TEX_SOURCE={tex_source}")
    print(f"FIRST_RUN={str(first_run).lower()}")

    if violations:
        print("VIOLATIONS:")
        for v in violations:
            print(f"  {v}")
    else:
        print("VIOLATIONS=none")

    # Contenu du .tex si first-run + global
    if first_run and tex_source == "global" and tex_file:
        with open(tex_file, "r", encoding="utf-8") as f:
            print(f"TEX_CONTENT:")
            print(f"  {f.read().strip()}")


if __name__ == "__main__":
    main()
