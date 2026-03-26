# Design: Auto-Build Elastix-Enabled Wheels on Release

**Date:** 2026-03-25
**Status:** Approved

## Goal

When a GitHub Release is created, automatically build SimpleITK Python wheels with Elastix (image registration) enabled for Linux x86_64 and Windows x86_64, and attach them as release assets. Downstream projects install directly from the release:

```
pip install simpleitk --find-links https://github.com/<owner>/SimpleITK_Elastix/releases/tag/<tag>
```

## Constraints

- Two self-hosted runners: CICD001 (Windows, X64), CICD002 (Linux, X64)
- Publish job uses GitHub-hosted `ubuntu-latest` (lightweight, no build)
- Python versions: 3.10, 3.11, 3.12, 3.13
- Limited API wheel for 3.11+ (single `cp311-abi3` wheel), separate 3.10 wheel
- Minimize changes to upstream files for easy future syncing

## Architecture

```
GitHub Release (published)
         │
         ├──> build-linux-x86_64 (CICD002, self-hosted Linux)
         │      ├── Docker build (Dockerfile-2014-x86_64)
         │      ├── SuperBuild with SimpleITK_USE_ELASTIX=ON
         │      ├── Build cp310 wheel
         │      ├── Build cp311-abi3 wheel (covers 3.11-3.13)
         │      └── auditwheel repair
         │
         ├──> build-windows (CICD001, self-hosted Windows)
         │      ├── SuperBuild with SimpleITK_USE_ELASTIX=ON
         │      ├── Build cp310 wheel
         │      └── Build cp311-abi3 wheel (covers 3.11-3.13)
         │
         └──> publish (ubuntu-latest, after both builds)
                ├── Download all wheel artifacts
                ├── Generate checksums
                └── Upload to GitHub Release
```

## Files to Create/Modify

| File | Action | Purpose |
|------|--------|---------|
| `.github/workflows/ReleaseElastix.yml` | Create | New workflow with 3 jobs |
| `Utilities/Distribution/manylinux/imagefiles/cmd.sh` | Patch | Accept `SIMPLEITK_USE_ELASTIX` env var |

## Linux Build Details

- Reuses existing `Dockerfile-2014-x86_64` and `cmd.sh`
- Small patch to `cmd.sh`: pass `SIMPLEITK_USE_ELASTIX` env var to cmake SuperBuild
- Docker container runs the SuperBuild, then builds Python wheels
- `auditwheel repair` ensures manylinux compliance
- Env vars passed into container: `SIMPLEITK_USE_ELASTIX=ON`, `BUILD_PYTHON_LIMITED_API=1`, `PYTHON_VERSIONS=cp310-cp310`

## Windows Build Details

- Runs on CICD001 (self-hosted, Windows, X64)
- Uses `actions/setup-python` to install Python 3.10 and 3.11
- SuperBuild step: CMake with Visual Studio generator, `SimpleITK_USE_ELASTIX:BOOL=ON`
- Wheel build step: For each Python, configure against SuperBuild output and build wheel
- Limited API for 3.11+ produces one wheel covering 3.11-3.13

## Publish Details

- Runs on `ubuntu-latest` after both builds succeed
- Downloads artifacts from both jobs
- Generates SHA256 checksums
- Uploads all `.whl` files to the triggering GitHub Release
- Adds install instructions to release notes

## What This Does NOT Change

- `pyproject.toml` — Elastix toggle is at SuperBuild level
- Dockerfiles — reused as-is
- Existing `Package.yml` / `Build.yml` workflows — untouched
- Upstream compatibility — only one upstream file patched (cmd.sh, backward compatible)
