# 数据集契约：port_traffic_timeseries_v1

每个港口数据集由一个 CSV 和一个 JSON manifest 组成。训练代码只依赖该合同，不硬编码港口名称。

## CSV 必需列

| 列 | 单位/范围 | 说明 |
| --- | --- | --- |
| `timestamp` | ISO-8601 UTC | 必须严格递增，先排序并去重 |
| `vessel_count` | 非负计数 | 时间桶内船舶数或等价交通参与者数 |
| `mean_sog_knots` | knots | 平均对地航速 |
| `stopped_ratio` | 0..1 | 低速/停止观测比例 |
| `course_dispersion` | 0..1 | 航向离散度 |
| `traffic_density` | 0..1 | 经数据提供者定义并记录的归一化密度 |
| `position_spread_km` | km | 位置二维离散度 |

至少需要 30 个时间点。加载器拒绝缺列、非有限值、非递增时间和 SHA-256 不匹配。

## manifest 必需内容

参考 [`backend/config/public_noaa_ais.json`](../backend/config/public_noaa_ais.json)：

- `schema_version` 固定为 `port_traffic_timeseries_v1`。
- `dataset_id` 在组织内唯一。
- `data_file` 相对于 manifest。
- `data_sha256` 是 CSV 的 SHA-256。
- `source` 记录提供者、直接下载地址、条款、原始文件哈希、空间和时间范围。
- `field_mapping` 解释每个目标列如何从源字段得到。
- `split.method` 必须为时间顺序语义；默认 70/15/15。
- `environment` 记录动作响应系数及其校准状态。
- `reward` 记录奖励权重。

数据哈希、环境参数、奖励权重或 schema 变化都会改变 `experiment_sha256`。检查点同时绑定数据和实验哈希，合同变化后旧检查点不能继续测试。

## 港口适配步骤

1. 在独立导入脚本中读取现场或公开源，保留原始来源证据。
2. 显式映射字段和单位，处理时区、缺失、异常值、重复和采样频率。
3. 按时间生成 CSV，计算哈希并写 manifest；不要随机打乱时序数据。
4. 用 `/api/data/status` 核对范围和三段划分。
5. 用训练集校准环境和算法；当前实现保留但不读取验证集，未来如做模型/超参数选择必须显式记录；测试集只用于最终报告与回放。
6. 现场投产前，用真实干预结果重新估计 `environment` 动作响应系数，并完成安全验收。

只有“换 CSV”能复用软件管线；它不能自动证明新港口的控制模型、奖励或约束有效。
