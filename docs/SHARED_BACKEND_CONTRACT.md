# 双端系统共享后端契约

Flutter 默认连接 Web 工程 `port-dt-multi` 的 FastAPI 服务：

| 方法与路径 | 移动端用途 |
|---|---|
| `GET /api/mobile/status` | 核对共享后端身份、五算法、系统KPI与移动闭环证据 |
| `GET /api/mobile/situation` | 读取证据状态；默认公开回放，不冒充实时态势 |
| `GET /api/mobile/alerts` | 初始系统告警快照 |
| `WS /api/mobile/alerts/ws` | 告警与服务心跳 |
| `GET /api/mobile/strategy/candidates` | 固定业务候选及已登记留出测试模型 |
| `POST /api/mobile/strategy/decisions` | 人工表态；必须带 `Idempotency-Key` |
| `GET /api/mobile/strategy/decisions/{id}` | 服务端回执 |
| `POST /api/mobile/strategy/replan` | 登记人工重规划审阅 |
| `POST /api/mobile/audit/events` | 上传移动端审计摘要 |
| `GET /api/mobile/audit/verify` | 校验服务端 SHA-256 前向链 |

训练与评测仍使用共享后端 `/api/rl/*`。算法合同固定为 SAC、PPO、TD3、DQN
与 MPC；移动端只能提交训练申请，电脑端异人批准后才能创建任务。

移动决策接口固定 `production_dispatch=false`，只返回干跑或阻断回执。真实
南向执行必须单独经过 `/api/actuators/*` 的白名单、约束与双人确认。
客户端会再次校验 `accepted=true`、非空 `request_id`、
`execution_status=dry_run_recorded` 与 `production_dispatch=false`；字段缺失或
服务端意外返回执行态时，移动端 fail-closed，不把该响应展示为成功回执。

系统级业务 KPI 和移动闭环可靠性指标不得合并：前者是 2025 全年
8,760 个小时留出步的固定数字孪生结果，后者是 500 项本地确定性接口操作。
