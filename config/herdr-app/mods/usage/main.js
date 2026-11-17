// 仮の usage (本物は後の計画)。帯の文字の 1 文字分の幅と、Nerd Fonts の記号の見え方を確かめるために、
// 10 文字の "0" と記号を描き、"0" 10 文字の幅を data/usage-measure.json に書く
import { View, div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { theme, checking, writeTextFile } from "herdr";

const FONT = "Moralerspace Neon HW";
// md_archive、md_duck、oct_diff_modified、md_alert_circle、md_check_circle、oct_git_branch
const GLYPHS = ["\u{f003c}", "\u{f01e5}", "\u{f459}", "\u{f0028}", "\u{f05e0}", "\u{f418}"];

export default class UsagePlaceholder extends View {
  render() {
    const t = theme();
    return v_flex()
      .size_full()
      .px(10)
      .py(6)
      .gap(4)
      .font_family(FONT)
      .text_size(13)
      .text_color(t.muted)
      .child(
        h_flex().child(
          div()
            .id("zeros")
            .flex_none()
            .child("0000000000")
            .on_size_change((size) => {
              if (checking() || this.width === size.width) return;
              this.width = size.width;
              writeTextFile(
                "/Users/reinmuth/.config/herdr-app/data/usage-measure.json",
                JSON.stringify({ font: FONT, size: 13, tenCharsWidth: size.width, cell: size.width / 10 }),
                null,
              );
            }),
        ),
      )
      .child(h_flex().gap(8).text_size(16).children(GLYPHS.map((g, i) => div().id(`g${i}`).child(g))));
  }
}
