// workbench.json の wtr の枠が映すターミナル (名前 wtr) の起こし方。herdr の API は使わない (node で試せるように)
// ターミナルは herdr-wtr (modules/herdr-app.nix) を動かす。herdr-wtr は wtr を子として起こし直し続け、ターミナルは終わらない。
// wtr をターミナルのプログラムそのものにしない: --keep のプログラムが signal で死ぬと、core はシェルに差し替え
// (reason "signaled")、herdr の枠のつながりが切れて描き直さなくなる (2026-11-26 に確かめた。子の wtr が死んでも core は何もしない)

export const WTR_NAME = "wtr";
export const WTR_PROGRAM = "herdr-wtr";

// --keep: core が落ちたとき (再起動など) も、ターミナルを残す (枠を落とさせない)。代わりにシェルが動くので、
// それは herdr-wtr に戻す
export const WTR_START = ["run", "--bg", "--keep", "--no-parent", "--name", WTR_NAME, "--", WTR_PROGRAM];

// --keep で残ったときに動くシェル
const SHELLS = new Set(["zsh", "bash", "sh", "fish"]);

// terminals() から、することを決める。"start": 起こす。"check": シェルから始まったターミナルなので、
// 今動いているもの (hc get の foreground) を確かめる。null: 何もしない (herdr-wtr か、人が動かした別のもの)。
// agent は最初のプログラムの名前で、シェルで exec herdr-wtr したあとも zsh のまま (動いている herdr で見た)
export function wtrAction(list) {
  const t = list.find((x) => x.name === WTR_NAME && x.state === "live");
  if (!t) return "start";
  if (SHELLS.has(t.agent)) return "check";
  return null;
}

// hc get <wtr> --json の foreground から、シェルが手前にいる (何も動かしていない) かを決める。
// そのときだけ exec herdr-wtr を打つ (wtr などが動いているところに打たない)。herdr-wtr も bash で動くので、
// 名前だけでなく、スクリプトを渡されていない (引数が - で始まるものだけ。/bin/zsh -l など) ことも見る
export function shellIsIdle(info) {
  const fg = info?.foreground;
  if (!SHELLS.has(fg?.name)) return false;
  return (fg.argv ?? []).slice(1).every((a) => a.startsWith("-"));
}
