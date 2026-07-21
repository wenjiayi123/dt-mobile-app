# Project Governance / 项目治理

PortAI DT Mobile currently uses maintainer review. Pull requests should state the problem, the smallest proposed change, evidence, test results, provenance impact, and rollback path.

本项目当前采用维护者评审制。Pull Request 应说明问题、最小变更、验证证据、测试结果、数据来源影响和回滚路径。

Maintainer approval is required for changes to canonical data fields, split logic, reward or environment definitions, algorithm registration, artifact schemas, authentication, audit semantics, approval separation, production dispatch, licences, and release workflows.

以下变更必须获得维护者明确批准：规范数据字段、时间切分、奖励或环境定义、算法注册、产物格式、身份认证、审计语义、异人审批、生产下发、许可证和发布工作流。

Long-term compatibility decisions should be recorded in a pull request or an architecture decision document. Releases use semantic version tags and include limitations, migration notes, data/model provenance, and verification results. Security reports follow [SECURITY.md](SECURITY.md); conduct follows [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

The maintainer may reject changes that inflate capability claims, weaken fail-closed behavior, obscure provenance, or add unreviewable generated assets even when the code runs.
