# 技術メモ

実装の構造と、変更時に壊れやすい箇所についてのメモです。

---

## 1. ファイル構成

| ファイル | 行数 | 内容 |
|---|---:|---|
| `index.html` | 2,054 | HTML / CSS / JS すべて。importmap + ES Modules |
| `trees.module.js` | 920 | 手続き生成ローポリ樹木ライブラリ（外部モジュール） |
| `assets/` | — | 画像 7 枚 |
| `start-game.cmd` | — | Windows 用ローカルサーバーランチャー |

`index.html` の内部は番号付きセクションで区切られています。

```
 1. CFG / DIFFS            設定
 2. 川の形状               cx() / halfW() / riverY() / DROPS
 3. ユーティリティ          clamp / damp / mulberry32 / vnoise
 4. シーン構築             川・岸・空・ライト
 5. コース生成             buildObstacles() / makeLedges() / makeFalls()
 6. 樹木                   buildTrees() / initTrees()
 7. カヤックとパドラー      makeKayak() / makePaddler()
 8. パーティクル
 9. HUD
10. タイトル / リザルト
11. サウンド（WebAudio 合成）
12. 入力
13. ゲーム状態
14. 物理更新
15. キャラクター更新
16. カメラ
17. 影 / 水面の泡 / HUD 更新
```

---

## 2. 依存関係

```html
<script type="importmap">
{ "imports": { "three": "https://cdn.jsdelivr.net/npm/three@0.160.0/build/three.module.js",
</script>
<script type="module">
import * as THREE from 'three';
import { Trees } from './trees.module.js';
```

- **ビルド不要**。バンドラもトランスパイラも通さない
- three.js は CDN 由来なので、**オフラインでは動きません**
- 配布する場合は CDN をローカルに置き換えるか `vendor/three.module.js` に置き換えてください

---

## 3. 描画の最適化

| 手法 | 対象 |
|---|---|
| `InstancedMesh` | 岩・ゲート旗・樹木・飛沫 |
| `g.update(camera)` | 樹木ライブラリが毎フレームカリング＆LOD |
| 共有ジオメトリ | 樹木は種ごとに 1 つの BufferGeometry を共有 |
| 固定 seed のインスタンス | 同じ環境を毎回生成するので GPU 側のキャッシュが効く |
| 水面メッシュ 2m 間隔 | 1650 行 × 15 列。段差の稜線を出すために 3m → 2m に密にした |

### 樹木

8 グループ（`willow` / `momiji` / `oak` / `ichou` / `fir` / `sugi` / `hinoki` / `shrub`）を
`InstancedMesh` で 1 つずつインスタンス化。

- **水際ほど密**：岸からの距離で Reject サンプリング（`Math.pow(R(), 1.7)`）
- **水辺は低く**：ヤナギはスケール 0.55〜0.9 に抑えて川を塞がない
- 合計 2,600 本 + 林床の低木 420 株

### 旗ゲートの高さ

`FLAG_POLE_H`（2.6m）がポールの高さ、旗はその 0.25m 下（2.35m）です。

- 遠景（木々や岩）と同じ高さになると、ゲートが読み取りにくくなる
- 上げすぎると川ではなく「門」に見えて現実感が失われる
- 先まで見すぎて難易度が下がるので、**少しずつ上げる**（2.4m → 2.6m）

値は `index.html` の `FLAG_POLE_H` を直せば全ゲートに反映されます。

### オール（パドル）の前後位置

`PADDLE_Z`（-0.18m）がオールの中軸の前後位置です（艇ローカル。-Z が船首）。

VRM を 1.3 倍にすると**胸が前に出る**ため、オールが胸の中に入って、
腕を脱臼したように見えてしまいます。胸の大きいモデルほど症状が出ます。

オールを前にずらすと握り点も一緒に前へ動くので、腕はそのまま届きます
（実測: IK 誤差 0mm、need/reach 0.62〜0.85 で余裕あり）。

---

## 4. 水面シェーダ

`MeshStandardMaterial` の `onBeforeCompile` でフラグメントシェーダを差し込んでいます。

```glsl
float zz = 90.0 - vSUv.y * 8.0;      // UV から z を復元
// 段差の lip：上流側は短く薄く、下流側（落ち先）は長く白く
float rapid = ...;
float pool  = ...;
foam = max(foam, max(lipFoam, poolFoam));
```

- `vSUv` は、水面メッシュに焼いた「z 座標を 8 分の 1 に縮めた」UV
- 白波は lip（±13m）、落ち先の飛沫プール（+26m）、岩の回り泡（uniform 配列で 32 個まで）を合成
- **霧が有効**。遠景の視界を 一定に濃くします

---

## 5. 変更時の落とし穴

実際に踏んだものを列挙します。

### ① 同一平面は z-fighting する

デッキ上面とコクピット上面が同じ `y = 0.57` になっていました。
黒の楕円が黄色とのディザノイズに化けます。

**対策**：重ねる面は 5cm 以上離す。上面を 0.635 に上げました。


### ② 軸の符号は「実際の向き」で確認する

ピッチの符号が逆で、**落ちながら機首が上がっていました**。絶果、演稽しながら落としてきませんでした。
`atan2(-x, 1)` と `atan2(x, 1)` の違いと同様に、片仮名と实物とがずれます。

**対策**：艇首・艇尾のローカル座標を `applyQuaternion()` して `y` 差を測る。
数値で見れば一発で分かります。


### ③ カメラの高さは「カメラ自身の z」の水位で計算する

艇の位置（`riverY(P.z)`）で高さを決めると、段差でカメラ自身が水面下に沈みます。
水面下に入ると近傍の水面が背面カリングされて、画面下部が平らな帯になります。

**対策**：`riverY(cameraZ)` を使う。下限クランプも入れる。


### ④ POV でカメラを完全固定すると手が見えなくなる

POV でカメラを目位置に完全固定すると、櫂が顔の 0.1m 先になり、
手の位置（横 ±0.52m）が画角の外へ逃げます。

**対策**：わずかな追従（`camK = 2e-6`）を残す。これが正解でした。


### ⑤ 自分の胸は POV で消す

頭・胴は POV で `visible = false`。
肩・上腕も消さないと、根元が至近すぎて赤い塊になります。


### ⑥ 段差の奥に何か置くとき、中央を空ける

lip の岩を岳幅いっぱいに並べると、カメラが岩の中に入ってしまい。

**対策**：中央 ±42% はスキップ。サイズも 0.7〜1.5m に。


### ⑦ 骨の rotation を直接触ると、quaternion 側が腐る

VRM アバターに「漕ぎに合わせて上体を傾ける」処理を入れたところ、
**体が高速で回転して、軸がないような状態**になりました。
派生症状として、前髪が消える、足が水面より上に出る、といった現象も出ました。

原因は three.js の `Object3D` における `quaternion` と `rotation` の連動です。

```js
rotation._onChange(onRotationChange);     // rotation -> quaternion
quaternion._onChange(onQuaternionChange); // quaternion -> rotation
```

ただし `quaternion.copy()` / `setFromEuler()` / `setFromRotationMatrix()` は
**onChange を発火しません**。つまり `quaternion` を直接書き換えると、
`rotation` 側は古い値のまま残り、あとから `rotation` が触られた時点で
onChange が発火して `quaternion.setFromEuler(rotation)` が走って
quaternion が上書きされます。

今回は **three-vrm のスプリングボーン管理も同じ腰の quaternion に
`copy()` で書き込んでいた**ため、二つの書き込みが競合し、
体の向きが 180 度フリップしていました。

**対策**：

- 骨を回すなら `rotation.set()` を使う（onChange が発火し、連動が保たれる）
- VRM の骨に自前の書き込みをするなら、**three-vrm と同じ対象**を書く
- そもそも VRM の骨は原則的に触らない

**検出法**（実際に助けになったもの）：

```js
// プロパティの setter ではなく、オブジェクトのメソッドをフックする
const q = hips.quaternion;
for (const name of ['copy', 'setFromEuler', 'setFromRotationMatrix']) {
  const orig = q[name].bind(q);
  q[name] = function () {
    console.log(name, new Error().stack);   // 誰が書いたか
    return orig.apply(null, arguments);
  };
}
```

`hips.quaternion` の setter を貼っても 0 件しか取れませんでした。
**オブジェクトの中身を直接書き換える `copy()` などは setter を通らない**ためです。


### ⑧ three-vrm の骨は 3 層構造。姿勢は「正規化ノード」で書く

VRM を読み込んだあとに実測すると、次の 3 層が見えます。

| 層 | 名前（Grus の例） | 役割 |
|---|---|---|
| raw | `Hips` / `Spine` / `Chest` / `Neck` / `Head` | **描画を駆動する骨**（SkinnedMesh の `skeleton.bones`） |
| 正規化リグ | `Normalized_Chest` / `Normalized_Neck` | three-vrm が作った人型リグ。回転を raw へ自動コピーする |
| 揺れ物 | `Pigtail_R005` / `BangsRoot` … | スプリングボーンで動く髪・衣。首の子からぶら下がる |

**回転は「正規化ノード」で書く。**（実測で確かめた）

- `Normalized_Chest.rotation.set(0.25, 0, 0)` → 次の `vrm.update()` で
  raw の `Chest.rotation` が `0.25` になり、**頭のワールド位置も描画も動いた**
- raw の `Chest.rotation.set(0.25, 0, 0)` → 次の `vrm.update()` で
  **0 に戻された**

`VRMHumanoid.autoUpdateHumanBones`（既定で true）が
「正規化リグの回転を raw の骨へコピーする」ためで、
**raw を直接回しても 1 フレームで消える**します。

> 「`getNormalizedBoneNode()` は描画に反応しない」という思い込みは
> **逆**でした。描画に反応するのは正規化ノードのほうです。
> 反応しないのは「raw の骨に書き込んだ場合」です。
> この思い込みのまま上体の傾けを諦めていたのが、実装が遅れた原因です。

**上体の傾けは首と胸に掛ける。腰は掛けない。**

- 髪・服の骨は首の子（`Head` → `Head_2` / `Head_3` → `Pigtail_R005` など）なので、
  首を回せば髪も一緒に動き、**スプリングボーンが「首が動いた」と認識して髪を揺らす**
- 腰を回すと全身が回る。raw と proxy の競合で 180 度返る
- 使う正規化ノードは `chest` と `neck`。VRM 0.x / 1.0 / VRoid のどれにも必ずある
  （実測: Grus / mollymolly / MyAvatartest / vketdevil / Xbase / Marycia の 6 モデル）

```js
// 上体を傾ける（loadVRM で集めて、updateVRM で毎フレーム適用する）
for (const nm of ['chest', 'neck']) {
  const n = vrm.humanoid.getNormalizedBoneNode(nm);
  if (n) VRM.leanBones.push({ node: n, w: nm === 'chest' ? 0.6 : 0.4 });
}
// 毎フレーム（vrm.update() の「前」に呼ぶ）
for (const b of VRM.leanBones) b.node.rotation.set(x * b.w, y * b.w, z * b.w);
```

正規化ノードの rest 回転は 6 モデルすべてゼロだったので、
絶対値（`rotation.set`）で書けて問題ありません。

**骨は skin ごとに分かれている**。VRM の髪や服は別の skin を持つことが多い。

Grus の場合、`Body` の skin は 53 骨で、`Hair_Twintails` の skin は独立して 36 骨で、
そこに `BangsRoot` や `Pigtail_L/R` といった髪の骨がある。

**骨の数えを調べるときは、スケルトンの最大の skin だけを見てはいけない**。
一般には、**glTF のノード全体**と
**揺れ物の設定（`secondaryAnimation` / `VRMC_springBone`）**を見てください。

親のエージェントが「Grus の髪には骨がない」と判断してしまい、
統計を取り違えました。

### ⑨ 見た目の検証は「描画なしステップ」で数値で行う

タブが非表示（バックグラウンド）になると `requestAnimationFrame` が止まり、
スクショも描画も取得できません。でも **ゲームロジックだけなら
描画なしで進められます**。

```js
g.step(1 / 60, true);   // noRender = true。描画を飛ばして 1 フレーム進める
```

これを使うと、次のような検証がバックグラウンドでも行えます。

```js
// 腰が安定しているか（180 度フリップしていないか）
const w = [];
for (let i = 0; i < 500; i++) {
  g.step(1 / 60, true);
  if (i % 4 === 0) w.push(g.VRM.bones.hips.quaternion.w);
}
// w の最大と最小の差が 0 なら固定している
```

肩の `need / reach`（腕が届いているか）や、握り間隔の自動調整の収束も
同じ方法で測れます。**見た目の主張はまず数値で裏を取り、
エビデンスが揃ってからスクショで確認する**という順番にすると、
推測を挟まずに済みます。

---


---


### ⑩ スプリングボーンの center が null なら世界空間で計算される

VRM の髪や揺れ物は、アバターが流れる速さでも毛が後ろに引きついて、
**針金のように巻き上がってしまう** という問題がありました。

three-vrm の `VRMSpringBoneJoint.center` と `VRMSpringBoneColliderGroup.center` は
**Object3D の参照**（null なら世界空間）で、そこからの相対動きだけで計算される。

```js
const sm = vrm.springBoneManager;
const frame = vrm.scene;            // アバターのルート（艇の子）
for (const g of sm.colliderGroups) g.center = frame;
for (const j of sm._joints) j.center = frame;
sm.reset();                         // 基準を変えたので初期状態を取り直す
```

`center` を設定すると、**流れによっても毛が頭の位置から移動しない**ことになります。
しかし、アバター自体が動くと頭の位置に対してずれるので、毛は反応して揺れます。

**dt に上限をかけること**（`dt = Math.min(dt, 0.05)`）。
タブ切替や読み込みで長いフレームが挟まると、計算が乱れて破綻します。

**検証の方法**：髪や揺れ物の骨の、頭の骨からのオフセットを**船ローカル座標で**測り、
走行前と走行後のオフセットの差がミリ単位ならよい。

**基準は乗り物にする**。これを外すと、
移動速度で毛が後ろに張り付く。
`center` には世界空間ではなく、**乗り物に対しての相対動き**だけを計算する。


### ⑪ dt が負になると lerp の係数が壊れてカメラが NaN になる

`renderer.setAnimationLoop(loop)` に渡す `now` は
**rAF のタイムスタンプ（フレームの開始時刻）**です。
直前のフレームで `last = performance.now()` として記録すると、
`now < last` になり **`dt` が負**になり得ます。

```js
// 悪い例
const dt = Math.min(0.05, (now - last) / 1000);   // 負になり得る
```

`dt` が負ると、追従の係数 `1 - Math.pow(camK, dt)` が壊れます。

```js
const camK = camMode === 2 ? 2e-6 : camMode === 1 ? 0 : 8e-4;
camPos.lerp(desired, 1 - Math.pow(camK, dt));
```

`camMode === 1`（正面カメラ）では `camK` が **0** なので
`Math.pow(0, 負) = Infinity` になり、係数が `-Infinity` に。
`lerp` の計算が `NaN` になり、**カメラ位置が NaN になって画面が真っ黒になります**。

しかも `lerp` は `this += (v - this) * a` なので、
一度 NaN になると **NaN が貼り付いて回復しません**。

**対策**

1. `dt` を 0 以上にクランプする

   ```js
   const dt = Math.min(0.05, Math.max(0, (now - last) / 1000));
   ```

2. lerp の係数を 0..1 に収める（`camMode === 1` は「固定」なので 1 にする）

   ```js
   let camA = camMode === 1 ? 1 : 1 - Math.pow(camK, dt);
   if (!(camA >= 0)) camA = 0;     // NaN も弾く
   if (camA > 1) camA = 1;
   ```

同じ理屈で `damp()`（`1 - Math.pow(k, dt)` を使う）は
`dt >= 0` なら係数が 0..1 に入るので安全です。

**再現の手順**：`g.step()` は `last = performance.now() - dt * 1000` と書きます。
そのあと rAF が走るとタイムスタンプが古く、`dt` が負になります。
デバッグ用に `g.step()` を叩いていると**カメラが NaN になる**ので、
気づいたら `__camDbg` で `camPos` を見てください。

### ⑫ 天空ドームは「カメラに追従」させる

空は `SphereGeometry(1000)` のドームです。**これを世界原点に置いてえると、
コース終点でカメラがドームの外へ出てしまいます。**

- コースの長さは z = +20 〜 -1500。カメラは原点から最大 1430m 離れる
- ドームの半径は 1000m なので、z ≈ -1000 を越えたあたりで **カメラが外に出る**
- カメラが外に出ると `BackSide` の内側が見え、**空に大きな白い円弧が出る**

原因は 2 つありました。両方直しています。

**1. ドームの位置をカメラに追従させる**

```js
// ループの最後、render の直前で
sky.position.copy(camera.position);
```

**2. シェーダの視線方向を「原点から」ではなく「カメラから」にする**

```glsl
// 悪い例（原点からの方向）
vDir = normalize((modelMatrix * vec4(position,1.0)).xyz);
// 良い例（カメラからの方向）
vDir = normalize((modelMatrix * vec4(position,1.0)).xyz - cameraPosition);
```

1 だけ直すと、グラデーションの上下が原点基準のままなので
「空の天井が斜めを向く」「太陽の位置がズレる」という別の崩れが残ります。
`cameraPosition` は three.js がすべてのシェーダに注入する built-in uniform です。

**確認方法**：終点（z ≈ -1400）にワープして空を見る。
`g.P.z = -1400` として数フレーム進め、スクショを撮る。
---

## 6. デバッグ用のフック

`window.__game` に開発用の参照を公開しています。

```js
{
  scene, camera, renderer, kayak, paddler, rocks, gates, waterMesh,
  treeGroups, P, CFG, THREE,
  state, score, info, total, diff, camMode,   // camMode は書き込み可
  VRM,          // アバターの内部状態（bones / vrm / leanBones / facing など）
  loadVRM,      // 別の VRM を読み込む
  applyDiff,    // 難易度を差し替える
  step,         // 1 フレーム進める（noRender=true で高速再現）
}
```

さらに 2 つ:

| フック | 用途 |
|---|---|
| `window.__camDbg = 1` | 毎フレーム `updateCamera()` が `camPos` / `camLook` / `desired` / `look` を `window.__camDbg` に記録する。カメラが NaN になったときに使う（⑪ 参照） |
| `window.__game.VRM.vrm` | three-vrm の `VRM` インスタンス。`springBoneManager`（`_joints` / `colliderGroups`）を覗くために使う |

デバッグ例：

```js
const g = window.__game;
g.applyDiff('hard');
document.getElementById('start-btn').click();
g.P.z = -448;                 // 段差の手前にワープ
for (let i = 0; i < 60; i++) g.step(1/60, true);   // noRender で高速計算
```

`step(dt, true)` は描画をスキップするので、**数千フレームの再現が数秒で終わります**。
AI パイロットで自動走行させ、ゲート通過数・岩ヒット数・ランクを比較するのが有効です。

> ブラウザの `python -m http.server` は 304 を返すため、変更確認時は
> `index.html?v=<timestamp>` のようにクエリを付けるか、-hard リロードしてください。

### DOM を含む画面のスクショ（headless Chrome）

`browser.screenshot` はデスクトップウィンドウが隠れていると使えません。
ただし **DOM オーバーレイ（タイトル画面・リザルト画面）は
headless Chrome で撮れます**。

```powershell
$chrome = "C:\Program Files\Google\Chrome\Application\chrome.exe"
$ud = "C:\Users\<user>\AppData\Local\Temp\chromeprofile"
& $chrome --headless=new --disable-gpu --no-first-run --no-default-browser-check `
  --disable-extensions --user-data-dir=$ud --hide-scrollbars `
  --window-size=1440,900 --virtual-time-budget=4000 `
  --screenshot="C:\out\title.png" "http://localhost:8123/_preview_title.html"
```

**使い分け**

| 対象 | 方法 |
|---|---|
| 3D の描画（ゲーム画面） | `renderer.domElement` を canvas に写して POST する。`browser.evaluate` から Base64 を取り出して保存 |
| DOM オーバーレイ（タイトル・リザルト） | 上記の headless Chrome。ページは「style + overlay の outerHTML だけ」を並べた単体 HTML にする |

**单独 HTML を作る手順**（ブラウザで DOM を取り出して POST する）

```js
const style = Array.from(document.querySelectorAll('style')).map(s => s.textContent).join('\n');
const o = document.getElementById('title').outerHTML;   // hidden を外す
const html = '<!doctype html><meta charset="utf-8"><style>' + style + '</style>' + o;
await fetch('http://127.0.0.1:8124/preview_title.html', { method: 'POST', body: html });
```

`#title` の背景画像 `assets/title_hero.jpg` は相対パスなので、
単体 HTML では `http://localhost:8123/kayak3d/assets/title_hero.jpg` に書き換えます。

**注意**：headless Chrome は URL をキャッシュする。
`?v=<時刻>` を付けて撮ってください。

## 7. VRM アバター

URL に `?vrm=<ファイル名>` を付けるとアバターが使われます。
ファイルは `assets/Model/` に入れています。

- タイトル画面の **AVATAR** 行でモデルを切り替えられます
  （`V` キーで次へ、`Shift+V` で前へ）
- **ファイルを直接読み込む**こともできます（`ファイル...` ボタン）
- 前回選んだモデルを `localStorage` に記憶し、起動時に自動で読み込みます

### 言語の切り替え（日本語 / English）

タイトル画面とリザルト画面の台上に「日本語 / EN」のボタンがあり、
選んだ言語は `localStorage` に保存され、次回開いてもその言語で始まる。

**言語の切り替えの実装（二つの方式）**

- 静的な文詞（HTML 内）は `data-en` 属性で切り替える
  - `applyLang()` は第一回だけ元の日本語（`data-ja`）を保存し、以降は `innerHTML` を換える
  - 例：`<span data-en="Paddle left">左へ漶ぐ</span>`
- JS で作る文詞（難易度の説明・結果画面・ポップアップ）は `tr(ja, en)` で分かる

**`tr()` という名前の理由**

`updatePlay(dt, t)` の第 2 引数は経過時間（`t`）なので、ヘルパーを `t()` とすると
`updatePlay` の中では `t` が数値になってしまい、`TypeError: t is not a function` になる。
`tr()` にして避けている。

### 同届の有無（`VRM_BUNDLED`）

`index.html` の `VRM_BUNDLED` で「VRM を同届するか」を切り替える。

| 値 | 用途 | 持ち |
|---|---|---|
| `false`（既定） | 公開版（GitHub Pages） | ドロップダウンは「アバターなし（既定）」だけ。`V` キーは何も起きない |
| `true` | 自分の PC で遊ぶとき | `assets/Model/` の VRM を一覧に出し、`V` キーで切り替える |

**自動ロードは「同届するモデルに限定する」。**
公開版では `VRM_LIST` が空なので、`?vrm=` という URL パラメータも読み込みない。
それによって 404 が出らない。

VRM はライセンス（Proprietary）のためリポジトリには含めない。

### 自動で調整される項目

| 項目 | 内容 |
|---|---|
| 縮尺 | 「腰から肩までの長さ」が櫂の高さに合うように求めます。モデルごとに違います。さらに `VRM_SIZE`（1.3）を掛けます |
| 座り位置 | 深さ 0.39m。コクピットの中心にアバターの腰を合わせます |
| 握り間隔 | 肩から握り点までが腕の届く長さを超えると、間隔を自動で縮めます（下限 0.14m） |
| 腰の処理 | 腰より下はクリッピング平面で落とします。落ちた部分は見えません |
| 手首 | 櫂を横切る軸を櫂シャフトに合わせ、掌の法線は「艇のローカル下方向」を櫂軸に直交させて決めます（下記） |
| 指 | 櫂に巻き込みます（巻き量は固定です） |
| 上体の傾け | 首と胸の骨を 0.6 : 0.4 に分けて傾けます。腰は傾けません（⑧ 参照） |
| 一人称カメラ | 高さをモデルの頭に合わせて `VRM.povEyeY`（頭骨 + 0.24）にします |

これらはモデルごとに自動で調整されます。

### 手の握り方（`aimHand`）

手の向きと手の位置は、**櫂軸だけではなく櫂軸によって決める**。

#### 1. 掌の法線（手の向き）

櫂軸は **櫂軸の向きだけ**で決める。

```js
// 掌の法線 = 艇のローカル「上」方向を、櫂軸に直交する成分に落としたもの
const P = _ik.e2.copy(_ik.e3);              // _ik.e3 = 艇のローカル上方向（world）
P.addScaledVector(S, -P.dot(S));
```

**前臂（foreDir）を使うと左右で握り方が反転する。**
`シャフト × 前臂` で掌の法線を作ると、前臂の向きが左右で逆なるため符号が反転し、
另、符号を「今の手の向きに近い方」で選ぶと**漖い側だけで手の向きが途中で回ってしまい**。

櫂軸だけで決めると、

- 左右の手の握り方が完全に一致する（実測: 全 6 モデルで左右の差 = 0）
- 掌が櫂軸を持って、櫂軸は其の下にきる（パドラーは「上から握る」握り方）

#### 2. 手の位置（握り点）

IK は**手首（手腐）を目標に置く**。そのままでは
櫂軸が手首の位置に当たり、「手の甲の上に櫂軸がある」状態になる。

```js
// 目標点 = 握り点 - 手の長さ × 指方向 × GRIP_FWD  +  櫂軸の上方向 × GRIP_UP
```

`GRIP_UP` は手を櫂軸より上に持ち上げる量（掌が櫂軸を受ける高さ）、
`GRIP_FWD` は手首を櫂軸から離す割合（手の長さに対して）。

実測（全 6 モデル）: 手の上方向成分 = +0.03m（手は櫂軸より上）、
左右の差 = 0。

**指方向は「櫂軸方向 × 掌の法線」から求める。**
手の現在の向きから求めると、IK と `aimHand` の間で手の向きが入れ替わるため、
毎フレームでの方向がブれて手首の位置が不安定になる。
軸の位置（櫂軸の軸の上に込む軸方向）から求める。
### VRM の大きさ（`VRM_SIZE`）

VRM は頭身大のデフォルメ体型なので、艇（幅 0.66m）に対して小さく見えました。
実物のカヤッカーが船に占める存在感に近づけるため、**`VRM_SIZE = 1.3`** 倍してあります。

| モデル | 縮尺（従来） | 縮尺（1.3 倍） | 肩幅 | need/reach |
|---|---:|---:|---:|---:|
| Grus | 0.828 | 1.077 | 0.237 | 0.697 |
| mollymolly | 0.723 | 0.940 | 0.274 | 0.892 |
| MyAvatartest | 0.771 | 1.002 | 0.242 | 0.725 |
| vketdevil | 0.816 | 1.060 | 0.253 | 0.714 |
| Xbase | 0.692 | 0.899 | 0.270 | 0.815 |
| Marycia | 1.112 | 1.446 | 0.259 | 0.712 |

**拡大しても壊れない理由**

- `need/reach`（腕の届く余裕）はむしろ**改善**する（0.85 → 0.70 前後）。
  肩が櫂より上へ上がるぶん、腕の伸び切る前の余力が増える
- 副作用として **grip の自動縮小が止まる**。
  従来は 0.82 を超えて握り間隔が 0.32 → 0.29 まで詰められていたが、
  拡大後は 0.32 のまま保たれ、手が櫂から外れなくなる
- 腰は `hipY` で固定なので、座っている感じは保たれる

**一人称（POV）のカメラ高さ**

POV カメラは艇の固定位置（y=1.30）に置かれるので、頭が大きいモデルだと
**頭が視界を塞いでしまう**（Marycia が該当）。
そこで `VRM.povEyeY = 頭骨の位置 + 0.24` をモデルごとに設定し、
カメラを頭より少し上に出しています（実測 1.308〜1.338）。

**上体の傾け**は、`?lean=0` を付けると無効になります（有効／無効の比較用）。

傾けの実測値（Grus、1 ストローク中）:

| 項目 | 値 |
|---|---|
| 胸の捻り（Y） | -5.5° 〜 +1.3° |
| 胸の傾き（Z） | -4.6° 〜 +0.1° |
| 頭（首の子の位置）の変化 | 艇に対して最大 22mm |
| 髪の「頭に対する相対運動」の平均 | 84mm（傾けなし）→ 99mm（傾けあり） |

つまり傾けは **約 18% ほど髪の揺れを増やしている**ものであり、
傾き自体はごく小さい（数度）で、破綻しない範囲に収まっています。

---

## 8. 既知の制約

- **オフライン不可**（three.js が CDN）
- **静的配信のみ**（サーバーサイド処理なし、セーブなし）
- モバイルは**タッチ対応**だが、performance に要確認（描画数が多い）
- Chrome / Edge / Firefox で確認。Safari は importmap と WebGL2 の挙動が未確認