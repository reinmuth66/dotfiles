// 仮の preview (本物は後の計画)。名前を薄い字で 1 行だけ描く
import { View, div } from "gpui-kit";
import { theme } from "herdr";

export default class Placeholder extends View {
  render() {
    return div().size_full().p(10).text_size(12).text_color(theme().dim).child("preview");
  }
}
