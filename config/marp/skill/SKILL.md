---
name: marp-modern
description: Use when creating, editing, or reviewing Marp slides (Markdown with `marp: true`), especially ones that use or should use `theme: modern` — 発表スライド、研究発表、授業のスライドを Marp で作る・直す・図を足すとき。Also use when a slide needs a table of contents, section slides, cards, boxes, or a diagram with arrows between elements, or when `:::` blocks or `a -> b` lines appear in slide Markdown.
---

# marp-modern

## 概要

`theme: modern` は、この環境の marp の既定のテーマ。色と大きさは決まった変数から選び、部品は短い記法 (`:::`) で書く。**スライドごとに `<style>` で見た目を作らない。** 見た目が足りないと感じたら、まず既にある部品の組み合わせで表す。

記法の全ての説明は、この skill と同じディレクトリの `syntax.md` にある。下の早見表にない書き方が要るとき、図の線が思ったとおりに出ないときは、推測せずに `syntax.md` を読む。

## 始め方

```markdown
---
marp: true
theme: modern
paginate: true
---
```

## 変換して、目で確かめる

変換は、必ず次の形で行う (PDF は `--pdf`、PPTX は `--pptx`)。

```sh
command marp --config "$HOME/.marprc.yml" --no-stdin slides.md --pdf
```

- `--no-stdin` がないと、エージェントから実行したときに標準入力を待って、何も出さずに止まる。
- テーマと拡張は `~/.marprc.yml` が指している。対話のシェルでは `marp` という関数がこの指定を足すが、`timeout` や別のシェル越しでは関数を通らない。そのときは、エラーも警告もなく、`:::` が文字のまま出た PDF ができる。上の形なら、どこから呼んでも同じ結果になる。

書いたら、画像にして見る。はみ出し、折り返し、線の重なりは、原稿を読んでも分からない。

```sh
command marp --config "$HOME/.marprc.yml" --no-stdin slides.md --images png -o check/s.png
```

できた `check/s.001.png` などを Read で開き、直したスライドを全て見る。見るところは、題が 1 行に収まっているか、中身が右や下にはみ出していないか、`:::` が文字のまま出ていないか、線が要素や題に重なっていないか。変換のときに `[modern]` で始まる警告が出たら、線の名前が間違っている。

## スライドの骨組み

```markdown
<!-- _class: title -->
# 題
### 名前

---

<!-- _class: toc -->
# 目次

1. 背景
2. 手法

---

<!-- _class: section -->
## 背景

---

# このスライドの主張
```

- 目次は、`toc` と番号付きリストだけで書く。番号の `<span>` を書かない。
- 章の扉は、`section` と `##` だけで書く。番号は自動で付く。
- フッターを書かない。章の扉の見出しが、次の扉まで自動で入る。
- 目次の順番と、章の扉の順番を揃える。目次の項目は、扉の見出しと同じ短い名前にする。
- 章の扉の見出しは `##` で書く。`#` は左上の題の位置に出るので、扉が崩れる。
- 章の扉は 1 章につき 1 枚かかる。枚数の指定があるときは、扉も数に入れて章の数を決める (8 枚なら 2 章か 3 章)。短い「まとめ」は章にせず、最後の章の中の 1 枚にする。

## 早見表

| やりたいこと | 書き方 |
|---|---|
| 説明をまとめる枠 | `::: card` 〜 `:::`。強調は `card accent`、問題は `card warn` |
| 図の要素 | `::: box` 〜 `:::`。処理は `dark`、中間の結果は `light`、結論は `blue-fill`、問題は `warn`、対象外は `muted` |
| card や box の角丸をなくす | 修飾に `square` を足す (`::: box dark square #model`、`::: card accent square`) |
| 横に並べる、縦に並べる | `::: row center`、`::: col` |
| 一直線の流れに矢印の文字を置く | 要素の間に `::: arrow` 〜 `:::` で `→` や `↓` を書く。つながった線ではない |
| 等幅の 2 列、3 列 | `::: grid2`、`::: grid3` |
| 要素を線でつなぐ | `::: diagram` の中で `#名前` を付け、`a.right -> b.left` |
| 文中の語に色 | `<span class="blue">語</span>`。強調は `blue`、否定は `red` |
| 文字の多いスライド | `<!-- _class: small-text -->` |
| 文の横に画像 | `<!-- _class: content-image-right -->` |

## 図の書き方

```markdown
::: diagram row center
::: box #in
入力
:::
::: box dark #model
モデル
:::
::: box blue-fill #out
出力
:::

in -> model
model -> out {blue} : 推論
out.bottom -> in.bottom {dashed} : 再学習
:::
```

- 線は `出る要素.辺 -> 入る要素.辺 {指定} : ラベル`。辺は `top`、`right`、`bottom`、`left`。省くと自動で選ばれる。
- `->` は矢印、`--` は矢じりなし、`<->` は両方向。指定は `blue`、`red`、`dashed`。
- 経路は辺の組み合わせで決まる。向かい合う辺は直線、直交する辺は L 字、同じ向きの辺 (`bottom` → `bottom`) は外側を回るコの字。
- 線の行は、ほかの文と空行で区切り、線だけの段落にする。
- 線が要素に重なったら、出る辺と入る辺を変える。位置を数値で動かさない。

枝分かれと合流は、`diagram` の中に `col` を入れて、縦に積んだ組を横に並べる。

```markdown
<!-- _class: align-center -->
# 誤差は、両方のエンコーダに戻す

::: diagram row center
::: col
::: box #img
画像
:::
::: box #meta
メタデータ
:::
:::
::: col
::: box dark #imgenc
画像<br>エンコーダ
:::
::: box dark #metaenc
メタデータ<br>エンコーダ
:::
:::
::: box light #feat
結合
:::
::: box blue-fill #out
予測
:::

img -> imgenc
meta -> metaenc
imgenc -> feat
metaenc -> feat
feat -> out
out.top -> imgenc.top {dashed} : 誤差を戻す
out.bottom -> metaenc.bottom {dashed}
:::
```

- 横に並べるのは 5 列まで。box の中は短い言葉にし、長いときは `<br>` で 2 行にする。あふれたら、言葉を削るか、列を減らす。
- 外側を回る線 (コの字) は、図の上と下に場所を取る。題に重なるときは、`<!-- _class: align-center -->` で図を縦の中央に置く。
- 戻る線は `dashed` で区別する。`red` は問題や否定を表す色なので、ただ戻るだけの線には使わない。

## 守ること

- 1 枚のスライドに、主張は 1 つ。題 (`#`) は 1 行に収める。
- 本文より小さい文字にしない。入らない量は、スライドを分ける。`small-text` は、表と補足のスライドにだけ使う。
- 1 枚で使う有彩色は、`blue` と、多くてもあと 1 色。
- 色で役割を示す。同じ図の中で、同じ役割には同じ種類の box を使う。`blue-fill` は 1 つの図に 1 つまで。
- 色、大きさ、余白の値を直接書かない (`#005599`、`font-size: 26px` など)。どうしても CSS が要るときは、変数で指す (`var(--blue)`、`var(--font-size-small)`、`var(--space-4)`)。
- 絵文字を使わない。影とグラデーションを足さない。

## よくある間違い

| 間違い | 正しくは |
|---|---|
| `<div class="toc">` と `<span class="toc-num">` で目次を組む | `<!-- _class: toc -->` と番号付きリスト |
| 全スライドに `<!-- footer: … -->` を書く | 書かない。章の扉から自動で入る |
| 要素の間に `→` の文字を置いて、枝分かれのある図を作る | `::: diagram` と線の記法 |
| `marp slides.md --pdf` とだけ書いて実行する | 上の「変換して、目で確かめる」の形で実行する。止まるか、`:::` が効かない |
| 変換できたことだけを見て終える | 画像にして、直したスライドを見る |
| `:::` を閉じ忘れる | 開いた数だけ `:::` で閉じる。閉じ忘れると、文字のまま出る |
| `:::` の枠の中に `---` を書く | 枠はスライドをまたげない。区切りの前で閉じる |
| 1 つの図で、角丸ありの box と `square` の box を混ぜる | どちらかに揃える |
| 線の行を、説明の文と同じ段落に書く | 空行で区切る |
| スライドの `<style>` に `.box` や `.card` を定義し直す | テーマにあるものを使う |
| 図の要素の位置を `margin` や `position` で調整する | `row`、`col`、`grid2`、`grid3` の入れ子で並べる |

## 効かない環境

`:::` の記法、章の番号、フッターの自動反映、図の線は、この環境の `marp` コマンドでだけ効く。VS Code の marp のプレビューや、ほかの PC では効かない。ほかの人にスライドの原稿を渡すときは、変換した PDF か PPTX を渡す。
