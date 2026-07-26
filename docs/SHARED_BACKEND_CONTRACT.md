# 双端系统共享后端契约

Flutter 默认连接 Web 工程 `port-dt-multi` 的 FastAPI 服务：

| 方法与路径 | 移动端用途 |
|---|---|
| `GET /api/mobile/status` | 核对共享后端身份、七算法、系统KPI与移动闭环证据 |
| `GET /api/mobile/situation` | 读取证据状态；默认公开回放，不冒充实时态势 |
| `GET /api/mobile/alerts` | 初始系统告警快照 |
| `WS /api/mobile/alerts/ws` | 告警与服务心跳 |
| `GET /api/mobile/strategy/candidates` | 固定业务候选及已登记留出测试模型 |
| `POST /api/mobile/strategy/decisions` | 人工表态；必须带 `Idempotency-Key` |
| `GET /api/mobile/strategy/decisions/{id}` | 服务端回执 |
| `POST /api/mobile/strategy/replan` | 登记人工重规划审阅 |
| `POST /api/mobile/audit/events` | 上传移动端审计摘要 |
| `GET /api/mobile/audit/verify` | 校验服务端 SHA-256 前向链 |

训练与评测仍使用共享后端 `/api/rl/*`：

| 方法与路径 | 移动端用途 |
|---|---|
| `GET /api/rl/engine/capabilities` | 一次读取七算法、数据登记和环境空间合同 |
| `GET /api/rl/benchmarks/summary?dataset_id=...` | 核验多种子正式训练与MPC留出评测证据 |
| `GET /api/rl/train/baselines?dataset_id=...` | 三维推演前复核精确算法集合 |
| `POST /api/rl/train/requests` | 提交数据指纹和训练参数；不直接创建训练进程 |
| `GET /api/rl/train/requests/{id}` | 同步异人审批、训练和评测状态 |

共享算法合同固定为 SAC、PPO、TD3、DQN、A2C、TQC 与 MPC。首选公开基准
`public_us_la_6min_v1` 必须对应 `port_ops_v2`、37维观测、5维建议动作和
12类现实因素可用性掩码；移动端只能提交训练申请，电脑端异人批准后才能
创建任务。独立 AIS 实验室的 PPO/SAC/TD3/DQN/LOS-PID 五方法合同不属于
共享双端运行路径。

`RL_DATASET_ID` 默认取 `public_us_la_6min_v1`。接入另一个已登记港口场景时，
通过 `--dart-define=RL_DATASET_ID=<dataset_id>` 切换；客户端仍要求环境和
算法合同一致，并从后端动态显示数据标题、来源、边界、规模和端口配置。

移动决策接口固定 `production_dispatch=false`，只返回干跑或阻断回执。真实
南向执行必须单独经过 `/api/actuators/*` 的白名单、约束与双人确认。
客户端会再次校验 `accepted=true`、非空 `request_id`、
`execution_status=dry_run_recorded` 与 `production_dispatch=false`；字段缺失或
服务端意外返回执行态时，移动端 fail-closed，不把该响应展示为成功回执。

系统级业务 KPI 和移动闭环可靠性指标不得合并：前者是 2025 全年
8,760 个小时留出步的固定数字孪生结果，后者是 500 项本地确定性接口操作。
