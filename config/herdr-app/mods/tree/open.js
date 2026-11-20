// ファイルを開くツールの決め方。正本は config/herdr-app/shared/open.js。
// ui.js と同じく、使う mod (preview と tree) のフォルダに cp で写す。herdr の API は使わない (node で試せるように)

// 専用のツール。fx は JSON だけ (YAML を fx で開くと JSON の形に変わり、コメントが消える)
const TOOLS = { csv: "csvlens", tsv: "csvlens", json: "fx" };

const extOf = (path) => {
  const name = String(path).split("/").pop() ?? "";
  const i = name.lastIndexOf(".");
  return i > 0 ? name.slice(i + 1).toLowerCase() : "";
};

// how: "edit" は nvim で開く (直す)。"tool" は専用のツールで開き、無ければ nvim
export function openArgv(path, how) {
  const tool = how === "tool" ? TOOLS[extOf(path)] : null;
  return [tool ?? "nvim", path];
}

// ツールを動かすフォルダ。リポジトリの根が分かればそこ、無ければファイルのフォルダ (tree と preview で同じにする)
export function openCwd(path, root) {
  return root || String(path).replace(/\/[^/]*$/, "") || "/";
}

// preview が開いたツールのターミナルに付ける印 (hc run --label)。preview の mod が作り直されても見つけられる
export const OPEN_LABEL = "herdr-preview=open";

// terminals() から、preview が開いて、まだ動いているターミナルを探す。
// 動いている herdr で見た形: state は "live"、--rm で起こしたものは終わると一覧から消える
export function openTerminalOf(list) {
  const [key, value] = OPEN_LABEL.split("=");
  return list.find((t) => t.state === "live" && t.labels?.[key] === value) ?? null;
}
