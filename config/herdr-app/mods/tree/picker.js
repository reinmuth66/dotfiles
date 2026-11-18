// ブランチを選ぶ窓の描画。判断は branches.js、開け閉めとキーは main.js
import { div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { theme } from "herdr";
import { GLYPH, METRICS, PALETTE } from "./ui.js";

export const PICKER_ROWS = 8;

const baseName = (path) => path.replace(/\/+$/, "").split("/").pop() || path;

// 8 行に収まるよう、カーソルが見える範囲を切り出す
function visible(rows, cursor) {
  if (rows.length <= PICKER_ROWS) return { start: 0, items: rows };
  const start = Math.max(0, Math.min(cursor - PICKER_ROWS + 1, rows.length - PICKER_ROWS));
  return { start, items: rows.slice(start, start + PICKER_ROWS) };
}

function renderRow(b, selected) {
  const note = b.worktree ? baseName(b.worktree) : b.kind === "remote" ? b.remote : null;
  return h_flex()
    .flex_none()
    .w_full()
    .h(METRICS.treeRow)
    .px(METRICS.padLeft)
    .items_center()
    .when(selected, (x) => x.bg(PALETTE.surface0))
    .child(
      div()
        .flex_none()
        .w(METRICS.glyphCol)
        .text_size(METRICS.glyphSize)
        .text_color(PALETTE.sky)
        .child(b.current ? GLYPH.branch : ""),
    )
    .child(
      div()
        .flex_1()
        .min_w(0)
        .truncate()
        .text_color(b.worktree ? theme().dim : PALETTE.text)
        .child(b.name),
    )
    .children(note ? [div().flex_none().pl(METRICS.padLeft).text_color(theme().dim).child(note)] : []);
}

export function renderPicker({ query, rows, cursor, message, width }) {
  const { start, items } = visible(rows, cursor);
  return v_flex()
    .id("tree-picker")
    .when(Number.isFinite(width), (x) => x.w(width))
    .when(!Number.isFinite(width), (x) => x.w_full())
    .py(4)
    .bg(theme().popover)
    .border_1()
    .border_color(theme().border)
    .rounded(6)
    .shadow_md()
    .overflow_hidden()
    .child(
      h_flex()
        .flex_none()
        .h(METRICS.treeRow)
        .px(METRICS.padLeft)
        .items_center()
        .font_weight(700)
        .text_color(PALETTE.subtext0)
        .child("Switch branch"),
    )
    .child(
      h_flex()
        .flex_none()
        .h(METRICS.treeRow)
        .px(METRICS.padLeft)
        .items_center()
        .child(div().flex_1().min_w(0).truncate().text_color(PALETTE.text).child(`> ${query}`)),
    )
    .children(items.map((b, i) => renderRow(b, start + i === cursor)))
    .children(
      message
        ? [
            div()
              .flex_none()
              .px(METRICS.padLeft)
              .py(4)
              .text_color(PALETTE.peach)
              .child(message),
          ]
        : [],
    );
}
