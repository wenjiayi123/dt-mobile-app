# 测试说明

## Flutter

```bash
bash scripts/check.sh
```

依次执行格式化校验、静态分析和所有 Flutter 测试。Situation 测试使用缓存或 provider fake，不依赖在线服务。

## Python

```bash
python3 -m venv .venv
.venv/bin/pip install -r backend/requirements.txt
bash scripts/check_backend.sh
```

独立 AIS 实验室 Python 测试覆盖：schema/hash/时间划分、train-only 标准化、训练期禁止渲染、test-only 轨迹、五方法合同、重规划产物门禁、客户端审阅参数边界、API key、异人审批、路径穿越防护、HTML 转义、fail-closed 和审计哈希链。

## 独立 AIS 实验室五方法冒烟

```bash
.venv/bin/python scripts/smoke_all_baselines.py --timesteps 128
```

预期每个算法都返回 `TRAINED` 和 `COMPLETED`，并产生非空测试轨迹。它不属于收敛测试。

## 完整项目检查

```bash
PORTAI_PYTHON=.venv/bin/python bash scripts/release_check.sh
```

检查数据哈希、Python 编译与测试、Flutter 质量、独立 AIS 五方法 128-step 接线、训练渲染隔离、资产来源和高风险 fake 标记。
