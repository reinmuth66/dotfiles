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

変換は `marp slides.md` (PDF は `--pdf`、PPTX は `--pptx`)。テーマと拡張の指定は要らない。

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
- 目次の順番と、章の扉の順番を揃える。

## 早見表

| やりたいこと | 書き方 |
|---|---|
| 説明をまとめる枠 | `::: card` 〜 `:::`。強調は `card accent`、問題は `card warn` |
| 図の要素 | `::: box` 〜 `:::`。処理は `dark`、中間の結果は `light`、結論は `blue-fill`、問題は `warn`、対象外は `muted` |
| 横に並べる、縦に並べる | `::: row center`、`::: col` |
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
| `:::` を閉じ忘れる | 開いた数だけ `:::` で閉じる。閉じ忘れると、文字のまま出る |
| 線の行を、説明の文と同じ段落に書く | 空行で区切る |
| スライドの `<style>` に `.box` や `.card` を定義し直す | テーマにあるものを使う |
| 図の要素の位置を `margin` や `position` で調整する | `row`、`col`、`grid2`、`grid3` の入れ子で並べる |

## 効かない環境

`:::` の記法、章の番号、フッターの自動反映、図の線は、この環境の `marp` コマンドでだけ効く。VS Code の marp のプレビューや、ほかの PC では効かない。ほかの人にスライドの原稿を渡すときは、変換した PDF か PPTX を渡す。
