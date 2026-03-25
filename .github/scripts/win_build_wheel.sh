#!/usr/bin/env bash
# Build a SimpleITK Python wheel on Windows against a SuperBuild output.
# Usage: win_build_wheel.sh <BLD_DIR> <SRC_DIR> <BUILD_SUFFIX> <USE_LIMITED_API>
#   BLD_DIR         - Path to the SuperBuild output directory
#   SRC_DIR         - Path to the SimpleITK source tree (GITHUB_WORKSPACE)
#   BUILD_SUFFIX    - Subdirectory name for the wheel build (e.g. py311-abi3)
#   USE_LIMITED_API - ON or OFF
set -ex

BLD_DIR="$1"
SRC_DIR="$2"
BUILD_SUFFIX="$3"
USE_LIMITED_API="$4"

PYTHON_EXE=$(python -c "import sys; print(sys.executable)")
VENV_PYTHON="$BLD_DIR/venv/Scripts/python.exe"
if [ ! -f "$VENV_PYTHON" ]; then
  echo "WARNING: SuperBuild venv not found at $VENV_PYTHON, using system Python"
  VENV_PYTHON="$PYTHON_EXE"
fi

pip install ninja

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
