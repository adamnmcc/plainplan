#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
PKG_DIR="$BUILD_DIR/python_lambda"
ZIP_PATH="$BUILD_DIR/plainplan-lambda.zip"

echo "[build] Root: $ROOT_DIR"
rm -rf "$PKG_DIR" "$ZIP_PATH"
mkdir -p "$PKG_DIR"

if [[ ! -f "$ROOT_DIR/requirements-python.txt" ]]; then
  echo "[build] Missing requirements-python.txt"
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "[build] python3 is required"
  exit 1
fi

if ! command -v pip3 >/dev/null 2>&1; then
  echo "[build] pip3 is required"
  exit 1
fi

if ! command -v zip >/dev/null 2>&1; then
  echo "[build] zip is required"
  exit 1
fi

echo "[build] Installing Python dependencies..."
pip3 install --upgrade --target "$PKG_DIR" -r "$ROOT_DIR/requirements-python.txt"

echo "[build] Copying application files..."
cp -r "$ROOT_DIR/python_service" "$PKG_DIR/"
cp -r "$ROOT_DIR/test-fixtures" "$PKG_DIR/"

pushd "$PKG_DIR" >/dev/null
echo "[build] Creating zip artifact..."
zip -r "$ZIP_PATH" . >/dev/null
popd >/dev/null

echo "[build] Done: $ZIP_PATH"
