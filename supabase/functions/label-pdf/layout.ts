// A5 label layouts for sorted containers (S1-08) and ripening containers (S3-08).
// The same input and layout version must reproduce the same PDF bytes, so all
// metadata dates are fixed and the embedded font subset uses a fixed name.
import { PDFDocument, type PDFFont, rgb } from "npm:pdf-lib@1.17.1";
import fontkit from "npm:@pdf-lib/fontkit@1.1.1";

export const LABEL_LAYOUT_VERSION = 1;

export interface SortingLabelData {
  containerDisplayId: string;
  originName: string;
  varietyName: string;
  gradeCode: string;
  netWeightKg: string;
  sortedOn: string;
  workerName: string;
}

const MM = 72 / 25.4;
const PAGE_WIDTH = 148 * MM;
const PAGE_HEIGHT = 210 * MM;
const MARGIN = 10 * MM;
const INK = rgb(0x11 / 255, 0x15 / 255, 0x13 / 255);
const MUTED = rgb(0x4f / 255, 0x59 / 255, 0x53 / 255);
const LINE = rgb(0x8d / 255, 0x96 / 255, 0x90 / 255);
const FIXED_DATE = new Date("2026-01-01T00:00:00.000Z");

export function fitTextSize(
  font: Pick<PDFFont, "widthOfTextAtSize">,
  text: string,
  preferredSize: number,
  maxWidth: number,
): number {
  const preferredWidth = font.widthOfTextAtSize(text, preferredSize);
  if (preferredWidth <= maxWidth || preferredWidth === 0) {
    return preferredSize;
  }
  return preferredSize * maxWidth / preferredWidth;
}

export function formatJapaneseDate(isoDate: string): string {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(isoDate);
  if (!match) {
    throw new Error(`sortedOn must be YYYY-MM-DD: ${isoDate}`);
  }
  return `${Number(match[1])}年${Number(match[2])}月${Number(match[3])}日`;
}

function requireText(
  data: SortingLabelData,
  field: keyof SortingLabelData,
): string {
  const value = data[field];
  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(`missing label field: ${field}`);
  }
  return value;
}

export async function buildSortingLabelPdf(
  data: SortingLabelData,
  fontBytes: Uint8Array,
): Promise<Uint8Array> {
  const containerDisplayId = requireText(data, "containerDisplayId");
  const originName = requireText(data, "originName");
  const varietyName = requireText(data, "varietyName");
  const gradeCode = requireText(data, "gradeCode");
  const netWeightKg = requireText(data, "netWeightKg");
  if (!/^\d+\.\d{2}$/.test(netWeightKg)) {
    throw new Error(`netWeightKg must have two decimals: ${netWeightKg}`);
  }
  const sortedOnLabel = formatJapaneseDate(requireText(data, "sortedOn"));
  const workerName = requireText(data, "workerName");

  const doc = await PDFDocument.create();
  doc.registerFontkit(fontkit);
  const font = await doc.embedFont(fontBytes, {
    subset: true,
    customName: "NotoSansJP",
  });
  doc.setTitle("選果後コンテナラベル");
  doc.setAuthor("おおくま農園 在庫管理システム");
  doc.setCreator("kiwi-inventory label-pdf");
  doc.setProducer(`kiwi-inventory label-pdf layout-v${LABEL_LAYOUT_VERSION}`);
  doc.setCreationDate(FIXED_DATE);
  doc.setModificationDate(FIXED_DATE);

  const page = doc.addPage([PAGE_WIDTH, PAGE_HEIGHT]);
  const drawText = (
    text: string,
    x: number,
    y: number,
    size: number,
    color = INK,
  ) => page.drawText(text, { x, y, size, font, color });
  const drawFittedText = (
    text: string,
    x: number,
    y: number,
    preferredSize: number,
    maxWidth: number,
  ) => drawText(text, x, y, fitTextSize(font, text, preferredSize, maxWidth));

  const top = PAGE_HEIGHT - MARGIN;
  drawText("選果後コンテナラベル", MARGIN, top - 7 * MM, 12);

  const idY = top - 24 * MM;
  drawText("コンテナID", MARGIN, idY, 9, MUTED);
  drawFittedText(
    containerDisplayId,
    MARGIN,
    idY - 10 * MM,
    25,
    PAGE_WIDTH - 2 * MARGIN,
  );

  const weightY = idY - 34 * MM;
  drawText("正味重量", MARGIN, weightY, 9, MUTED);
  drawFittedText(
    `${netWeightKg} kg`,
    MARGIN,
    weightY - 17 * MM,
    40,
    PAGE_WIDTH - 2 * MARGIN,
  );

  const dividerY = weightY - 25 * MM;
  page.drawLine({
    start: { x: MARGIN, y: dividerY },
    end: { x: PAGE_WIDTH - MARGIN, y: dividerY },
    thickness: 1.2,
    color: INK,
  });

  let y = dividerY - 11 * MM;
  const drawField = (label: string, value: string) => {
    drawText(label, MARGIN, y, 9, MUTED);
    const valueX = MARGIN + 34 * MM;
    drawFittedText(value, valueX, y - 1, 13, PAGE_WIDTH - MARGIN - valueX);
    page.drawLine({
      start: { x: MARGIN, y: y - 5 * MM },
      end: { x: PAGE_WIDTH - MARGIN, y: y - 5 * MM },
      thickness: 0.6,
      color: LINE,
    });
    y -= 13 * MM;
  };
  drawField("産地・区画", originName);
  drawField("品種", varietyName);
  drawField("等級", gradeCode);
  drawField("選果日", sortedOnLabel);
  drawField("担当者", workerName);

  drawText("おおくま農園", MARGIN, MARGIN, 8, MUTED);

  return await doc.save({ useObjectStreams: false });
}

// ── Ripening label (S3-08) ────────────────────────────────────────────────────

export interface RipeningLabelData {
  containerDisplayId: string;
  orchardNames: string;
  varietyName: string;
  gradeCode: string;
  netWeightKg: string;
  injectionAt: string;    // ISO 8601 datetime
  plannedRemovalAt: string | null;
  plannedCompletionAt: string | null;
  locationName: string;
  allocations: Array<{ allocationType: string; orderNumber: string | null; weightKg: string }>;
}

export function formatJapaneseDateTime(iso: string): string {
  const date = new Date(iso);
  if (!/(Z|[+-]\d{2}:\d{2})$/.test(iso) || !Number.isFinite(date.getTime())) {
    throw new Error(`invalid datetime: ${iso}`);
  }
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: "Asia/Tokyo", year: "numeric", month: "numeric", day: "numeric",
    hour: "2-digit", minute: "2-digit", hourCycle: "h23",
  }).formatToParts(date);
  const value = (type: string) => parts.find((part) => part.type === type)!.value;
  return `${value("year")}年${Number(value("month"))}月${Number(value("day"))}日 ${value("hour")}:${value("minute")}`;
}

export async function buildRipeningLabelPdf(
  data: RipeningLabelData,
  fontBytes: Uint8Array,
): Promise<Uint8Array> {
  const containerDisplayId = data.containerDisplayId?.trim();
  if (!containerDisplayId) throw new Error("missing label field: containerDisplayId");
  const netWeightKg = data.netWeightKg?.trim();
  if (!netWeightKg || !/^\d+\.\d{2}$/.test(netWeightKg)) {
    throw new Error(`netWeightKg must have two decimals: ${netWeightKg}`);
  }

  const doc = await PDFDocument.create();
  doc.registerFontkit(fontkit);
  const font = await doc.embedFont(fontBytes, {
    subset: false,
    customName: "NotoSansJP",
  });
  doc.setTitle("追熟コンテナラベル");
  doc.setAuthor("おおくま農園 在庫管理システム");
  doc.setCreator("kiwi-inventory label-pdf");
  doc.setProducer(`kiwi-inventory label-pdf layout-v${LABEL_LAYOUT_VERSION}`);
  doc.setCreationDate(FIXED_DATE);
  doc.setModificationDate(FIXED_DATE);

  let page = doc.addPage([PAGE_WIDTH, PAGE_HEIGHT]);
  const drawText = (text: string, x: number, y: number, size: number, color = INK) =>
    page.drawText(text, { x, y, size, font, color });
  const drawFittedText = (
    text: string,
    x: number,
    y: number,
    preferredSize: number,
    maxWidth: number,
  ) => drawText(text, x, y, fitTextSize(font, text, preferredSize, maxWidth));

  const top = PAGE_HEIGHT - MARGIN;
  drawText("追熟コンテナラベル", MARGIN, top - 7 * MM, 12);

  const idY = top - 24 * MM;
  drawText("コンテナID", MARGIN, idY, 9, MUTED);
  drawFittedText(containerDisplayId, MARGIN, idY - 10 * MM, 25, PAGE_WIDTH - 2 * MARGIN);

  const weightY = idY - 34 * MM;
  drawText("正味重量", MARGIN, weightY, 9, MUTED);
  drawFittedText(`${netWeightKg} kg`, MARGIN, weightY - 17 * MM, 40, PAGE_WIDTH - 2 * MARGIN);

  const dividerY = weightY - 25 * MM;
  page.drawLine({
    start: { x: MARGIN, y: dividerY },
    end: { x: PAGE_WIDTH - MARGIN, y: dividerY },
    thickness: 1.2,
    color: INK,
  });

  let y = dividerY - 11 * MM;
  const drawField = (label: string, value: string) => {
    drawText(label, MARGIN, y, 9, MUTED);
    const valueX = MARGIN + 34 * MM;
    drawFittedText(value, valueX, y - 1, 13, PAGE_WIDTH - MARGIN - valueX);
    page.drawLine({
      start: { x: MARGIN, y: y - 5 * MM },
      end: { x: PAGE_WIDTH - MARGIN, y: y - 5 * MM },
      thickness: 0.6,
      color: LINE,
    });
    y -= 10 * MM;
  };

  drawField("産地", data.orchardNames || "—");
  drawField("品種", data.varietyName || "—");
  drawField("等級", data.gradeCode || "—");
  drawField("注入日時", data.injectionAt ? formatJapaneseDateTime(data.injectionAt) : "—");
  drawField("抜き予定", data.plannedRemovalAt ? formatJapaneseDateTime(data.plannedRemovalAt) : "—");
  drawField("出荷可能予定", data.plannedCompletionAt ? formatJapaneseDateTime(data.plannedCompletionAt) : "—");
  drawField("場所", data.locationName || "—");

  drawText("内訳（ロット全体）", MARGIN, y, 10, MUTED);
  y -= 7 * MM;
  if (data.allocations.length === 0) {
    drawText("内訳未設定", MARGIN, y, 11);
  }
  for (const allocation of data.allocations) {
    const label = allocation.allocationType === "reserve" ? "予備" : `受注 ${allocation.orderNumber ?? "番号未設定"}`;
    // Wrap long order numbers at a readable size; never silently omit rows.
    const lines: string[] = [];
    let current = "";
    for (const char of `${label}  ${allocation.weightKg} kg`) {
      if (font.widthOfTextAtSize(current + char, 11) > PAGE_WIDTH - 2 * MARGIN) {
        lines.push(current); current = char;
      } else current += char;
    }
    if (current) lines.push(current);
    for (const line of lines) {
      if (y < 22 * MM) {
        drawText("おおくま農園", MARGIN, MARGIN, 8, MUTED);
        page = doc.addPage([PAGE_WIDTH, PAGE_HEIGHT]);
        drawFittedText(`${containerDisplayId} 内訳（続き）`, MARGIN, PAGE_HEIGHT - 17 * MM, 14, PAGE_WIDTH - 2 * MARGIN);
        y = PAGE_HEIGHT - 29 * MM;
      }
      drawText(line, MARGIN, y, 11);
      y -= 6 * MM;
    }
  }
  drawText("おおくま農園", MARGIN, MARGIN, 8, MUTED);

  return await doc.save({ useObjectStreams: false });
}
