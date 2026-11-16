# 図の完成した例

`::: diagram` を、開いてから閉じるまで省かずに書いた例。言葉 (`hoge`、`fuga` など) に意味はない。形を写して、id と言葉を置き換えて使う。

## 枝分かれ、合流、戻る線

2 つの入力 (`hoge`、`fuga`) がそれぞれ処理 (`piyo`、`foo`) を通り、1 つ (`bar`) に合流して、結論 (`baz`) に進む。結論から、2 つの処理に戻る。

```markdown
<!-- _class: align-center -->
# hoge

::: diagram row center
::: col
::: box #hoge
hoge
:::
::: box #fuga
fuga
:::
:::
::: col
::: box dark #piyo
piyo
:::
::: box dark #foo
foo
:::
:::
::: box light #bar
bar
:::
::: box blue-fill #baz
baz
:::

hoge -> piyo
fuga -> foo
piyo -> bar
foo -> bar
bar -> baz
baz.top -> piyo.top {dashed} : qux
baz.bottom -> foo.bottom {dashed}
:::
```

この例で使っている形:

- 横の並びは `diagram row center`。その中の `col` が、縦に積んだ 1 列になる。`col` は、中の box を全て書いてから `:::` で閉じる。
- 線は、最後の box を閉じた後に、空行を 1 つ置いて書く。線の段落の中に空行は置かない。
- 進む線は辺を省く。隣の列に向かって、向かい合う辺が選ばれる。
- 戻る線は、進む線が使っていない辺 (`top`、`bottom`) から出して、同じ向きの辺に入れる。外側を回るコの字になる。上の列には `top`、下の列には `bottom` を使う。
- 戻る線は `dashed`。ラベルは 1 本にだけ付ける。
- 外側を回る線が題に近づくので、スライドに `align-center` を付ける。

## 1 つから 2 つに分かれる

```markdown
::: diagram row center
::: box #hoge
hoge
:::
::: box dark #fuga
fuga
:::
::: col
::: box blue-fill #piyo
piyo
:::
::: box #foo
foo
:::
:::

hoge -> fuga
fuga -> piyo
fuga -> foo
:::
```

ラベルは、線の最も長い区間の中央に置かれ、その場所の線は描かれない。短い線に付けると線がほとんど隠れるので、ラベルは長い線 (横に並んだ要素の間、外側を回る線) に付ける。

## 縦の流れ

```markdown
::: diagram col
::: box #hoge
hoge
:::
::: box dark #fuga
fuga
:::
::: box blue-fill #piyo
piyo
:::

hoge -> fuga
fuga -> piyo
:::
```

## 格子に置く

`grid3` は、box を左上から順に 3 列で並べる。離れた box は、辺を指定して L 字でつなぐ。

```markdown
::: diagram grid3
::: box #hoge
hoge
:::
::: box dark #fuga
fuga
:::
::: box light #piyo
piyo
:::
::: box #foo
foo
:::
::: box dark #bar
bar
:::
::: box blue-fill #baz
baz
:::

hoge -> fuga
fuga -> piyo
foo -> bar
bar -> baz
piyo.bottom -> baz.top
hoge.bottom -> foo.top {dashed}
:::
```
