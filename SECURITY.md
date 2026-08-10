# Security notes

fn-codex is a community project intended for a trusted local network or loopback use. It is not a security boundary around an untrusted user.

- The service binds to `127.0.0.1` by default. If you expose it on a LAN, put it behind fnOS access controls or a separately managed reverse proxy.
- File browsing and previews are confined to `FN_CODEX_WORKSPACE`; absolute paths, `..` traversal, and symlink escapes are rejected.
- Command execution is disabled by default in the FPK. When explicitly enabled, only a small set of non-shell commands is accepted and the process runs as the package user.
- Provider credentials are read from environment variables and are never written to task state or the repository.
- Do not put secrets in the configured workspace. Report suspected credential leaks privately before opening a public issue.
