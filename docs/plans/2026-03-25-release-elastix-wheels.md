# Release Elastix Wheels Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Auto-build Elastix-enabled SimpleITK Python wheels (Linux x86_64 + Windows x86_64, Python 3.10-3.13) when a GitHub Release is published, and attach them as release assets.

**Architecture:** New `ReleaseElastix.yml` workflow triggered on release. Linux builds via existing manylinux Docker with patched `cmd.sh`. Windows builds via CMake SuperBuild + Ninja wheel packaging on self-hosted runner. Publish job uploads all wheels to the release.

**Tech Stack:** GitHub Actions, CMake SuperBuild, Docker (manylinux2014), Visual Studio 2022, SWIG, scikit-build-core

**Review decisions (from /plan-eng-review 2026-03-25):**
- 1A: Keep `ilammy/msvc-dev-cmd@v1` for MSVC setup
- 2A: Use `actions/upload-artifact@v4` + `actions/download-artifact@v4`
- 3A: Add workspace cleanup steps for self-hosted runners
- 4A: Extract Windows wheel build into reusable `build_wheel.sh` script
- 5A: Keep only latest 20 releases (auto-cleanup old ones)
- 6A: Add Elastix smoke test after wheel build on both platforms

---

### Task 1: Patch cmd.sh to accept Elastix env var

**Files:**
- Modify: `Utilities/Distribution/manylinux/imagefiles/cmd.sh:41-52`

**Step 1: Add SIMPLEITK_USE_ELASTIX to the cmake SuperBuild command**

In `build_simpleitk()`, add the Elastix flag to the cmake invocation. The env var defaults to OFF so existing usage is unaffected.

Change lines 41-52 from:
```bash
    cmake \
        -DSimpleITK_BUILD_DISTRIBUTE:BOOL=ON \
        -DSimpleITK_BUILD_STRIP:BOOL=ON \
        -DCMAKE_BUILD_TYPE:STRING=Release \
        -DBUILD_TESTING:BOOL=ON \
        -DBUILD_EXAMPLES:BOOL=OFF \
        -DBUILD_SHARED_LIBS:BOOL=OFF \
        -DWRAP_DEFAULT:BOOL=OFF \
        -DITK_GIT_REPOSITORY:STRING="https://github.com/InsightSoftwareConsortium/ITK.git" \
        -DITK_C_OPTIMIZATION_FLAGS:STRING="" \
        -DITK_CXX_OPTIMIZATION_FLAGS:STRING="" \
        ${SRC_DIR}/SuperBuild &&
```

To:
```bash
    cmake \
        -DSimpleITK_BUILD_DISTRIBUTE:BOOL=ON \
        -DSimpleITK_BUILD_STRIP:BOOL=ON \
        -DCMAKE_BUILD_TYPE:STRING=Release \
        -DBUILD_TESTING:BOOL=ON \
        -DBUILD_EXAMPLES:BOOL=OFF \
        -DBUILD_SHARED_LIBS:BOOL=OFF \
        -DWRAP_DEFAULT:BOOL=OFF \
        -DITK_GIT_REPOSITORY:STRING="https://github.com/InsightSoftwareConsortium/ITK.git" \
        -DITK_C_OPTIMIZATION_FLAGS:STRING="" \
        -DITK_CXX_OPTIMIZATION_FLAGS:STRING="" \
        -DSimpleITK_USE_ELASTIX:BOOL=${SIMPLEITK_USE_ELASTIX:-OFF} \
        ${SRC_DIR}/SuperBuild &&
```

**Step 2: Commit**

```bash
git add Utilities/Distribution/manylinux/imagefiles/cmd.sh
git commit -m "feat: accept SIMPLEITK_USE_ELASTIX env var in manylinux build script"
```

---

### Task 1.5: Create Windows wheel build script (DRY)

**Files:**
- Create: `.github/scripts/win_build_wheel.sh`

**Step 1: Create the reusable script**

```bash
#!/usr/bin/env bash
# Usage: win_build_wheel.sh <BLD_DIR> <SRC_DIR> <BUILD_SUFFIX> <USE_LIMITED_API>
set -ex

BLD_DIR="$1"
SRC_DIR="$2"
BUILD_SUFFIX="$3"
USE_LIMITED_API="$4"

PYTHON_EXE=$(python -c "import sys; print(sys.executable)")
VENV_PYTHON="$BLD_DIR/venv/Scripts/python.exe"
if [ ! -f "$VENV_PYTHON" ]; then VENV_PYTHON="$PYTHON_EXE"; fi

BUILD_DIR="$SRC_DIR/$BUILD_SUFFIX"

cmake -G Ninja \
  -DCMAKE_PREFIX_PATH:PATH="$BLD_DIR" \
  -DCMAKE_BUILD_TYPE:STRING=Release \
  -DSWIG_EXECUTABLE:FILEPATH="$BLD_DIR/swigwin/swig.exe" \
  -DSWIG_DIR:PATH="$BLD_DIR/swigwin" \
  -DSimpleITK_PYTHON_USE_LIMITED_API:BOOL="$USE_LIMITED_API" \
  -DSimpleITK_BUILD_DISTRIBUTE:BOOL=ON \
  -DSimpleITK_PYTHON_WHEEL:BOOL=ON \
  -DSimpleITK_Python_EXECUTABLE:FILEPATH="$VENV_PYTHON" \
  -DPython_EXECUTABLE:FILEPATH="$PYTHON_EXE" \
  -S "$SRC_DIR/Wrapping/Python" \
  -B "$BUILD_DIR"
cmake --build "$BUILD_DIR" --config Release
cmake --build "$BUILD_DIR" --config Release --target dist
```

**Step 2: Commit**

```bash
git add .github/scripts/win_build_wheel.sh
git commit -m "feat: add reusable Windows wheel build script"
```

---

### Task 2: Create the ReleaseElastix.yml workflow

**Files:**
- Create: `.github/workflows/ReleaseElastix.yml`

**Step 1: Create the workflow file**

```yaml
name: Release Elastix Wheels

on:
  release:
    types: [published]
  workflow_dispatch:

concurrency:
  group: '${{ github.workflow }}@${{ github.sha }}'

permissions:
  contents: write

jobs:
  build-linux-x86_64:
    runs-on: [self-hosted, Linux, X64]
    timeout-minutes: 360
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0

      - name: Clean workspace
        run: git clean -fdx

      - name: Build Docker Image
        working-directory: Utilities/Distribution/manylinux
        run: |
          docker build --pull=true --rm=true -t simpleitk_manylinux -f Dockerfile-2014-x86_64 .

      - name: Build Elastix Wheels
        env:
          PYTHON_VERSIONS: "cp310-cp310"
          BUILD_CSHARP: 0
          BUILD_JAVA: 0
          BUILD_PYTHON_LIMITED_API: 1
          SIMPLEITK_USE_ELASTIX: "ON"
        run: |
          docker run --rm \
            --user "$(id -u):$(id -g)" \
            --env PYTHON_VERSIONS \
            --env BUILD_CSHARP \
            --env BUILD_JAVA \
            --env BUILD_PYTHON_LIMITED_API \
            --env SIMPLEITK_USE_ELASTIX \
            --env SIMPLEITK_SRC_DIR="/work/src" \
            -v "${{ github.workspace }}:/work/src" \
            -v "${{ github.workspace }}/Utilities/Distribution/manylinux:/work/io" \
            -t simpleitk_manylinux

      - name: List Outputs
        run: |
          find "${{ github.workspace }}/Utilities/Distribution/manylinux" -name "*.whl" -o -name "*.log" | head -50

      - name: Smoke Test Elastix
        run: |
          WHL=$(find "${{ github.workspace }}/Utilities/Distribution/manylinux/wheelhouse" -name "*.whl" | head -1)
          pip install "$WHL"
          python -c "import SimpleITK as sitk; f = sitk.ElastixImageFilter(); print('Elastix OK')"

      - name: Upload Artifacts
        uses: actions/upload-artifact@v4
        with:
          name: linux-x86_64-wheels
          path: |
            ${{ github.workspace }}/Utilities/Distribution/manylinux/wheelhouse/*.whl

  build-windows:
    runs-on: [self-hosted, Windows, X64]
    timeout-minutes: 360
    env:
      BLD_DIR: "${{ github.workspace }}\\bld"
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0

      - name: Clean workspace
        shell: bash
        run: git clean -fdx

      - name: Set up MSVC
        uses: ilammy/msvc-dev-cmd@v1
        with:
          arch: amd64

      - name: SuperBuild with Elastix
        shell: bash
        run: |
          cmake -G "Visual Studio 17 2022" -A x64 \
            -DSimpleITK_BUILD_DISTRIBUTE:BOOL=ON \
            -DBUILD_TESTING:BOOL=OFF \
            -DBUILD_EXAMPLES:BOOL=OFF \
            -DBUILD_SHARED_LIBS:BOOL=OFF \
            -DWRAP_DEFAULT:BOOL=OFF \
            -DSimpleITK_USE_ELASTIX:BOOL=ON \
            -DITK_C_OPTIMIZATION_FLAGS:STRING="" \
            -DITK_CXX_OPTIMIZATION_FLAGS:STRING="" \
            -S "$GITHUB_WORKSPACE/SuperBuild" \
            -B "$BLD_DIR"
          cmake --build "$BLD_DIR" --config Release

      - name: Install Ninja
        shell: bash
        run: pip install ninja

      # --- Limited API wheel (covers Python 3.11, 3.12, 3.13) ---
      - name: Set up Python 3.11
        uses: actions/setup-python@v5
        with:
          python-version: "3.11"

      - name: Build cp311-abi3 Wheel
        shell: bash
        run: |
          "$GITHUB_WORKSPACE/.github/scripts/win_build_wheel.sh" \
            "$BLD_DIR" "$GITHUB_WORKSPACE" "py311-abi3" "ON"

      # --- Python 3.10 wheel ---
      - name: Set up Python 3.10
        uses: actions/setup-python@v5
        with:
          python-version: "3.10"

      - name: Build cp310 Wheel
        shell: bash
        run: |
          "$GITHUB_WORKSPACE/.github/scripts/win_build_wheel.sh" \
            "$BLD_DIR" "$GITHUB_WORKSPACE" "py310" "OFF"

      - name: Collect Wheels
        shell: bash
        run: |
          mkdir -p "$GITHUB_WORKSPACE/artifacts"
          find "$GITHUB_WORKSPACE/py311-abi3" "$GITHUB_WORKSPACE/py310" \
            -iname "simpleitk*.whl" -exec cp -v {} "$GITHUB_WORKSPACE/artifacts/" \;

      - name: Smoke Test Elastix
        shell: bash
        run: |
          WHL=$(find "$GITHUB_WORKSPACE/artifacts" -name "*.whl" | head -1)
          pip install "$WHL"
          python -c "import SimpleITK as sitk; f = sitk.ElastixImageFilter(); print('Elastix OK')"

      - name: Upload Artifacts
        uses: actions/upload-artifact@v4
        with:
          name: windows-x86_64-wheels
          path: ${{ github.workspace }}/artifacts/*.whl

  publish:
    needs: [build-linux-x86_64, build-windows]
    runs-on: ubuntu-latest
    if: github.event_name == 'release'
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0

      - uses: actions/download-artifact@v4
        id: download
        with:
          path: ${{ github.workspace }}/artifacts

      - name: Checksums
        shell: bash
        run: |
          find ${{ steps.download.outputs.download-path }} -type f -name "*.whl" \
            | xargs sha256sum | tee checksums.txt

      - name: Upload Wheels to Release
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          TAG="${{ github.event.release.tag_name }}"
          echo "Uploading wheels to release: $TAG"
          gh release upload "$TAG" \
            $( find ${{ steps.download.outputs.download-path }} -type f -name "*.whl" ) \
            checksums.txt \
            --clobber

      - name: Cleanup Old Releases (keep latest 20)
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          gh release list --limit 100 --json tagName,createdAt \
            --jq 'sort_by(.createdAt) | reverse | .[20:] | .[].tagName' | \
          while read -r tag; do
            echo "Deleting old release: $tag"
            gh release delete "$tag" --yes --cleanup-tag || true
          done
```

**Step 2: Commit**

```bash
git add .github/workflows/ReleaseElastix.yml
git commit -m "feat: add workflow to build Elastix-enabled wheels on release"
```

---

### Task 3: Verify workflow syntax

**Step 1: Install and run actionlint (if available)**

```bash
actionlint .github/workflows/ReleaseElastix.yml
```

If actionlint is not installed, manually review the YAML for syntax errors.

**Step 2: Verify cmd.sh patch is backward compatible**

Confirm that `${SIMPLEITK_USE_ELASTIX:-OFF}` defaults to `OFF` when the env var is not set, preserving existing behavior.

---

### Task 4: Test with workflow_dispatch

**Step 1: Push the branch and trigger manually**

1. Push the changes to a branch
2. Go to Actions > "Release Elastix Wheels" > "Run workflow"
3. This tests the full build pipeline without creating a release

**Step 2: Verify outputs**

- Linux job: should produce 2 wheels in `wheelhouse/` (cp310, cp311-abi3)
- Windows job: should produce 2 wheels in `artifacts/` (cp310, cp311-abi3)
- Publish job: skipped (only runs on release events)

**Step 3: Create a test release**

1. Tag: `v0.0.1-test`
2. Create release from the tag
3. Verify wheels appear as release assets
4. Test installation: `pip install simpleitk --find-links https://github.com/<owner>/SimpleITK_Elastix/releases/tag/v0.0.1-test`
5. Verify Elastix is available: `python -c "import SimpleITK as sitk; sitk.ElastixImageFilter()"`
6. Delete the test release when done

---

## Files Created/Modified

| File | Action | Purpose |
|------|--------|---------|
| `Utilities/Distribution/manylinux/imagefiles/cmd.sh` | Patch (1 line) | Accept `SIMPLEITK_USE_ELASTIX` env var |
| `.github/scripts/win_build_wheel.sh` | Create | Reusable Windows wheel build script (DRY) |
| `.github/workflows/ReleaseElastix.yml` | Create | Release workflow: build + publish |

## Notes

- **Visual Studio version:** The plan uses `Visual Studio 17 2022`. If CICD001 has a different version, update the `-G` flag accordingly.
- **vcvarsall.bat:** The `ilammy/msvc-dev-cmd@v1` action auto-detects the VS installation via `vswhere`. No hardcoded paths needed.
- **Build time:** SuperBuild with Elastix takes ~1-2 hours. The 360-minute timeout accommodates this.
- **Disk space:** SuperBuild produces ~10-20 GB of intermediate files. Workspace cleanup runs at job start.
- **Release retention:** Only the latest 20 releases are kept. Older releases and their tags are auto-deleted.
