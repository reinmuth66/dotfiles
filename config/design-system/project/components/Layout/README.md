box や card を並べる配置。横に並べる `row`、縦に並べる `col`、等幅の列にする `grid2` と `grid3`。

## 使い分け

| 配置 | 使う場面 |
|---|---|
| `row` | box を横に並べる。中身の幅に合わせて詰める。`center` を付けると中央に寄せる |
| `col` | box を縦に並べる |
| `grid2`、`grid3` | card を同じ幅で 2 列、3 列に並べる |

## 書き方

```html
<div class="row center">
  <div class="box">入力</div>
  <div class="box dark">処理</div>
</div>
```

```jsx
<Modern.Row center>
  <Modern.Box>入力</Modern.Box>
  <Modern.Box variant="dark">処理</Modern.Box>
</Modern.Row>
<Modern.Grid columns={2}>…</Modern.Grid>
```

marp:

```markdown
::: row center
::: box
入力
:::
::: box dark
処理
:::
:::
```

## 決まり

- 間隔は部品が決める (`row` と `col` は `space-3`、`grid2` は `space-6`、`grid3` は `space-5`)。個別に余白を足さない。
- 入れ子にできる。`row` の中に `col` を置くと、縦に積んだ組を横に並べられる。
- 要素の間に矢印を引くときは、`Diagram` で線をつなぐ。
