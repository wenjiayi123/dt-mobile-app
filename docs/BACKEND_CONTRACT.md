# 独立 AIS 实验后端契约（可选参考）

> 双端系统默认使用 `port-dt-multi` 的 `/api/mobile/*` 共享契约，见
> [SHARED_BACKEND_CONTRACT.md](SHARED_BACKEND_CONTRACT.md)。本文件仅描述
> `backend/portai_rl` 的独立算法实验服务，不用于证明整套系统的
> 泊位 +7.45 个百分点 / 待泊 -16.94% / 成本 -11.80% 的系统业务指标。

默认地址为 `http://127.0.0.1:8000`。响应中的 `public_replay`、`historical_public_replay` 和 `live_data_verified=false` 都是强制证据标签，不应被客户端改写为“实时”。

## 数据与健康

- `GET /health`：服务、数据集与生产门禁状态。
- `GET /api/data/status`：schema、数据/实验哈希、来源、字段和 train/validation/test 时间范围。
- `GET /api/situation/current`：由当前数据集最后一个测试时间点派生的摘要。公开回放返回 `riskEvidence=derived_point_from_historical_ais`、`riskHorizonMinutes=0`，低/高值相等；客户端不得把它写成未来预测或置信区间。
- `GET /api/alerts`、`WS /ws/alerts`：由历史 AIS 测试段派生的标记告警；断线时客户端不得生成业务告警。

## 五算法训练

- `GET /api/rl/train/baselines`
  - 必须返回 `contract=four_rl_plus_one_control`、`count=5`。
  - 算法必须为 `ppo`、`sac`、`td3`、`dqn`、`los_pid`。
- `POST /api/rl/train/requests`
  - body 包含 `config.algorithm`、`config.total_steps` 和客户端看到的 `config.dataset_sha256`。
  - 数据哈希不一致返回 409；算法或步数非法返回 422。
- `POST /api/rl/train/requests/{request_id}/approve`
  - 人工批准后启动独立 worker；训练阶段固定 `dataset_split=train`、`render=false`。
- `POST /api/rl/train/requests/{request_id}/reject`
- `GET /api/rl/train/requests/{request_id}`
- `GET /api/rl/train/status?job_id=...`
  - `RUNNING` 的 `step`、`episodes_completed`、`reward`、`step_rate_per_second` 和 `history` 来自训练器回调。
  - `EVALUATING` 才允许 `render=true`，且必须为 `dataset_split=test`。
- `GET /api/rl/artifacts/{job_id}/replay`
  - 只在测试完成后返回 `portai_policy_test_rollout_v1`。
- `POST /api/rl/future/run`
  - 读取最近一个已完成 job 的测试轨迹；无产物返回 409，不提供本地 fallback。

## 策略与审计

- `GET /api/strategy/candidates`：只从已完成测试产物构建候选；没有产物则 `items=[]`。`congestionIndex`、`conflictRisk`、`safetyMargin` 与 `rewardDelta` 都是测试聚合点值，不伪造成置信区间；`rewardDelta` 仅与同合同 LOS-PID 比较。
- `POST /api/strategy/replan`：只有当前数据哈希存在完成的 test 产物时才登记人工审阅申请；不生产下发。
- `POST /api/strategy/adopt_and_label`：记录人工表态。公开回放固定返回 `dry_run_recorded`；只有验证过的执行适配器真实确认才返回 `acked`。
- `POST /api/control/config`：验证并持久化客户端审阅参数，固定 `scope=client_advisory_view`、`production_applied=false`。
- `POST /api/audit/events`：追加服务器审计事件；服务器增加 `serverTime`、`serverEventId` 和哈希链字段。

生产执行由以下四个条件共同控制：live 模式、实时数据已验证、执行适配器已验证、执行适配器 URL 已配置。适配器没有实际 2xx 回执时接口返回 502，不伪造已提交或已执行状态。

## 数据交换最小字段

训练请求：

```json
{
  "source": "dt_mobile_app",
  "requested_by": "mobile_operator",
  "config": {
    "algorithm": "ppo",
    "total_steps": 20000,
    "dataset_sha256": "..."
  }
}
```

完成状态必须至少包含：

```json
{
  "status": "COMPLETED",
  "algorithm": "ppo",
  "dataset_split": "test",
  "render_ready": true,
  "dataset_sha256": "...",
  "aggregate_metrics": {
    "mean_reward": 0.0,
    "mean_throughput": 0.0,
    "mean_congestion": 0.0,
    "mean_conflict_risk": 0.0,
    "mean_safety_margin": 0.0
  }
}
```
