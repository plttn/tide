# Agents

All agent-driven work must be opened as pull requests against `plttn/tide`.

Do not open pull requests against `IlanCosman/tide` (upstream) for work done in this fork.

For testing, use `mise` rather than `make`.

Every commit must follow [Conventional Commits](https://www.conventionalcommits.org/)
(e.g. `fix: ...`, `feat: ...`) — see `CONTRIBUTING.md`. PRs merge via a real
merge commit, not squash, so release-please reads each commit on `main`
directly to generate the changelog; the PR title itself has no format
requirement.
