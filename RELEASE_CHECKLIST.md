# Maintainer Checklist / 维护清单

- [ ] `pubspec.yaml`, changelog, citation metadata, tag, and release notes agree.
- [ ] Flutter format, analysis, 17 tests, and release Web build pass on a clean checkout.
- [ ] Python compile, 19 tests, dependency audit, and five-baseline 128-step smoke pass.
- [ ] Secret scan and tracked-file review find no credentials, `.env`, private paths, identity fields, generated models, audit logs, or production telemetry.
- [ ] Dataset source URLs, licence/use limitations, field mapping, de-identification statement, and SHA-256 are current.
- [ ] README screenshots match the tagged build and retain evidence labels.
- [ ] No `.dart_tool`, build output, local environment, IDE metadata, or backend artifact is tracked.
- [ ] Container build and `/health` are verified when Docker is available.
- [ ] Authentication, distinct approval, execution, and audit boundaries are unchanged or explicitly reviewed.
- [ ] Release notes distinguish public, historical, replayed, derived, sandbox, live, and production evidence.
- [ ] When public: enable branch protection, private vulnerability reporting, Discussions, and public-only security workflows.
