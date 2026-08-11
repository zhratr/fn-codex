# fnOS FPK packaging notes

The package is a native fnOS service package. It does not use Docker. The corrected release publishes an x86_64 FPK for the confirmed NAS target and an ARM64 FPK from the same source tree.

## Evidence and contract

The implementation follows the current fnOS developer entry points:

- [fnpack CLI documentation](https://developer.fnnas.com/docs/cli/fnpack/)
- [Create an fnOS application](https://developer.fnnas.com/docs/quick-started/create-application)
- [fnOS Apps community packaging reference](https://github.com/conversun/fnos-apps), which documents manual installation from a Release `.fpk`, a common `manifest`/`app.tgz`/`cmd`/`config`/`wizard` layout, and multi-architecture release assets.

The repository keeps a complete fnpack-style package source in `fpk/`, including `app/server`, `app/ui`, UI icons, lifecycle scripts, manifest, and config. On a development machine with the fnOS packager installed, run:

```sh
fnpack build --directory fpk
```

The fallback `scripts/build-fpk.sh` builds a compressed `.fpk` with the same top-level layout and bundles a matching official Node runtime. It is useful for CI and local inspection; it does not replace `fnpack` validation or a real fnOS install test.

## Architecture

```sh
PLATFORM=x86_64 VERSION=0.1.6 SKIP_RUNTIME=1 bash scripts/build-fpk.sh
PLATFORM=arm64 VERSION=0.1.6 SKIP_RUNTIME=1 bash scripts/build-fpk.sh
bash scripts/validate-fpk-package.sh dist/fn-codex-0.1.6-x86_64.fpk
```

`PLATFORM=x86_64` is the first-install priority for the target NAS. The release workflow builds both assets. Runtime binaries are architecture-specific; the JavaScript application and UI are shared.

The fnOS manifest uses `platform="x86"` for the x86_64 package and `platform="arm"` for the ARM64 package; the separate `arch` field records the exact runtime architecture.

The package-shape command above intentionally omits the runtime for fast local inspection. The builder downloads the official fnpack 1.2.3 tool and GitHub Actions adds the matching official Linux Node runtime, then runs the same archive validator with `REQUIRE_RUNTIME=1`.

## Lifecycle and defaults

- `cmd/main` starts and stops the service as the fnOS package user.
- The default bind is `127.0.0.1:3010`.
- The default workspace is the app's persistent home directory under `workspace/`.
- File paths are resolved beneath that workspace; `..`, absolute paths, and symlink escapes are rejected.
- Commands are disabled by default and, when explicitly enabled, use a small non-shell allowlist.
- `CODEX_API_URL`, `CODEX_API_KEY`, and `CODEX_MODEL` are environment-only configuration. No credential is shipped or written to task state.

The package has not been installed on fnOS hardware in this development session. Treat the FPK as a release candidate until a user validates install, start/stop, browser reachability, workspace restriction, upgrade, and uninstall on the target NAS.
