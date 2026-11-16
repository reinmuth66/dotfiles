# HTML と style で書いた原稿を、記法に置き換える

手書きの HTML と CSS で作ったスライドを、テーマ `modern` の記法に直すときの対応表。左の形を見つけたら、右の形に置き換える。class の名前 (`hoge`、`fuga` など) は原稿ごとに違うので、名前ではなく役割で対応を決める。

## 原稿の全体

| 元の形 | 置き換え |
|---|---|
| front matter の `theme: <ほかのテーマ>` | `theme: modern` |
| front matter の `style: \|` のブロック、`<style>` のブロック | 消す。見た目は下の記法で作る |
| front matter の `footer: "hoge"` | 消す。章の扉から自動で入る |
| スライドごとの `<!-- footer: "1. hoge" -->` | 消す。章の扉から自動で入る |

## スライドの種類

| 元の形 | 置き換え |
|---|---|
| 題と名前を中央に置いた 1 枚目 | `<!-- _class: title -->`、`# hoge`、`### fuga` |
| `<div class="hoge"><div><span>1.</span>fuga</div>…</div>` の目次 | `<!-- _class: toc -->`、`# hoge`、`1. fuga` の番号付きリスト |
| `# <span>1.</span>hoge` や `# 1. hoge` だけのスライド (章の区切り) | `<!-- _class: section -->`、`## hoge` |
| `<!-- _class: lead -->` で中央に置いた章の区切り | `<!-- _class: section -->`、`## hoge` |

## 枠と並び

| 元の形 | 置き換え |
|---|---|
| 枠線と余白を付けた `<div class="hoge">` に、見出しと箇条書き | `::: card`、`#### hoge`、`- fuga`、`:::` |
| その枠の色違い (強調) | `::: card accent` |
| その枠の色違い (問題、欠点) | `::: card warn` |
| `display: grid` で 2 列、3 列にした `<div>` | `::: grid2`、`::: grid3` |
| `display: flex` で横に並べた `<div>` | `::: row center` |
| `flex-direction: column` で縦に並べた `<div>` | `::: col` |
| `<h4>hoge</h4>`、`<ul><li>fuga</li></ul>` | `#### hoge`、`- fuga` |

## 図

| 元の形 | 置き換え |
|---|---|
| 枠線を付けた短い言葉の `<div class="hoge">fuga</div>` | `::: box`、`fuga`、`:::` |
| 地を濃くした枠 (処理) | `::: box dark` |
| 地を薄い色にした枠 (中間の結果) | `::: box light` |
| 地を主役の色にした枠 (結論) | `::: box blue-fill` |
| 赤い枠 (問題) | `::: box warn` |
| 破線の枠 (対象外) | `::: box muted` |
| 枠の間に置いた `<span>→</span>` (一直線の流れ) | `::: arrow`、`→`、`:::` |
| `margin` や `position` で枠をずらして作った枝分かれ | `::: diagram row center` の中に、`::: col` で縦に積んだ組を並べ、`hoge -> fuga` の線でつなぐ |
| 手書きの `<svg>` の線や矢印 | `::: diagram` の中の `hoge.right -> fuga.left` |

## 文字

| 元の形 | 置き換え |
|---|---|
| `<span style="color: #…">hoge</span>` (強調) | `<span class="blue">hoge</span>` |
| `<span style="color: #…">hoge</span>` (否定、問題) | `<span class="red">hoge</span>` |
| `style="font-size: …px"` で小さくした 1 行 | 大きさの指定を外し、本文と同じ大きさにする |
| `style="font-size: …px"` をスライド全体に付けて詰めた表 | `<!-- _class: small-text -->` |
| `style="text-align: center"` | `<!-- _class: text-center -->` |
| 残す必要のある CSS の値 (`#…`、`…px`) | 変数にする (`var(--blue)`、`var(--font-size-small)`、`var(--space-4)`) |
