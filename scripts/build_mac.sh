#!/usr/bin/env bash
# ============================================================
#  CIE 试卷下载器 — macOS 打包脚本（干净 venv 构建）
#  产出: dist/C-Paper.dmg
#  用法: bash build_mac.sh
# ============================================================
set -e
cd "$(dirname "$0")"

APP_NAME="C-Paper"
ENTRY="../src/main.py"
BUNDLE_ID="cn.fraft.cpaper"
DIST_DIR="dist"
BUILD_DIR="build"
VENV_DIR=".build_venv"
DMG_OUT="${DIST_DIR}/${APP_NAME}.dmg"

# ── 系统 Python（不用 conda，避免携带大量科学计算包） ──
SYS_PYTHON=$(which python3.13 2>/dev/null \
  || which python3.12 2>/dev/null \
  || which python3.11 2>/dev/null \
  || which python3 2>/dev/null)

# 如果当前是 conda python，尝试找系统原生 python
if echo "$SYS_PYTHON" | grep -q "anaconda\|miniconda\|conda"; then
  for candidate in \
      /usr/bin/python3 \
      /usr/local/bin/python3 \
      /opt/homebrew/bin/python3; do
    if [ -f "$candidate" ] && ! "$candidate" -c "import sys;sys.exit(0 if 'conda' not in sys.prefix else 1)" 2>/dev/null; then
      SYS_PYTHON="$candidate"
      break
    fi
  done
fi

echo "▶ 使用 Python: $SYS_PYTHON ($(${SYS_PYTHON} --version))"

# ══ Step 1: 创建干净的 venv ══════════════════════════════
echo ""
echo "▶ [1/6] 创建干净 venv（隔离 Anaconda 大包）..."
rm -rf "${VENV_DIR}"
"${SYS_PYTHON}" -m venv "${VENV_DIR}"
VENV_PY="${VENV_DIR}/bin/python"
VENV_PIP="${VENV_DIR}/bin/pip"

"${VENV_PIP}" install --quiet --upgrade pip

# ══ Step 2: 只装必需依赖 ═════════════════════════════════
echo "▶ [2/6] 安装最小依赖（pywebview + pyinstaller + requests）..."
"${VENV_PIP}" install --quiet \
  pywebview \
  pyinstaller \
  requests \
  urllib3 \
  pyobjc-framework-WebKit \
  pyobjc-framework-Cocoa \
  pyobjc-framework-UniformTypeIdentifiers

# ══ Step 3: 清理旧构建 ═══════════════════════════════════
echo "▶ [3/6] 清理旧构建..."
rm -rf "${BUILD_DIR}" "${DIST_DIR}/${APP_NAME}.app" "${DMG_OUT}"
mkdir -p "${DIST_DIR}"

# ══ Step 4: PyInstaller 打包 ═════════════════════════════
echo "▶ [4/6] PyInstaller 打包（使用 spec 文件）..."

# 动态生成 spec，内嵌 Info.plist 并排除非必需模块
cat > "_cie_build.spec" << 'SPEC_EOF'
import sys
from PyInstaller.utils.hooks import collect_submodules, collect_data_files

block_cipher = None

EXCLUDES = [
    # 其他 GUI 框架
    'tkinter', '_tkinter', 'tk', 'tcl',
    'PyQt5', 'PyQt6', 'PySide2', 'PySide6', 'wx',
    # 科学计算
    'numpy', 'pandas', 'scipy', 'matplotlib', 'PIL', 'Pillow',
    'sklearn', 'sklearn', 'cv2', 'torch', 'tensorflow',
    # 开发调试工具
    'test', 'tests', 'unittest', 'doctest',
    'pdb', 'pydoc', 'profile', 'cProfile', 'timeit', 'trace',
    'distutils', 'setuptools', 'pkg_resources', 'pip',
    # 不用的标准库
    'sqlite3', '_sqlite3',
    'curses', '_curses',
    'turtle', 'idlelib', 'turtledemo',
    'multiprocessing',
    'lib2to3',
    'xmlrpc',
    # 不需要的 pyobjc 框架（保留 WebKit / Cocoa / UniformTypeIdentifiers）
    'Quartz', 'SceneKit', 'ModelIO', 'GameController',
    'MetalKit', 'SpriteKit', 'MapKit', 'AVFoundation',
    'CoreData', 'iTunesLibrary', 'MediaPlayer',
    'NetworkExtension', 'NotificationCenter', 'SafariServices',
    'StoreKit', 'UserNotifications', 'Vision', 'CoreML',
    'NaturalLanguage', 'Contacts', 'ContactsUI', 'EventKit',
    'FileProvider', 'PhotosUI', 'CoreAudio', 'CoreMIDI',
    'ExceptionHandling', 'FSEvents', 'LatentSemanticMapping',
    'PreferencePanes', 'PubSub', 'ScreenSaver',
    'ServiceManagement', 'SystemConfiguration',
    'OSLog', 'AutomaticAssessmentConfiguration',
    'BusinessChat', 'CallKit', 'ClassKit', 'ClockKit',
    'DataDetection', 'DeviceCheck', 'GameKit',
    'HealthKit', 'HomeKit', 'LinkPresentation',
    'PencilKit', 'RealityKit', 'SharedWithYou',
    'SharedWithYouCore', 'SoundAnalysis', 'Speech',
    'ThreadNetwork', 'Virtualization', 'WebKit.legacy',
    'CoreSpotlight', 'CoreServices', 'CoreWLAN',
    'InputMethodKit', 'InstallerPlugins',
    'LocalAuthentication', 'OpenDirectory',
    'SecurityFoundation', 'SecurityInterface',
    'SyncServices', 'XPC',
]

a = Analysis(
    ['../src/main.py'],
    datas=[
        ('../src/ui_v2.html', '.'),
        ('../src/ui_v2.css', '.'),
        ('../src/ui_v2.js', '.'),
        ('../version.json', '.'),
    ] + collect_data_files('webview'),
    pathex=[],
    binaries=[],
    hiddenimports=[
        'webview',
        'webview.platforms.cocoa',
        'webview.http',
        'webview.js',
        'webview.util',
        'requests',
        'urllib3',
        'backend', 'backend.const', 'backend.cache', 'backend.limiter',
        'backend.engine', 'backend.parser', 'backend.api',
        'Foundation', 'AppKit', 'WebKit', 'UniformTypeIdentifiers',
    ],
    hookspath=[],
    runtime_hooks=[],
    excludes=EXCLUDES,
    cipher=block_cipher,
    noarchive=False,
)

# 进一步过滤打包物（排除漏网的 Quartz 等大框架）
_DROP = {'Quartz','SceneKit','ModelIO','GameController','MetalKit',
         'SpriteKit','MapKit','AVFoundation','CoreData','iTunesLibrary',
         'MediaPlayer','CoreAudio','CoreMIDI','Vision','CoreML',
         'NaturalLanguage','ExceptionHandling','PreferencePanes',
         'ScreenSaver','ServiceManagement','SystemConfiguration',
         'CoreServices','CoreWLAN','InputMethodKit','LocalAuthentication',
         'OpenDirectory','SecurityFoundation','SecurityInterface',
         'AutomaticAssessmentConfiguration','FSEvents','OSLog',
         'GameKit','HealthKit','HomeKit','Speech',}

def _keep(name):
    return not any(d in name for d in _DROP)

a.binaries = TOC([x for x in a.binaries if _keep(x[0])])
a.datas    = TOC([x for x in a.datas    if _keep(x[0])])
a.pure     = TOC([x for x in a.pure     if _keep(x[0])])

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz, a.scripts, [],
    exclude_binaries=True,
    name='C-Paper',
    debug=False,
    strip=True,
    upx=True,
    console=False,
)

coll = COLLECT(
    exe, a.binaries, a.zipfiles, a.datas,
    strip=True,
    upx=True,
    upx_exclude=[],
    name='C-Paper',
)

app = BUNDLE(
    coll,
    name='C-Paper.app',
    icon='../assets/icon.icns',
    bundle_identifier='cn.fraft.cpaper',
    info_plist={
        'NSHighResolutionCapable': True,
        'NSAppTransportSecurity': {'NSAllowsArbitraryLoads': True},
        'CFBundleName': 'C-Paper',
        'CFBundleDisplayName': 'C-Paper',
        'CFBundleShortVersionString': '5.2.1',
        'CFBundleVersion': '5.2.1',
        'LSMinimumSystemVersion': '11.0',
        'NSHumanReadableCopyright': '© 2026 C-Paper',
    },
)
SPEC_EOF

"${VENV_DIR}/bin/pyinstaller" \
  --noconfirm \
  --distpath "${DIST_DIR}" \
  --workpath "${BUILD_DIR}" \
  "_cie_build.spec"

rm -f "_cie_build.spec"

APP_PATH="${DIST_DIR}/${APP_NAME}.app"
if [ ! -d "${APP_PATH}" ]; then
  echo "❌ 打包失败：未生成 ${APP_PATH}"
  exit 1
fi

# ══ Step 5: 剪枝（删除打包后残留的无用文件） ════════════
echo "▶ [5/6] 剪枝瘦身 & 清理扩展属性..."
# 清理 macOS 扩展属性（避免 codesign "detritus" 警告）
xattr -cr "${APP_PATH}" 2>/dev/null || true
# 重新签名
codesign --force --deep --sign - "${APP_PATH}" 2>/dev/null || true


FRAMEWORKS="${APP_PATH}/Contents/Frameworks"
RESOURCES="${APP_PATH}/Contents/Resources"

# 删除多余的 pyobjc 框架目录
for DROP_FW in Quartz SceneKit ModelIO GameController MetalKit SpriteKit \
               MapKit AVFoundation CoreData iTunesLibrary MediaPlayer \
               CoreAudio CoreMIDI Vision CoreML NaturalLanguage \
               ExceptionHandling PreferencePanes ScreenSaver \
               ServiceManagement SystemConfiguration CoreServices \
               CoreWLAN InputMethodKit LocalAuthentication OpenDirectory \
               SecurityFoundation SecurityInterface FSEvents OSLog \
               GameKit HealthKit HomeKit Speech Contacts EventKit; do
  find "${APP_PATH}" -name "${DROP_FW}" -type d -exec rm -rf {} + 2>/dev/null || true
  find "${APP_PATH}" -name "${DROP_FW}.*" -exec rm -rf {} + 2>/dev/null || true
done

# 删除不必要文件
find "${APP_PATH}" -name "*.pyc"              -delete      2>/dev/null || true
find "${APP_PATH}" -name "__pycache__"        -type d -exec rm -rf {} + 2>/dev/null || true
find "${APP_PATH}" -name "test"               -type d -exec rm -rf {} + 2>/dev/null || true
find "${APP_PATH}" -name "tests"              -type d -exec rm -rf {} + 2>/dev/null || true
find "${APP_PATH}" -name "*.h"                -delete      2>/dev/null || true
find "${APP_PATH}" -name "*.pdb"              -delete      2>/dev/null || true

# 删除除中英文外的 locale 文件（通常较大）
if [ -d "${RESOURCES}" ]; then
  find "${RESOURCES}" -maxdepth 1 -name "*.lproj" \
    ! -name "en.lproj" ! -name "en_US.lproj" \
    ! -name "zh_CN.lproj" ! -name "zh_TW.lproj" \
    ! -name "Base.lproj" \
    -exec rm -rf {} + 2>/dev/null || true
fi

# ── 打印最终大小 ──
FINAL_SIZE=$(du -sh "${APP_PATH}" | cut -f1)
echo "   App 大小: ${FINAL_SIZE} → ${APP_PATH}"

# ══ Step 6: 制作 DMG ════════════════════════════════════
echo "▶ [6/6] 制作 DMG..."

make_dmg_hdiutil() {
  local STAGING="${DIST_DIR}/_dmg_staging"
  rm -rf "${STAGING}"; mkdir -p "${STAGING}"
  cp -r "${APP_PATH}" "${STAGING}/"
  cp ../README.md "${STAGING}/README.txt"
  ln -s /Applications "${STAGING}/Applications"
  hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${STAGING}" \
    -ov -format UDZO \
    "${DMG_OUT}"
  rm -rf "${STAGING}"
}

make_dmg_hdiutil

# ── 清理 venv（可选，注释掉则保留以便下次复用） ──
echo "   清理 venv..."
rm -rf "${VENV_DIR}"

DMG_SIZE=$(du -sh "${DMG_OUT}" | cut -f1)
echo ""
echo "╔══════════════════════════════════════╗"
echo "║  ✅  打包完成！                       ║"
echo "╠══════════════════════════════════════╣"
printf  "║  App : %-32s║\n" "${FINAL_SIZE}  ${APP_NAME}.app"
printf  "║  DMG : %-32s║\n" "${DMG_SIZE}  ${APP_NAME}.dmg"
echo "╚══════════════════════════════════════╝"
echo ""
echo "安装：打开 ${DMG_OUT}，拖入 Applications 即可"
