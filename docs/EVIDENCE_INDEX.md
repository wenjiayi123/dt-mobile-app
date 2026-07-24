# 移动端开源证据索引

本仓库是数字孪生 AI 港口双端系统的 Flutter 前台，不复制 Web 决策后端的训练产物或港口运行数据。

## 本仓库可复现证据

- `bash scripts/check.sh`：Dart 格式、Flutter 静态分析和客户端测试；2026-07-24 固定发布快照为 22 项客户端测试通过。
- `bash scripts/check_backend.sh`：独立 AIS 研究合同与 API 测试；2026-07-24 固定发布快照为 19 项测试通过。
- `scripts/smoke_all_baselines.py`：PPO、SAC、TD3、DQN、LOS-PID 各执行 128 步接线测试。该结果只证明训练、保存和留出测试链路可运行，不证明算法收敛或港口收益。
- `scripts/release_check.sh`：串联上述检查，并验证时间隔离、公开数据哈希、失效安全回执、Git 发布边界和敏感信息扫描。

## 双端共享业务证据

泊位利用率、平均待泊时间和能源成本等系统级指标由 Web 决策后端统一计算，权威证据位于配套 `port-dt-multi` 仓库：

- `data/rl/business_kpi_benchmark_v1.json`
- `data/rl/business_kpi_benchmark_v1_daily.csv`
- `data/mobile/mobile_workflow_benchmark_v1.json`
- `docs/RESUME_CLAIMS_DUAL_FRONTEND.md`

移动端只消费候选策略、人工审批、执行回执与审计事件，不单独宣称一份重复的调度收益。首次克隆未连接 Web 后端时，界面显示“等待接入港口”或“公开历史回放”，不会生成本地告警、现场曲线或成功执行回执。
