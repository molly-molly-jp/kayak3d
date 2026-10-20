# アセットの作り方

画像 7 枚はすべて **ローカルで動かした Qwen-Image-2.1** で生成しています。
樹木は画像ではなく**コードで手続き生成**しています。

---

## 1. 画像素材の一覧

| ファイル | サイズ | 用途 | 生成方式 |
|---|---:|---|---|
| `title_hero.jpg` | 328 KB | タイトル画面の背景 | txt2img |
| `banner.png` | 720 KB | ゴールの FINISH 看板 | txt2img → PIL でトリミング |
| `banner_start.png` | 693 KB | スタート地点の看板 | `banner.png` を編集（画像編集） |
| `water_foam.jpg` | 364 KB | 水面の白波テクスチャ / 滝のカーテン | txt2img |
| `ground_detail.jpg` | 551 KB | 岸のディテール | txt2img |
| `foam.png` | 9.5 KB | パーティクル（泡） | txt2img → PIL でラジアルフェード |
| `splash.png` | 8.6 KB | パーティクル（飛沫） | txt2img → PIL でラジアルフェード |

---

## 2. 画像生成環境

**Unsloth Desktop / Studio** をローカルで起動し、`localhost:8888` の API を使いました。

| 項目 | 値 |
|---|---|
| モデル | `unsloth/Qwen-Image-2.1-Turbo-GGUF`（配布元: [unsloth/Qwen-Image-2.1-GGUF](https://huggingface.co/unsloth/Qwen-Image-2.1-GGUF)） |
| 実行場所 | ローカル（GPU） |
| ワークフロー | `txt2img` / `reference` / `edit` |

### 手順

1. Unsloth を起動し、モデルを読み込む
2. テキストから生成（`txt2img`）
3. 看板の反復や、(2) の一部は既存画像を基にした編集（`edit`）
4. 必要な場合は Pillow で後処理（alpha マスク・ブラー・トリミング）

### 生成後の後処理

パーティクルの 2 枚は、そのままでは長方形が見えて不自然で大きいため、
Pillow で**ラジアルフェード**を掛けました。

```python
# 疑似コード
img = Image.open(src).convert("RGBA")
mask = Image.new("L", img.size, 0)
ImageDraw.Draw(mask).ellipse(center, radius, fill=255)
mask = mask.filter(ImageFilter.GaussianBlur(radius))
img.putalpha(mask)
```

---

## 3. 樹木：画像ではない

樹木は画像アセットが **1 枚もありません**。`trees.module.js`（920 行）が
コードだけで生成します。

### ライブラリが持つもの

```js
const SPECIES = [
  { id: 'oak',    base: PRESETS.oak,    variants: 3, spacing: 9   },
  { id: 'willow', base: PRESETS.willow, variants: 2, spacing: 8   },
  { id: 'birch',  base: PRESETS.birch,  variants: 3, spacing: 4.5 },
  { id: 'fir',    base: PRESETS.fir,    variants: 3, spacing: 5   },
  { id: 'dead',   base: PRESETS.dead,   variants: 2, spacing: 6   },
  { id: 'shrub',  base: SHRUB,           variants: 3, spacing: 2.4 },
];
```

各種（`id` → `PRESETS`）は、幹と枝を `CylinderGeometry` の束として組み合わせ、
アルファテストした板（カード）の葉を数枚組み合わせただけのローポリ構造です。
一部は `leafTex`（`leafType`）で葉テクスチャを切り替えられます。

### ゲーム側での使い方

```js
const bins = { willow: [], momiji: [], oak: [], ichou: [],
               sugi: [], hinoki: [], fir: [], shrub: [] };

for (let i = 0; i < 2600; i++) {
  const out = 1.2 + Math.pow(R(), 1.7) * 52;   // 岸からの距離
  if (out < 6.5)  bins.willow.push(p);          // 水際
  else if (out < 13) bins.momiji.push(p);
  // ...
}
```

- **水際ほど密**になるよう、岸からの距離で Reject サンプリング
- **水辺は低く**して川を塞がない
- 固定 seed（`mulberry32(424242)`）なので**毎回まったく同じ森**になります

---

## 4. チェックリスト

画像を追加・差し替えるときは、これを確認してください。

- [ ] `assets/` に置けている（`assets/` 以外はコードが読みません）
- [ ] ファイル名が ASCII（小文字推奨）
- [ ] パーティクルなら**ラジアルフェード済み**のアルファ PNG
- [ ] 看板なら**背景が透過**されていること（「地図」になっている）
- [ ] タイトル用なら 16:9 で 1MB 前後以内（34MB の制限に余裕を持たせる）
- [ ] 読み込みに時間がかかる場合は `README.md` に

---

## 5. 著作について

- 生成画像は **Qwen-Image-2.1**（Alibaba / Apache-2.0 系のライセンス）に基づきます
- 商用利用・二次配布の前に、必ずモデルのライセンスを確認してください
- 樹木の形は既存のライブラリからではなく、手続き生成の結果です