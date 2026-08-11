# Security notes

fn-codex is a community project intended only for a trusted local network. It is not a security boundary around an untrusted user.

- The service binds to `0.0.0.0:3010` by default, making it reachable from the NAS LAN. It has no built-in authentication or authorization. Do not expose this port to the Internet; use fnOS firewall/access controls and an authenticated reverse proxy if untrusted devices can reach it.
- File browsing and previews are confined to `FN_CODEX_WORKSPACE`; absolute paths, `..` traversal, and symlink escapes are rejected.
- Command execution is disabled by default in the FPK. When explicitly enabled, only a small set of non-shell commands is accepted and the process runs as the package user.
- Provider credentials are read from environment variables and are never written to task state or the repository.
- Do not put secrets in the configured workspace. Report suspected credential leaks privately before opening a public issue.
