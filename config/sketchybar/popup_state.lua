-- 歯車 (system) と Spotify のポップアップの間で共有する状態。items/ のモジュールは同じ Lua の状態で動くので、
-- require で同じテーブルを得られる。
--   system_open: system のポップアップが開いている (ホバー中、またはピン留め中)。
-- 両方のポップアップは同じ場所で重なる。Spotify の棒グラフの窓 (window level 100) は、SketchyBar のポップアップ
-- (101) より下に描かれるので、system のポップアップが開いている間に出すと、Spotify の背景 (窓が描く) だけが
-- system のポップアップの下に回り、文字・画像 (101) だけが上に出て、前後がばらばらに見える。
-- そのため、system のポップアップが開いている間は棒グラフを出さず、Spotify のポップアップ自身の背景で描く。
return { system_open = false }
