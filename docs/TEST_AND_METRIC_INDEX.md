# 移动端测试与指标索引

本仓库是数字孪生 AI 港口双端系统的 Flutter 前台，不复制 Web 决策后端的训练产物或港口运行数据。

## 本仓库测试

- `bash scripts/check.sh`：Dart 格式、Flutter 静态分析和客户端测试；记录为 25 项客户端测试通过。
- `bash scripts/check_backend.sh`：独立 AIS 研究合同与 API 测试；记录为 19 项测试通过。
- `scripts/smoke_all_baselines.py`：PPO、SAC、TD3、DQN、LOS-PID 各执行 128 步接线测试。该结果只证明训练、保存和留出测试链路可运行，不证明算法收敛或港口收益。
- `scripts/release_check.sh`：串联上述检查，并验证时间隔离、公开数据哈希、失效安全回执和敏感信息扫描。

## 双端共享业务指标

泊位利用率、平均待泊时间和能源成本等系统级指标由 Web 决策后端统一计算，权威证据位于配套 `port-dt-multi` 仓库：

- `data/rl/business_kpi_benchmark_v1.json`
- `data/rl/business_kpi_benchmark_v1_daily.csv`
- `data/mobile/mobile_workflow_benchmark_v1.json`
- `docs/DUAL_FRONTEND_METRICS.md`

## 双端共享算法与公开数据

移动端通过共享后端 `/api/rl/engine/capabilities` 与
`/api/rl/benchmarks/summary?dataset_id=public_us_la_6min_v1` 核验：

- 核心兼容集合：SAC、PPO、TD3、DQN、A2C、TQC、MPC；当前 V3.2 完整能力另含 QR-DQN、TRPO、Recurrent PPO、ARS、FCFS；
- `port_ops_v2` 的37维观测、5维建议动作与12类因素可用性掩码；
- 87,459个六分钟时步、262,347条独立公共原始观测、69,967/17,492时序划分；
- 18组多种子正式RL训练证据与1组MPC控制基线证据。

移动端小懿还会调用 `/api/rl/integration/health`、
`/api/assistant/actions/execute` 与 `/api/mobile/audit/verify`，只有身份、路由、
dry-run 回执和审计链同时通过时才显示“Web 共享链路已核验”。

权威训练产物、数据 manifest、质量报告和来源登记位于配套
`port-dt-multi` 仓库；移动仓库只消费并失效关闭校验，不复制或改写证据。

移动端只消费候选策略、人工审批、执行回执与审计事件，不单独宣称一份重复的调度收益。首次克隆未连接 Web 后端时，界面显示“等待接入港口”或“公开历史回放”，不会生成本地告警、现场曲线或成功执行回执。
