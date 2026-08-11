# fn-codex

`fn-codex` is a community-built, browser-first coding-agent workspace packaged as a native fnOS FPK. It brings together a task sidebar, chat, selected workspace/file browsing, terminal output, and change preview for a NAS-hosted development workflow.

> This is an independent community implementation. It is not an official OpenAI desktop application, does not include OpenAI proprietary assets, and does not imply OpenAI endorsement.

## What is in the first release

- Dark desktop-style browser workspace with recent tasks and keyboard-friendly controls.
- Workspace-scoped file listing and text preview.
- Local task history persisted under the fnOS app data directory.
- Optional OpenAI-compatible agent provider through environment configuration; no credentials in source or package.
- Local change preview from `git diff` when the configured workspace is a Git checkout.
- Explicitly disabled command execution by default, with a small non-shell allowlist when enabled.
- Native FPK release assets for the confirmed x86_64 NAS target and ARM64 fnOS targets.

## Install from GitHub Release

1. Download `fn-codex-<version>-x86_64.fpk` for an x86_64 NAS, or the ARM64 asset for an ARM64 NAS.
2. In fnOS, open App Center → Manual install and upload the `.fpk` file.
3. Start the app, then open its fnOS app entry or `http://<NAS-LAN-IP>:3010/` from a trusted LAN. The default service listens on all NAS interfaces at port 3010.

The package has been tested to install and start on one Harn-MEmini / Intel N150 / fnOS 1.2.0401 target. LAN reachability of each new release still requires target-NAS verification.

## Configure an agent provider

Set these values in the fnOS service environment or the package's supported configuration surface; never commit them:

```sh
CODEX_API_URL=https://your-openai-compatible-endpoint.example
CODEX_API_KEY=provided-at-runtime
CODEX_MODEL=your-model-name
```

Without a provider, the UI remains usable as a local workspace preview and clearly reports that agent connectivity is not configured.

## Security defaults

The service binds to `0.0.0.0:3010` by default so it is reachable on the LAN. It currently has no built-in authentication. Keep it on a trusted LAN, do not expose the port to the Internet, and use fnOS firewall/access controls or an authenticated reverse proxy if any untrusted device can reach it. File operations remain limited to the explicitly configured workspace. Read [SECURITY.md](SECURITY.md) before enabling command execution.

## Development

Requirements: Node.js 18+ for the local preview. The app has no npm dependencies.

```sh
npm run check
FN_CODEX_ALLOW_COMMANDS=1 npm start
```

Set `FN_CODEX_WORKSPACE=/path/to/project` to preview a real project. The default is `app/workspace` in a checkout and the persistent app home in an FPK.

Build and inspect FPK source:

```sh
bash scripts/validate-fpk.sh --source fpk
PLATFORM=x86_64 bash scripts/build-fpk.sh
```

On an fnOS development environment with the official packager available, prefer `fnpack build --directory fpk`; see [docs/fpk.md](docs/fpk.md) for the evidence, package contract, and unverified hardware boundary.

## License

Apache-2.0. See [LICENSE](LICENSE).
