# 月面识别

App 路径为「相册 → 照片详情 → 探索月面」。原生照片展开到全屏、放大月亮，再逐个显示可点击地名；参考月面与微调按需开启。UIKit 负责转场、缩放、动态引线与详情，后台 JavaScriptCore 负责离线配准，没有网页、预览服务或照片上传。

## 构建与资源

Xcode 当前引用相邻目录的 `../SkyKit`，需要其中增强后的 `Moon.surface` API。远端 1.0.0 不包含此 API；发布新版本后再将项目改回固定的远端依赖。

运行资源位于 `moontake/Moon/MoonAtlasResources`：识别核心、2K 月面纹理、22 处地形的坐标和来源、22 张科普参考图。原始高清 TIFF、维护资料和测试样例不进入 App。

科普以 [英文基稿](../tools/moon-atlas/content/en.json) 为基准，包含命名来历、独特故事、照片辨认线索，再翻译为其余 13 种语言。修改流程见 [内容说明](../tools/moon-atlas/content/README.md)。从仓库根目录同步或校验：

```sh
python3 tools/moon-atlas/sync-content.py
python3 tools/moon-atlas/sync-content.py --check
```

图源、公共领域依据和裁切参数见 [图片来源说明](../tools/moon-atlas/reference-images.md) 与 [处理计划](../tools/moon-atlas/reference-image-plan.json)。重建图片：

```sh
python3 tools/moon-atlas/fetch-reference-sources.py /tmp/moontake-reference-sources
swiftc -O tools/moon-atlas/build-reference-images.swift -o /tmp/moon-references
/tmp/moon-references /tmp/moontake-reference-sources \
  moontake/Moon/MoonAtlasResources/assets/features.json \
  tools/moon-atlas/reference-image-plan.json \
  moontake/Moon/MoonAtlasResources/assets/details
```

## 识别和验证

照片按 EXIF 方向解码，最长边缩至 1600 像素。拍摄日期优先读取 EXIF 日期与时区，缺失时回退到 App 保存时间。照片已有经纬度时使用观测点，否则采用地心近似。SkyKit 计算姿态和受光方向，配准同时比较月海的大轮廓与细纹理；白天候选定位可先扣除局部天空背景，匹配仍使用原图像素。

标注是根据配准结果投影的近似地名中心，不是逐个地形分割。显示条件排除背面、暗面和在分析图上过小的环形山、山脉。引线在当前视口中动态分配位置，并以最小总长度匹配避免交叉。

```sh
python3 tests/moon-atlas/prepare-fixtures.py  # 需要 Pillow
node --test tests/moon-atlas/registration.test.mjs
xcodebuild -project moontake.xcodeproj -scheme moontake \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  -only-testing:moontakeTests/MoonAtlasTests test
```

[测试说明](../tests/moon-atlas/README.md) 记录实拍样例来源及回归依据。21 项 Node 检查覆盖配准和拒绝条件；13 项原生测试另覆盖日期读取、转场、微调、动态标签、图文详情与多语言资源。评分不是概率，测试通过不代表已建立大规模实拍准确率。细月牙、遮云、散焦、严重过曝或很小的月轮仍可能失败，可使用手动对齐。

## 基础数据来源

- 识别纹理：NASA SVS [CGI Moon Kit](https://svs.gsfc.nasa.gov/4720/) 的 [2048 × 1024 月面纹理](https://svs.gsfc.nasa.gov/vis/a000000/a004700/a004720/lroc_color_2k.jpg)。
- 独立测试示例：NASA SVS [Moon Phase and Libration, 2026](https://svs.gsfc.nasa.gov/5587/) 的 [2026-01-01 00:00 UTC 渲染帧](https://svs.gsfc.nasa.gov/vis/a000000/a005500/a005587/frames/730x730_1x1_30p/moon.0001.jpg)。
- 地名：IAU / USGS [Gazetteer of Planetary Nomenclature](https://planetarynames.wr.usgs.gov/GIS_Downloads) 的 [月球中心点目录](https://asc-planetarynames-data.s3.us-west-2.amazonaws.com/MOON_nomenclature_center_pts.kmz)，经度统一为东正西负。科普逐项证据保存在 [research.json](../tools/moon-atlas/content/research.json)。
