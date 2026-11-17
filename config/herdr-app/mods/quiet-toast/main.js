// 通知の表示の差し替え。エージェントの終了と入力待ちの通知は表示せずに閉じる (音は settings.json の
// sounds が鳴らす)。それ以外は、同梱の toast と同じ見た目 (view.js は同梱の mods/toast/main.js の写し) で出す
import { div } from "gpui-kit";
import { props, closeOverlay, checking } from "herdr";
import Toast from "./view.js";
import { shouldSuppress } from "./logic.js";

export default class QuietToast extends Toast {
  init() {
    const p = props();
    this.suppressed = shouldSuppress(p);
    if (this.suppressed && !checking()) closeOverlay(p.overlay);
  }

  render(cx) {
    return this.suppressed ? div() : super.render(cx);
  }
}
