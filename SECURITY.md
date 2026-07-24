# Security Policy / 安全策略

## Reporting / 漏洞报告

Do not disclose credentials, port topology, device addresses, non-public vessel tracks, production telemetry, or exploitable details in a public Issue. Use **Security → Report a vulnerability** after the repository becomes public. While it remains private, contact the repository owner through a private GitHub channel.

请勿在公开 Issue 中提交访问凭证、港口拓扑、设备地址、未公开船舶轨迹、生产遥测或可直接利用的细节。仓库公开后请使用 **Security → Report a vulnerability**；当前私有预览阶段请通过 GitHub 私密渠道联系仓库所有者。

Include the affected version, minimum safe reproduction, impact, prerequisites, and suggested mitigation. We aim to acknowledge credible reports within seven days; remediation and disclosure timing depend on severity and affected operators. Only the latest release is eligible for security fixes.

## Deployment baseline / 部署基线

- Use Python 3.12–3.14 and the pinned dependencies; audit the exact release lock before deployment.
- Set `PORTAI_APP_ENV=production`, a 32+ character `PORTAI_API_KEY`, and explicit non-wildcard CORS origins.
- Terminate TLS at a reviewed gateway and apply identity, role, rate, and network policies.
- Keep port, AIS, TOS, execution-adapter, and signing secrets in a secret manager.
- Separate training, evaluation, approval, audit, and production identities and storage.
- Retain dry-run and human approval until site-specific safety acceptance is complete.
- Scan imported datasets for privacy, licensing, malware, schema, and poisoning risks.
- Export the local audit chain to signed or WORM storage when stronger non-repudiation is required.

- 使用 Python 3.12–3.14 与固定依赖，并审计准确的发布锁定版本；
- 生产环境必须设置 32 字符以上 API 密钥和非通配 CORS；
- 在受审网关终止 TLS，并实施身份、角色、速率和网络策略；
- 隔离训练、评测、审批、审计和生产身份与存储；
- 现场验收前保持 dry-run 和人工审批；
- 对导入数据执行隐私、许可、恶意文件、字段和投毒风险检查。

The detailed threat and audit boundary is documented in [docs/SECURITY.md](docs/SECURITY.md). This software is not a certified autonomous port or vessel controller.
