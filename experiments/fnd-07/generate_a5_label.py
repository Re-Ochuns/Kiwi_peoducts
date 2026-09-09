#!/usr/bin/env python3
"""Generate the reproducible FND-07 Japanese A5 label prototype."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from reportlab.lib.colors import HexColor
from reportlab.lib.pagesizes import A5
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen.canvas import Canvas


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DATA = ROOT / "experiments/fnd-07/label-sample.json"
DEFAULT_FONT = (
    ROOT / "experiments/fnd-07/assets/NotoSansJP-VariableFont_wght.ttf"
)
DEFAULT_OUTPUT = ROOT / "output/pdf/fnd-07-a5-label-prototype.pdf"

PAGE_WIDTH, PAGE_HEIGHT = A5
MARGIN = 10 * mm
INK = HexColor("#111513")
MUTED = HexColor("#4F5953")
LINE = HexColor("#8D9690")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", type=Path, default=DEFAULT_DATA)
    parser.add_argument("--font", type=Path, default=DEFAULT_FONT)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    return parser.parse_args()


def draw_text(
    canvas: Canvas,
    text: str,
    x: float,
    y: float,
    size: float,
    *,
    color=INK,
) -> None:
    canvas.setFillColor(color)
    canvas.setFont("NotoSansJP", size)
    canvas.drawString(x, y, text)


def draw_field(canvas: Canvas, label: str, value: str, y: float) -> float:
    draw_text(canvas, label, MARGIN, y, 9, color=MUTED)
    draw_text(canvas, value, MARGIN + 34 * mm, y - 1, 13)
    line_y = y - 5 * mm
    canvas.setStrokeColor(LINE)
    canvas.setLineWidth(0.6)
    canvas.line(MARGIN, line_y, PAGE_WIDTH - MARGIN, line_y)
    return y - 13 * mm


def generate(data_path: Path, font_path: Path, output_path: Path) -> None:
    data = json.loads(data_path.read_text(encoding="utf-8"))
    output_path.parent.mkdir(parents=True, exist_ok=True)

    pdfmetrics.registerFont(TTFont("NotoSansJP", str(font_path)))
    canvas = Canvas(str(output_path), pagesize=A5, pageCompression=1)
    canvas.setTitle("FND-07 A5ラベル試作")
    canvas.setAuthor("おおくま農園 在庫管理システム")

    top = PAGE_HEIGHT - MARGIN
    draw_text(canvas, "選果後コンテナラベル", MARGIN, top - 7 * mm, 12)

    id_y = top - 24 * mm
    draw_text(canvas, "コンテナID", MARGIN, id_y, 9, color=MUTED)
    draw_text(canvas, data["container_id"], MARGIN, id_y - 10 * mm, 25)

    weight_y = id_y - 34 * mm
    draw_text(canvas, "正味重量", MARGIN, weight_y, 9, color=MUTED)
    draw_text(
        canvas,
        f'{data["net_weight_kg"]} kg',
        MARGIN,
        weight_y - 17 * mm,
        40,
    )

    canvas.setStrokeColor(INK)
    canvas.setLineWidth(1.2)
    divider_y = weight_y - 25 * mm
    canvas.line(MARGIN, divider_y, PAGE_WIDTH - MARGIN, divider_y)

    y = divider_y - 11 * mm
    y = draw_field(canvas, "産地・区画", data["origin"], y)
    y = draw_field(canvas, "品種", data["variety"], y)
    y = draw_field(canvas, "等級", data["grade"], y)
    y = draw_field(canvas, "選果日", data["sorted_on"], y)
    draw_field(canvas, "担当者", data["worker"], y)

    calibration_y = MARGIN + 8 * mm
    draw_text(canvas, "印刷確認線 100 mm", MARGIN, calibration_y + 4 * mm, 8, color=MUTED)
    canvas.setStrokeColor(INK)
    canvas.setLineWidth(0.8)
    canvas.line(MARGIN, calibration_y, MARGIN + 100 * mm, calibration_y)
    canvas.line(MARGIN, calibration_y - 2 * mm, MARGIN, calibration_y + 2 * mm)
    canvas.line(
        MARGIN + 100 * mm,
        calibration_y - 2 * mm,
        MARGIN + 100 * mm,
        calibration_y + 2 * mm,
    )

    draw_text(canvas, "おおくま農園", MARGIN, MARGIN, 8, color=MUTED)
    canvas.showPage()
    canvas.save()


if __name__ == "__main__":
    args = parse_args()
    generate(args.data, args.font, args.output)
