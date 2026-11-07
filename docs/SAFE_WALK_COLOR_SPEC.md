# 臺北安心行顏色規範

2026-11-07。只規範新增功能的色彩語意及可讀配對；不包含版面、Widget 架構、尺寸、形狀或操作流程。正式新增 UI/UX 由 M3 莅紋設計。

唯一現有色值來源為官方 `lib/util/tp_colors.dart`（Base `c8e5d4d3f8f699f3d9d6cd68e129ed4da12037b3`）。新增功能優先直接引用 TPColors，不修改官方全域 Theme，也不另外建立 CSS Design System。

| 官方名稱 | 色碼 | 使用語意 |
|---|---|---|
| TPColors.primary500 | #5AB4C5 | 原生品牌色、一般非緊急重點；搭深色文字 |
| TPColors.primary700 | #356C77 | 深主色、高對比用途；可搭白字 |
| TPColors.primary800 | #22474E | 深色強調文字 |
| TPColors.secondary500 | #F5BA4B | 非緊急輔助資訊，不能單靠顏色表示已安全 |
| TPColors.red600 | #C2332F | 緊急求助與高度警示操作；可搭白字 |
| TPColors.grayscale50 | #F1F3F4 | 淺色背景 |
| TPColors.grayscale900 | #171B1D | 主要文字 |
| TPColors.white | #FFFFFF | 白色背景 |

## 可讀配對

下列為不透明 sRGB 的相對亮度計算；一般文字至少 4.5:1，大字及必要非文字資訊至少 3:1。配對數字不等於整個 App 已通過 WCAG 2.2 AA。

| 前景／背景 | 對比約值 | 結論 |
|---|---:|---|
| white／primary500 | 2.39:1 | 不適用一般字、大字或需 3:1 的必要資訊 |
| grayscale900／primary500 | 7.24:1 | 可用於一般文字 |
| white／primary700 | 5.89:1 | 可用於一般文字 |
| white／primary600 | 3.79:1 | 不適用一般小字 |
| white／red500 | 4.10:1 | 不適用一般小字 |
| white／red600 | 5.51:1 | 可用於一般文字 |
| grayscale900／white | 17.34:1 | 可用於一般文字 |
| grayscale900／grayscale50 | 15.58:1 | 可用於一般文字 |
| grayscale700／white | 8.02:1 | 可用於次要文字 |
| secondary800／secondary50 | 6.69:1 | 可用於非緊急輔助文字 |

依據：[WCAG 2.2](https://www.w3.org/TR/WCAG22/)、[文字對比](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)、[非文字對比](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html)。實際透明度、背景與狀態改變後需要重算，不沿用表中的結論。

## 語意與維護

- 紅色專用於緊急求助／高度警示，不把模擬陪伴做成警消報案，也不以顏色表示已受理。
- 一般導航與陪伴沿用官方品牌色；顏色不構成道路安全保證。
- Mock、未知、定位失敗、未配置等狀態必須有文字或其他可理解資訊；不能只靠顏色區分。
- 不自行建立第二份色值或修改全站品牌色。新增色彩先由 M3 提出理由、對比配對與語意，交 M1 協調。
- Legacy React `DESIGN_SYSTEM.md` 及 CSS tokens 不約束本專案；沒有移植其版型、圓角、陰影、寬高或 Widget Tree。
