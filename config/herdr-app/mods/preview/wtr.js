// workbench.json の wtr の枠が映すターミナル (名前 wtr) の起こし方。herdr の API は使わない (node で試せるように)
// ターミナルは herdr-wtr (modules/herdr-app.nix) を動かす。herdr-wtr は wtr を起こし直し続け、ターミナルは終わらない

export const WTR_NAME = "wtr";
export const WTR_PROGRAM = "herdr-wtr";

// --keep: core が落ちたとき (再起動など) も、ターミナルを残す (枠を落とさせない)。代わりにシェルが動くので、
// それは wtrAction が "exec" で herdr-wtr に戻す
export const WTR_START = ["run", "--bg", "--keep", "--no-parent", "--name", WTR_NAME, "--", WTR_PROGRAM];

// --keep で残ったときに動くシェル。hc の agent はプログラムの名前 (動いている herdr で見た)
const SHELLS = new Set(["zsh", "bash", "sh", "fish"]);

// terminals() から、することを決める。"start": 起こす。"exec": 残ったシェルで herdr-wtr を動かす。null: 何もしない
// (herdr-wtr が動いている、または人が別のもの (wtr を直に動かすなど) を動かしている)
export function wtrAction(list) {
  const t = list.find((x) => x.name === WTR_NAME && x.state === "live");
  if (!t) return "start";
  if (SHELLS.has(t.agent)) return "exec";
  return null;
}
