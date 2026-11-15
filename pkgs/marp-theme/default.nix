# デザインシステム (config/design-system) から marp のテーマを組み立てる。
# 値は tokens.json にだけ書き、ここで CSS の変数にする。変数名は、デザインシステムのページが
# 作る tokens.css と同じ (--<トークン名>、書体は --font-<キー>) にして、部品の CSS を両方で使えるようにする。
{
  lib,
  writeTextDir,
  name ? "modern",
  tokensFile ? ../../config/design-system/project/tokens.json,
  bundleCss ? ../../config/design-system/project/components/bundle.css,
  layoutCss ? ../../config/marp/layout.css,
}:
let
  tokens = builtins.fromJSON (builtins.readFile tokensFile);
  firstTheme = (builtins.head tokens.color.themes).id;

  # type 以外の族は、どれも { tokens = [ { name, value } ]; } の形をしている
  families = lib.filterAttrs (key: family: key != "type" && family ? tokens) tokens;
  allTokens = lib.concatMap (family: family.tokens) (lib.attrValues families);
  byName = lib.listToAttrs (map (token: lib.nameValuePair token.name token) allTokens);

  checkName =
    tokenName:
    if builtins.match "[A-Za-z0-9_-]+" tokenName == null then
      throw "marp-theme: トークン名 '${tokenName}' は CSS の変数名にできない"
    else
      tokenName;

  # テーマごとの値は最初のテーマを取り、別名 "{name}" は var(--name) にする
  resolve =
    token:
    let
      raw = if builtins.isAttrs token.value then token.value.${firstTheme} else toString token.value;
      alias = builtins.match "\\{(.+)}" raw;
    in
    if alias == null then
      raw
    else if byName ? ${builtins.head alias} then
      "var(--${builtins.head alias})"
    else
      throw "marp-theme: '${token.name}' の別名先 '${builtins.head alias}' がない";

  declare = token: "  --${checkName token.name}: ${resolve token};";

  fontDeclarations = lib.mapAttrsToList (
    key: stack: "  --font-${checkName key}: ${stack};"
  ) tokens.type.families;

  # type のスタイル (ページの Typography 表示用) と font-size-* のトークンは同じ値を 2 回書くので、ずれたら止める
  styles = lib.concatMap (group: group.styles) tokens.type.groups;
  # builtins.all は全ての要素を評価する。map で作ったリストの長さを見るだけでは、中の throw が評価されない
  stylesMatch = builtins.all (
    style:
    let
      token = byName."font-size-${style.name}" or null;
    in
    if token == null || token.value != style.fontSize then
      throw "marp-theme: type のスタイル '${style.name}' と font-size-${style.name} の値が違う"
    else
      true
  ) styles;

  # section.small-text は、文字と行間を一定の比率で縮める。変数は自分自身を参照できないので、値をここで埋める
  scaled =
    prefix: scale:
    map (token: "  --${token.name}: calc(${resolve token} * var(--${scale}));") (
      lib.filter (token: lib.hasPrefix prefix token.name && token.name != "font-size-footer") allTokens
    );

  googleFonts = lib.concatMapStringsSep "&" (
    font: "family=${lib.replaceStrings [ " " ] [ "+" ] font}"
  ) tokens.meta.googleFonts;

  css = lib.concatStringsSep "\n" (
    [
      "/*"
      " * @theme ${name}"
      " * @auto-scaling true"
      " */"
      ""
      "/* このファイルは pkgs/marp-theme が生成する。値は config/design-system/project/tokens.json で変える */"
      "@import url('https://fonts.googleapis.com/css2?${googleFonts}&display=swap');"
      "@import 'default';"
      ""
      ":root {"
    ]
    ++ map declare allTokens
    ++ fontDeclarations
    ++ [
      "}"
      ""
      "section.small-text {"
    ]
    ++ scaled "font-size-" "small-text-scale"
    ++ scaled "line-height-" "small-text-leading-scale"
    ++ [
      "}"
      ""
      (builtins.readFile bundleCss)
      (builtins.readFile layoutCss)
    ]
  );
in
assert stylesMatch;
writeTextDir "${name}.css" css
