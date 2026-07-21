# 强化学习方法与证据边界

## 五个固定基线

| ID | 类型 | 实现 | 动作空间 |
| --- | --- | --- | --- |
| `ppo` | RL | Stable-Baselines3 PPO | 连续二维 |
| `sac` | RL | Stable-Baselines3 SAC | 连续二维 |
| `td3` | RL | Stable-Baselines3 TD3 | 连续二维 |
| `dqn` | RL | Stable-Baselines3 DQN | 9 个离散二维组合 |
| `los_pid` | 控制理论 | 本仓库 LOS-PID；5/15/30 组训练集增益网格试验 | 连续二维 |

动作表示交通流建议和容量分配建议。公开 AIS 只有观测，没有干预后的反事实标签，因此环境使用 manifest 中显式声明的沙箱响应系数。训练是真实的策略优化，但效果只对该沙箱实验合同成立。

## 数据隔离

- train：唯一允许训练、探索和 LOS-PID 增益校准的数据段；`render_mode=None`。
- validation：当前基线实现不读取，保留给未来显式的模型/超参数选择流程；不进入最终指标。
- test：训练结束后才加载；策略固定为 deterministic，记录轨迹供客户端渲染。
- 标准化均值/方差只使用 train 计算。

worker 顺序固定为：

```text
load train -> headless train -> checkpoint + hashes -> exit training
-> load test -> deterministic rollout -> record trajectory -> client render
```

训练环境若产生帧或调用 render 会使测试失败。测试轨迹包含真实数据时间戳、动作、奖励、吞吐、拥堵、冲突风险和安全余量。

## 指标解释

- `mean_reward`：manifest 奖励合同下的平均回合收益，不能跨不同合同直接比较。
- `mean_throughput`、`mean_congestion`、`mean_conflict_risk`：沙箱响应模型输出，不是现场测量效果。
- `mean_safety_margin=1-mean_conflict_risk`。
- 相对 LOS-PID 的 reward 差值只在相同数据哈希、实验哈希和测试段内有意义。

`128` 步 smoke 仅验证接线。发布性能结论前应固定种子集合、训练预算和超参数选择流程，运行多种子统计，报告置信区间，并保留完整 artifact。
