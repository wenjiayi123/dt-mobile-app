# 数据来源与使用限制

仓库内置文件：`backend/data/noaa_long_beach_2024_01_10_5min.csv`。

- 提供者：BOEM、NOAA Office for Coastal Management、U.S. Coast Guard。
- 数据集：MarineCadastre.gov Automatic Identification System（AIS）。
- 原始文件：`AIS_2024_01_10.zip`。
- 空间范围：WGS84 `[-118.35, 33.68, -118.05, 33.88]`，美国长滩港邻近水域。
- 处理：五分钟时间桶；输出船舶计数、航速、停止比例、航向离散、交通密度和位置离散。
- 隐私最小化：输出中不保留 MMSI 或其他船舶身份字段。
- 原始 ZIP SHA-256：`d450fdabbb21b02bd843028accfa8ad2af7d304d46223e71ee53422c32be90a9`。
- 派生 CSV SHA-256：`c98e4f9b5d0bf0df0e798a767ae30510cbfd6ae021916332fdddf65aa3cadcf4`。

官方目录、数据字典、FAQ/使用条款的直接链接都保存在 manifest。官方材料说明该数据源于 USCG NAIS、可公开使用，并提示其面向海岸与海洋规划；它不适用于监管或执法。美国政府材料通常不受美国版权保护，但在其他司法辖区可能存在不同权利。

本仓库的 MIT 代码许可证不改变源数据条款。使用者有责任核对其所在司法辖区、用途和最新官方条款。AIS 历史数据也不能替代港口 TOS、ECS、VTS、设备遥测或经过验证的实时网关。

可复现导入：

```bash
python scripts/import_noaa_ais.py \
  --input AIS_2024_01_10.zip \
  --output backend/data/noaa_long_beach_2024_01_10_5min.csv \
  --evidence-output backend/data/noaa_long_beach_2024_01_10_evidence.json \
  --min-lon -118.35 --min-lat 33.68 --max-lon -118.05 --max-lat 33.88
```
