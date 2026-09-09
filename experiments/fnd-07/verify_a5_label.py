#!/usr/bin/env python3
"""Verify page size, text, margins, and embedded fonts in the prototype."""

from __future__ import annotations

import argparse
from pathlib import Path

import pdfplumber
from pypdf import PdfReader


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_INPUT = ROOT / "output/pdf/fnd-07-a5-label-prototype.pdf"
A5_WIDTH_POINTS = 419.5276
A5_HEIGHT_POINTS = 595.2756
EXPECTED_TEXT = (
    "選果後コンテナラベル",
    "選果-2027-001-1",
    "18.40 kg",
    "おおくま農園 第一圃場・A区画",
    "ヘイワード",
    "2027年10月15日",
    "大熊 太郎",
    "印刷確認線 100 mm",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("pdf", type=Path, nargs="?", default=DEFAULT_INPUT)
    return parser.parse_args()


def embedded_font_count(reader: PdfReader) -> int:
    fonts = reader.pages[0]["/Resources"].get("/Font", {})
    count = 0
    for font_reference in fonts.values():
        font = font_reference.get_object()
        descriptor_reference = font.get("/FontDescriptor")
        if descriptor_reference is None:
            descendants = font.get("/DescendantFonts", [])
            if descendants:
                descriptor_reference = descendants[0].get_object().get(
                    "/FontDescriptor"
                )
        if descriptor_reference is None:
            continue
        descriptor = descriptor_reference.get_object()
        if any(key in descriptor for key in ("/FontFile", "/FontFile2", "/FontFile3")):
            count += 1
    return count


def verify(pdf_path: Path) -> None:
    reader = PdfReader(pdf_path)
    assert len(reader.pages) == 1, "PDF must contain exactly one page"

    page = reader.pages[0]
    width = float(page.mediabox.width)
    height = float(page.mediabox.height)
    assert abs(width - A5_WIDTH_POINTS) < 0.2, f"unexpected width: {width}"
    assert abs(height - A5_HEIGHT_POINTS) < 0.2, f"unexpected height: {height}"
    assert embedded_font_count(reader) >= 1, "no embedded font was found"

    with pdfplumber.open(pdf_path) as document:
        rendered_page = document.pages[0]
        text = rendered_page.extract_text() or ""
        for expected in EXPECTED_TEXT:
            assert expected in text, f"missing text: {expected}"

        assert rendered_page.chars, "no visible text characters were found"
        min_x = min(float(char["x0"]) for char in rendered_page.chars)
        max_x = max(float(char["x1"]) for char in rendered_page.chars)
        assert min_x >= 27, f"text exceeds the left safe margin: {min_x}"
        assert max_x <= width - 27, f"text exceeds the right safe margin: {max_x}"

    print(
        f"verified: pages=1 size={width:.2f}x{height:.2f}pt "
        f"embedded_fonts={embedded_font_count(reader)}"
    )


if __name__ == "__main__":
    verify(parse_args().pdf)
