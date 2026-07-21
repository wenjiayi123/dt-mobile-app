# Contributing / 参与贡献

感谢你帮助改进 PortAI DT Mobile。我们欢迎小而可复核的 Issue 与 Pull Request，尤其是数据契约、移动可用性、实验可复现性、无障碍、安全边界和测试方面的贡献。

Thank you for improving PortAI DT Mobile. Small, reviewable issues and pull requests are welcome, especially around data contracts, mobile usability, reproducible experiments, accessibility, safety boundaries, and testing.

## Before opening a change / 提交前

1. Do not commit port credentials, restricted data, vessel identity fields, `.env`, generated models, audit logs, or workstation paths.
2. Every new dataset must include a manifest, field mapping, provenance, licence/use limitations, de-identification statement, and SHA-256.
3. Never describe replay, sandbox, derived metrics, or smoke results as live production evidence or convergence proof.
4. Keep the five-baseline contract (`PPO`, `SAC`, `TD3`, `DQN`, `LOS-PID`) unless a versioned design discussion explicitly changes it.
5. UI changes must not introduce fake progress, local fallback alerts, fabricated execution receipts, or unlabeled precomputed trajectories.

请勿提交凭证、受限数据、船舶身份字段、生成模型和本机路径。新数据源必须提供来源、许可、字段映射、去标识声明和哈希；回放、沙箱、派生指标与冒烟结果必须保持明确标签。

## Development gate / 开发门禁

```bash
bash scripts/check.sh
bash scripts/check_backend.sh
python scripts/smoke_all_baselines.py --timesteps 128
```

Algorithm changes should report the dataset hash, experiment hash, seed, budget, environment contract, independent test metrics, and comparison boundary. Visible workflow changes should include a screenshot or short recording.

算法变更应同时提交数据哈希、实验哈希、随机种子、训练预算、环境合同、独立测试指标与对照边界；可见工作流变更应附截图或短录屏。

## Review expectations / 评审要求

- Keep unrelated refactors out of the pull request.
- Explain data, model, audit, authentication, and execution-gate impact.
- Add or update tests for behavioral changes.
- Disclose generated or third-party material and confirm redistribution rights.
- Use Conventional Commit-style messages when practical.

长期兼容性、奖励定义、数据字段、审批/执行边界和许可证变更需要维护者明确批准，并在 PR 或架构决策记录中说明迁移与回滚方案。

Please follow [GOVERNANCE.md](GOVERNANCE.md), [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md), and [SECURITY.md](SECURITY.md).
