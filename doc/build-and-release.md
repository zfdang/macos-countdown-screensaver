# Build, Test, and Release

## Local Development

Requirements: macOS, Xcode or a compatible Swift toolchain/macOS SDK, Swift 5.9 or later, Python 3.9 or later, and Git with full repository history. The deployment target is macOS 13. The current acceptance platform is macOS 15.8 with Xcode 26.3; older OS behavior must be verified on the intended machines.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test --enable-code-coverage
python3 -m unittest discover -s Tests/BuildTests -v
scripts/build.sh all
scripts/acceptance.sh arm64
```

`build.sh` automatically selects `/Applications/Xcode.app` if no developer directory is already specified. It does not modify the machine's global Xcode selection.

`build.sh arm64` and `build.sh x86_64` create architecture-specific bundles. `build.sh all` additionally creates Universal bundles. Each architecture has a `.saver` and a standalone `.app` preview. ZIP archives, Git/version metadata, and SHA-256 checksums are written to `dist/`. Unpacked bundles are under `.build/distribution/<architecture>/`.

On Apple Silicon with Rosetta already installed, the Intel acceptance harness can also be run locally:

```sh
scripts/acceptance.sh x86_64 .acceptance/intel
arch -x86_64 /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift test --arch x86_64
```

Rosetta execution is not a substitute for native Intel hardware. CI runs tests and acceptance on a native Intel runner.

## Version Definition

The user-visible version is `YYYYMMDD.N`:

- `YYYYMMDD` is the latest commit's committer date in `Asia/Singapore`.
- `N` is `git rev-list --count HEAD`: all commits reachable from the build's HEAD, including merge commits.
- Both CPU architectures use the same version for the same commit.
- Rebuilding a commit retains its version; GitHub Actions run numbers are not used.
- Shallow clones are rejected to prevent incorrect counts. CI checks out with `fetch-depth: 0`.

For example, a commit dated October 8, 2026 with 42 reachable commits produces `20261008.42`. The Info.plist short version uses this value, the bundle build number uses `N`, and `build-info.json` contains the complete Git SHA.

## GitHub Actions

`.github/workflows/build.yml` runs on pull requests, pushes to `main`, and manual dispatch:

1. Run Swift unit/interface tests and Python version tests on `macos-15` (arm64) and `macos-15-intel` (x86_64).
2. Build and ad-hoc sign both the saver and preview application on each runner.
3. Execute the distributable preview and an independent bundle-loading harness; validate architecture, Info.plist, and signatures.
4. Upload architecture-specific ZIPs, metadata, checksums, acceptance screenshots, and coverage data as workflow artifacts.
5. After a push to `main`, publish a versioned GitHub Release only when both architecture jobs succeed. A merged PR therefore produces a fresh build automatically. Re-running a successful commit updates its existing release assets rather than creating a second version.

Runner availability is based on the [GitHub-hosted runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners). Only the release job has repository write permissions. Pull requests do not publish releases or use signing credentials.

## Signing

The repository builds with ad-hoc code signing and verifies the resulting signatures. It does not claim Developer ID signing or Apple notarization: those require the project's own signing identity and account credentials, which are not configured. Downloaded builds may require approval through macOS Privacy & Security. Do not disable Gatekeeper or other system protections.

## Acceptance Boundaries

The automated harness loads the actual `.saver` in a separate process that does not link CountdownUI, verifies the principal class and configure sheet, and checks start/stop/restart and independent view instances. It also renders English, Chinese, small, portrait, and tiny system-preview layouts.

The actual macOS System Settings host must additionally be checked manually for configuration, saving, preview refresh, and full-screen operation. Full-screen testing can trigger the user's normal lock policy; unlocking remains a user action. Actual multi-monitor, sleep/wake, long-duration resource use, and older macOS behavior require their respective hardware/environment checks.
