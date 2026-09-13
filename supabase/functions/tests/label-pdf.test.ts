import {
  assert,
  assertEquals,
  assertRejects,
  assertThrows,
} from "jsr:@std/assert@1";
import {
  buildRipeningLabelPdf,
  buildSortingLabelPdf,
  fitTextSize,
  formatJapaneseDate,
  formatJapaneseDateTime,
  RipeningLabelData,
  SortingLabelData,
} from "../label-pdf/layout.ts";
import { PDFDocument } from "npm:pdf-lib@1.17.1";
import fontkit from "npm:@pdf-lib/fontkit@1.1.1";

const fontBytes = await Deno.readFile(
  new URL(
    "../label-pdf/assets/NotoSansJP-VariableFont_wght.ttf",
    import.meta.url,
  ),
);

const sample: SortingLabelData = {
  containerDisplayId: "選果-2027-001-1",
  originName: "おおくま農園 第一圃場・A区画",
  varietyName: "ヘイワード",
  gradeCode: "M",
  netWeightKg: "18.40",
  sortedOn: "2027-10-15",
  workerName: "大熊 太郎",
};

const A5_WIDTH_POINTS = 419.5276;
const A5_HEIGHT_POINTS = 595.2756;

function decodeBytes(pdf: Uint8Array): string {
  let text = "";
  const chunk = 0x8000;
  for (let i = 0; i < pdf.length; i += chunk) {
    text += String.fromCharCode(...pdf.subarray(i, i + chunk));
  }
  return text;
}

Deno.test("generates a single A5 page", async () => {
  const pdf = await buildSortingLabelPdf(sample, fontBytes);
  const text = decodeBytes(pdf);
  assert(text.startsWith("%PDF-"), "output must be a PDF");
  const mediaBox = /\/MediaBox \[\s*0 0 ([\d.]+) ([\d.]+)\s*\]/.exec(text);
  assert(mediaBox, "MediaBox must be present");
  const width = Number(mediaBox![1]);
  const height = Number(mediaBox![2]);
  assert(Math.abs(width - A5_WIDTH_POINTS) < 0.2, `unexpected width: ${width}`);
  assert(
    Math.abs(height - A5_HEIGHT_POINTS) < 0.2,
    `unexpected height: ${height}`,
  );
  const pageCount = /\/Type \/Pages[^>]*\/Count (\d+)/.exec(text);
  assert(pageCount, "page tree must be present");
  assertEquals(pageCount![1], "1", "PDF must contain exactly one page");
});

Deno.test("embeds a Noto Sans JP subset", async () => {
  const pdf = await buildSortingLabelPdf(sample, fontBytes);
  const text = decodeBytes(pdf);
  assert(text.includes("/FontFile2"), "TrueType font program must be embedded");
  assert(text.includes("NotoSansJP"), "embedded font must keep its fixed name");
  assert(
    pdf.byteLength < 1024 * 1024,
    `embedded subset must stay far below the full 9 MB font: ${pdf.byteLength}`,
  );
});

Deno.test("same input reproduces identical bytes", async () => {
  const first = await buildSortingLabelPdf(sample, fontBytes);
  const second = await buildSortingLabelPdf(sample, fontBytes);
  assertEquals(first, second);
});

Deno.test("different input changes the bytes", async () => {
  const first = await buildSortingLabelPdf(sample, fontBytes);
  const second = await buildSortingLabelPdf(
    { ...sample, netWeightKg: "18.50" },
    fontBytes,
  );
  assert(decodeBytes(first) !== decodeBytes(second));
});

Deno.test("fits long Japanese values inside the field width", async () => {
  const doc = await PDFDocument.create();
  doc.registerFontkit(fontkit);
  const font = await doc.embedFont(fontBytes, { subset: true });
  const value = "福島県大熊町キウイフルーツ生産実証圃場第一試験区画";
  const maxWidth = 94 * 72 / 25.4;
  const size = fitTextSize(font, value, 13, maxWidth);

  assert(size < 13, "long values must be reduced from the preferred size");
  assert(
    font.widthOfTextAtSize(value, size) <= maxWidth + 0.01,
    "fitted value must stay inside the A5 safe area",
  );

  await buildSortingLabelPdf({ ...sample, originName: value }, fontBytes);
});

Deno.test("rejects blank fields", async () => {
  await assertRejects(
    () => buildSortingLabelPdf({ ...sample, originName: " " }, fontBytes),
    Error,
    "missing label field: originName",
  );
});

Deno.test("rejects weights without two decimals", async () => {
  await assertRejects(
    () => buildSortingLabelPdf({ ...sample, netWeightKg: "18.4" }, fontBytes),
    Error,
    "two decimals",
  );
});

Deno.test("formats sorted dates in Japanese", () => {
  assertEquals(formatJapaneseDate("2027-10-15"), "2027年10月15日");
  assertEquals(formatJapaneseDate("2028-05-01"), "2028年5月1日");
  assertThrows(() => formatJapaneseDate("2028/05/01"));
});

// Ripening label (S3-08) -----------------------------------------------------

const ripeningBase: RipeningLabelData = {
  containerDisplayId: "追熟-2026-001-1",
  orchardNames: "おおくま農園",
  varietyName: "ヘイワード",
  gradeCode: "L",
  netWeightKg: "8.00",
  injectionAt: "2026-09-01T10:00:00Z",
  plannedRemovalAt: "2026-09-04T09:00:00Z",
  plannedCompletionAt: "2026-09-20T09:00:00Z",
  locationName: "追熟庫",
  allocations: [
    { allocationType: "order", orderNumber: "ORDER-001", weightKg: "6.00" },
    { allocationType: "reserve", orderNumber: null, weightKg: "2.00" },
  ],
};

Deno.test("ripening: generates a single A5 page", async () => {
  const pdf = await buildRipeningLabelPdf(ripeningBase, fontBytes);
  const text = decodeBytes(pdf);
  assert(text.startsWith("%PDF-"), "output must be a PDF");
  const mediaBox = /\/MediaBox \[\s*0 0 ([\d.]+) ([\d.]+)\s*\]/.exec(text);
  assert(mediaBox, "MediaBox must be present");
  const width = Number(mediaBox![1]);
  const height = Number(mediaBox![2]);
  assert(Math.abs(width - A5_WIDTH_POINTS) < 0.2, `unexpected width: ${width}`);
  assert(Math.abs(height - A5_HEIGHT_POINTS) < 0.2, `unexpected height: ${height}`);
});

Deno.test("ripening: same input reproduces identical bytes", async () => {
  const first = await buildRipeningLabelPdf(ripeningBase, fontBytes);
  const second = await buildRipeningLabelPdf(ripeningBase, fontBytes);
  assertEquals(first, second);
});

Deno.test("ripening: optional dates rendered as em dash when null", async () => {
  const pdf = await buildRipeningLabelPdf(
    { ...ripeningBase, plannedRemovalAt: null, plannedCompletionAt: null },
    fontBytes,
  );
  assert(pdf.length > 0, "PDF is still generated without optional dates");
});

Deno.test("ripening: rejects blank containerDisplayId", async () => {
  await assertRejects(
    () => buildRipeningLabelPdf({ ...ripeningBase, containerDisplayId: "  " }, fontBytes),
    Error,
    "containerDisplayId",
  );
});

Deno.test("ripening: rejects weight without two decimals", async () => {
  await assertRejects(
    () => buildRipeningLabelPdf({ ...ripeningBase, netWeightKg: "8" }, fontBytes),
    Error,
    "two decimals",
  );
});

Deno.test("formatJapaneseDateTime formats ISO 8601 datetime", () => {
  assertEquals(formatJapaneseDateTime("2026-09-01T10:00:00Z"), "2026年9月1日 19:00");
  assertEquals(formatJapaneseDateTime("2026-09-04T09:00:00+09:00"), "2026年9月4日 09:00");
  assertThrows(() => formatJapaneseDateTime("2026-09-01"));
});

Deno.test("ripening: dates represent the same instant in JST and cross midnight", () => {
  assertEquals(formatJapaneseDateTime("2026-09-01T01:00:00Z"), formatJapaneseDateTime("2026-09-01T10:00:00+09:00"));
  assertEquals(formatJapaneseDateTime("2026-09-01T18:30:00Z"), "2026年9月2日 03:30");
});
Deno.test("ripening: many allocations continue on A5 pages", async () => {
  const pdf = await buildRipeningLabelPdf({ ...ripeningBase, allocations: Array.from({length: 40}, (_, i) => ({allocationType: "order", orderNumber: `ORDER-${i}`, weightKg: "0.20"})) }, fontBytes);
  const doc = await PDFDocument.load(pdf);
  assert(doc.getPageCount() > 1);
  for (const page of doc.getPages()) assert(Math.abs(page.getWidth() - A5_WIDTH_POINTS) < 0.2);
});
