#!/usr/bin/env bash
# 打包 AropytEditor
# 用法：./package.sh [dmg|pkg]   默认 dmg
set -euo pipefail

MODE="${1:-dmg}"
if [[ "$MODE" != "dmg" && "$MODE" != "pkg" ]]; then
    echo "用法：$0 [dmg|pkg]" >&2
    exit 1
fi

APP_NAME="AropytEditor"
DISPLAY_NAME="Aropyt"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFO_PLIST="$SCRIPT_DIR/Sources/$APP_NAME/Resources/Info.plist"
BUNDLE_ID="$(/usr/bin/plutil -extract CFBundleIdentifier raw "$INFO_PLIST")"
DESIGNATED_REQUIREMENT="designated => identifier \"$BUNDLE_ID\""
VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$INFO_PLIST")"
BUILD_DIR="$SCRIPT_DIR/.build/release"
DIST_DIR="$SCRIPT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aropyt-package.XXXXXX")"
STAGED_APP="$WORK_DIR/$APP_NAME.app"
ASSOCIATION_HELPER="$WORK_DIR/preserve-markdown-default"
ASSOCIATION_SNAPSHOT="$WORK_DIR/markdown-default.json"

cleanup() {
    local result=$?
    trap - EXIT
    # Remove transient app copies before restoring the original association.
    rm -rf "$STAGED_APP" "$WORK_DIR/dmg" "$WORK_DIR/pkg"
    if [[ -f "$ASSOCIATION_SNAPSHOT" ]]; then
        if ! "$ASSOCIATION_HELPER" restore "$ASSOCIATION_SNAPSHOT" "$BUNDLE_ID" "$APP_BUNDLE"; then
            echo "错误：未能恢复打包前的 Markdown 默认应用。" >&2
            [[ "$result" -ne 0 ]] || result=1
        fi
    fi
    rm -rf "$WORK_DIR"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Only restore associations that already point to Aropyt; other choices are kept.
swiftc "$SCRIPT_DIR/Scripts/PreserveMarkdownDefault.swift" -o "$ASSOCIATION_HELPER"
"$ASSOCIATION_HELPER" snapshot "$ASSOCIATION_SNAPSHOT" "$BUNDLE_ID"

# ── 第 1 步：编译 ────────────────────────────────────────────────────────────
echo "==> [1/4] swift build -c release"
cd "$SCRIPT_DIR"
swift build -c release

# ── 第 2 步：组装 .app bundle ─────────────────────────────────────────────────
echo "==> [2/4] 组装 $APP_NAME.app"
mkdir -p "$STAGED_APP/Contents/MacOS"
mkdir -p "$STAGED_APP/Contents/Resources"

# 主二进制
cp "$BUILD_DIR/$APP_NAME" "$STAGED_APP/Contents/MacOS/$APP_NAME"

# SPM 资源包（本地化 / JS / CSS / 图标）—— 代码通过 AppResources 定位
cp -R "$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle" \
      "$STAGED_APP/Contents/Resources/"

# Info.plist —— bundle 模式由系统从 Contents/ 读；裸跑时靠 Mach-O __info_plist 段
cp "$INFO_PLIST" \
   "$STAGED_APP/Contents/Info.plist"

# App icon —— CFBundleIconFile 从 Contents/Resources 顶层读取
cp "$SCRIPT_DIR/Sources/$APP_NAME/Resources/AropytEditor.icns" \
   "$STAGED_APP/Contents/Resources/AropytEditor.icns"

# ── 第 3 步：Ad-hoc 签名 ─────────────────────────────────────────────────────
# 固定 DR 让 macOS 在不同 ad-hoc 构建间保持应用身份；正式分发仍需真实证书和 notarize
echo "==> [3/4] ad-hoc 签名"
codesign --deep --force --sign - \
    --identifier "$BUNDLE_ID" \
    --requirements "=$DESIGNATED_REQUIREMENT" \
    "$STAGED_APP"

# Keep the app directory's identity instead of deleting a possible default app.
mkdir -p "$APP_BUNDLE"
/usr/bin/rsync -a --delete "$STAGED_APP/" "$APP_BUNDLE/"
codesign --verify --deep --strict "$APP_BUNDLE"

# ── 第 4 步：打包 ─────────────────────────────────────────────────────────────
if [[ "$MODE" == "dmg" ]]; then
    OUTPUT="$DIST_DIR/$DISPLAY_NAME-$VERSION.dmg"
    echo "==> [4/4] 打 DMG → $OUTPUT"

    # 保留拖拽安装入口，跳过需要打开 Finder 的窗口和图标排版。
    DMG_SRC="$WORK_DIR/dmg"
    mkdir -p "$DMG_SRC"
    cp -R "$APP_BUNDLE" "$DMG_SRC/"
    ln -s /Applications "$DMG_SRC/Applications"

    create-dmg \
        --skip-jenkins \
        --volname "$DISPLAY_NAME $VERSION" \
        "$WORK_DIR/$DISPLAY_NAME-$VERSION.dmg" \
        "$DMG_SRC"
    mv -f "$WORK_DIR/$DISPLAY_NAME-$VERSION.dmg" "$OUTPUT"

elif [[ "$MODE" == "pkg" ]]; then
    OUTPUT="$DIST_DIR/$DISPLAY_NAME-$VERSION.pkg"
    echo "==> [4/4] 打 PKG → $OUTPUT"

    # pkgbuild 把 --root 下的内容安装到 --install-location
    # 结果：用户双击 pkg 后 .app 被装入 /Applications/
    PKG_ROOT="$WORK_DIR/pkg"
    mkdir -p "$PKG_ROOT"
    cp -R "$APP_BUNDLE" "$PKG_ROOT/"

    pkgbuild \
        --root "$PKG_ROOT" \
        --install-location /Applications \
        --identifier "$BUNDLE_ID" \
        --version "$VERSION" \
        "$WORK_DIR/$DISPLAY_NAME-$VERSION.pkg"
    mv -f "$WORK_DIR/$DISPLAY_NAME-$VERSION.pkg" "$OUTPUT"
fi

echo ""
echo "Done! 产物：$OUTPUT"
