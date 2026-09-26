# 月面详情参考图

核实日期：2026-09-26。22 张 JPEG 共 1,650,450 字节，全部离线使用。原始 TIFF 共 114,852,254 字节，只保存在开发缓存，不进入 Git 或 App Bundle。

## 来源与使用依据

- [NASA SVS CGI Moon Kit](https://svs.gsfc.nasa.gov/4720/) 的 2019 版 8192×4096 月面纹理。署名 `NASA’s Scientific Visualization Studio`，源数据 NASA / GSFC / ASU。[SVS FAQ](https://svs.gsfc.nasa.gov/help/#faq) 说明未另行标注的内容属于公共领域，可下载、使用和再分发。页面没有针对该纹理的例外。
- [NASA PDS WAC 正面拼图](https://data.lroc.im-ldi.com/lroc/view_rdr_product/WAC_GLOBAL_O000N0000_064P)，7334×7334，473.80235037734 m/px。用于第谷、哥白尼、柏拉图、亚平宁山脉和阿尔卑斯山脉。
- [NASA PDS 开普勒 E 版](https://data.lroc.im-ldi.com/lroc/view_rdr_product/NAC_ROI_KEPLER__LOE_E081N3220_20M)，1779×2458，20 m/px。
- [NASA PDS 阿里斯塔克斯低太阳角拼图](https://data.lroc.im-ldi.com/lroc/view_rdr_product/NAC_ROI_ARISTARCLOA_E238N3125_20M)，2541×2352，20 m/px。

PDS 图署名 `NASA / GSFC / ASU`。[LROC 条款](https://lroc.im-ldi.com/about/terms) 明确 PDS 数据产品属于公共领域，同时把网站精选图等商业使用另行区分。本次文件全部从 PDS 归档下载，重定向目的地为 NASA PDS。它们不是 CC0 授权图片，不将“公共领域”误标为 CC0。不使用 NASA 标志、不暗示 NASA 为产品背书，遵循 [NASA 媒体使用指南](https://www.nasa.gov/nasa-brand-center/images-and-media/)。

## 坐标与处理

`reference-image-plan.json` 提供下载直链、原图精确字节数、SHA-256 和每个地形的源图选择。地形坐标使用 `features.json` 的 IAU / USGS 中心点，东经为正。

SVS 图的横轴经度为 -180° 至 180°，纵轴为 90°N 至 90°S。WAC 为中心在 0°N、0°E 的正射投影，月球半径 1737.4 km，零基像素投影原点 `(3666.5, 3666.5)`，无旋转。开发阶段将这两种源图反采样为局部等距方位图，局部北向上。

NAC 图为北向上的等距圆柱投影。开普勒 E 版按 `(x: 21, y: 448, width: 1600, height: 1600)` 裁切，覆盖整个坑体；阿里斯塔克斯各边内裁 60 像素，去除外围无数据区。所有采样均来自真实源图，JPEG 编码质量为 ImageIO 0.60，不填补数据、不生成细节。大多数图片 768×512，开普勒 640×640，阿里斯塔克斯 640×590。

8K 全球纹理适合月海形态，29 km 的开普勒在其上仅约 22 像素，因此细小环形山另用 NAC。第谷等 WAC 局部图用于展示坑体，不包含其全部长距离辐射纹。NASA SVS 纹理本身为视觉展示进行过曝光、白平衡和极区缺口处理，详情图不能用于科学测量。App 原有 2K 纹理继续用于配准，新增图片不参与匹配。

科普事实逐条来源见 `content/research.json`，英文基稿为 `content/en.json`。每处地形分别介绍命名来历、独特知识和照片辨认线索。原文网页的插图许可不自动适用于本项目，未从科普来源页复制图片。
