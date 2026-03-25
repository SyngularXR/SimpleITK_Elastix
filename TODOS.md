# TODOs

## macOS Wheel Builds

**What:** Add macOS x86_64 + ARM64 wheel builds to `ReleaseElastix.yml`.
**Why:** Enables `pip install` on macOS without building from source.
**Context:** The existing `Package.yml` has proven macOS build configs (Intel `macos-15-intel` + ARM `mac-arm64`) with correct deployment targets and visibility flags. These can be adapted for the Elastix workflow. Requires either macOS self-hosted runners or GitHub-hosted macOS runners (which cost more minutes).
**Blocked by:** No macOS runner currently available.

## Linux aarch64 Wheel Builds

**What:** Add Linux ARM64 wheel builds to `ReleaseElastix.yml`.
**Why:** Covers ARM Linux deployments (AWS Graviton, Docker on Apple Silicon via emulation).
**Context:** The manylinux `Dockerfile-2014-aarch64` already exists and the `cmd.sh` patch works identically. Just needs an ARM self-hosted runner (label: `self-hosted, Linux, ARM64`) or GitHub-hosted `ubuntu-22.04-arm`.
**Blocked by:** No ARM runner currently available.
