# 强化学习方法与证据边界

## 共享双端算法合同

移动端默认连接 `port-dt-multi`，要求核心 SAC、PPO、TD3、DQN、A2C、TQC
和 MPC 全部存在；当前 V3.2 能力清单另登记 QR-DQN、TRPO、Recurrent PPO、
ARS 与 FCFS。算法环境支持 `port_ops_v2/v3`：37维观测、5维建议动作、12类现实因素
及逐因素可用性掩码。BTS 与 NOAA 洛杉矶港 2021 公开基准包含 87,459 个
六分钟时步与 262,347 条独立公共原始观测，按 69,967/17,492 时序划分。

六种 RL 各完成 3 个随机种子 × 10,000 步正式无渲染训练，并在 10 个
确定性留出窗口评测；MPC 按相同窗口独立登记。正式产物由共享后端持有，
移动仓库不复制模型或训练数据。

## 独立 AIS 实验室五方法

| ID | 类型 | 实现 | 动作空间 |
| --- | --- | --- | --- |
| `ppo` | RL | Stable-Baselines3 PPO | 连续二维 |
| `sac` | RL | Stable-Baselines3 SAC | 连续二维 |
| `td3` | RL | Stable-Baselines3 TD3 | 连续二维 |
| `dqn` | RL | Stable-Baselines3 DQN | 9 个离散二维组合 |
| `los_pid` | 控制理论 | 本仓库 LOS-PID；5/15/30 组训练集增益网格试验 | 连续二维 |

上表只描述本仓库 `backend/portai_rl` 的兼容研究实验室，不是共享双端动态方法
合同。动作表示交通流建议和容量分配建议。公开 AIS 只有观测，没有干预后的
反事实标签，因此环境使用 manifest 中显式声明的沙箱响应系数。训练是真实的
策略优化，但效果只对该沙箱实验合同成立。

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
