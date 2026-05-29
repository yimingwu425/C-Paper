@echo off
:: ============================================================
::  C-Paper — Windows 打包脚本
::  产出: dist\C-Paper_win.zip
::  用法: 双击运行 或 build_win.bat
:: ============================================================
setlocal EnableDelayedExpansion
cd /d "%~dp0\.."

set APP_NAME=C-Paper
set ENTRY=main.py
set DIST=dist
set BUILD=build
set VENV=.build_venv_win

echo.
echo ======================================
echo  C-Paper Windows 打包工具
echo ======================================
echo.

:: ── Step 1: 创建干净 venv ─────────────────────────────────
echo [1/5] 创建干净 venv...
if exist %VENV% rmdir /s /q %VENV%
python -m venv %VENV%
if errorlevel 1 (
    echo [错误] 创建 venv 失败，请确保已安装 Python 3.x
    pause & exit /b 1
)
call %VENV%\Scripts\activate.bat

:: ── Step 2: 安装最小依赖 ──────────────────────────────────
echo [2/5] 安装依赖（pywebview + pyinstaller + requests）...
pip install --quiet --upgrade pip
pip install --quiet pywebview pyinstaller requests urllib3
if errorlevel 1 (
    echo [错误] 安装依赖失败
    pause & exit /b 1
)

:: ── Step 3: 清理旧构建 ────────────────────────────────────
echo [3/5] 清理旧构建...
if exist %BUILD%             rmdir /s /q %BUILD%
if exist %DIST%\%APP_NAME%   rmdir /s /q %DIST%\%APP_NAME%
if exist _cie_win.spec       del _cie_win.spec

:: ── Step 4: 生成 spec 并打包 ──────────────────────────────
echo [4/5] PyInstaller 打包...

(
echo block_cipher = None
echo.
echo a = Analysis^(
echo     ['main.py'],
echo     pathex=['..\\..'],
echo     binaries=[],
echo     datas=[
echo         ('ui_v2.html', '.'^),
echo         ('ui_v2.css', '.'^),
echo         ('ui_v2.js', '.'^),
echo         ('..\\..\\version.json', '.'^),
echo     ],
echo     hiddenimports=[
echo         'webview',
echo         'webview.platforms.winforms',
echo         'webview.platforms.edgechromium',
echo         'webview.http',
echo         'webview.js',
echo         'webview.util',
echo         'backend',
echo         'backend.const',
echo         'backend.cache',
echo         'backend.limiter',
echo         'backend.engine',
echo         'backend.parser',
echo         'backend.api',
echo         'requests',
echo         'urllib3',
echo         'clr',
echo     ],
echo     hookspath=[],
echo     runtime_hooks=[],
echo     excludes=[
echo         'tkinter', '_tkinter',
echo         'numpy', 'pandas', 'scipy', 'matplotlib',
echo         'PIL', 'Pillow',
echo         'PyQt5', 'PyQt6', 'PySide2', 'PySide6', 'wx',
echo         'test', 'unittest', 'doctest',
echo         'pdb', 'pydoc', 'profile', 'cProfile',
echo         'distutils', 'setuptools', 'pkg_resources',
echo         'sqlite3', '_sqlite3',
echo         'curses', 'turtle', 'idlelib',
echo         'multiprocessing', 'lib2to3',
echo     ],
echo     cipher=block_cipher,
echo     noarchive=False,
echo ^)
echo.
echo pyz = PYZ^(a.pure, a.zipped_data, cipher=block_cipher^)
echo.
echo exe = EXE^(
echo     pyz, a.scripts, [],
echo     exclude_binaries=True,
echo     name='%APP_NAME%',
echo     debug=False,
echo     strip=False,
echo     upx=True,
echo     console=False,
echo     icon=None,
echo ^)
echo.
echo coll = COLLECT^(
echo     exe, a.binaries, a.zipfiles, a.datas,
echo     strip=False,
echo     upx=True,
echo     name='%APP_NAME%',
echo ^)
) > _cie_win.spec

:: 先尝试用 collect-all（更稳），失败则用 spec
pyinstaller ^
    --noconfirm ^
    --distpath %DIST% ^
    --workpath %BUILD% ^
    --paths ..\.. ^
    --collect-all webview ^
    --windowed ^
    --name "%APP_NAME%" ^
    --exclude-module tkinter ^
    --exclude-module numpy ^
    --exclude-module pandas ^
    --exclude-module scipy ^
    --exclude-module matplotlib ^
    --exclude-module PIL ^
    --exclude-module PyQt5 ^
    --exclude-module PyQt6 ^
    --exclude-module PySide2 ^
    --exclude-module PySide6 ^
    --hidden-import webview ^
    --hidden-import webview.platforms.winforms ^
    --hidden-import webview.platforms.edgechromium ^
    --hidden-import backend ^
    --hidden-import backend.const ^
    --hidden-import backend.cache ^
    --hidden-import backend.limiter ^
    --hidden-import backend.engine ^
    --hidden-import backend.parser ^
    --hidden-import backend.api ^
    --add-data "ui_v2.html;." ^
    --add-data "ui_v2.css;." ^
    --add-data "ui_v2.js;." ^
    --add-data "..\..\version.json;." ^
    %ENTRY%

if errorlevel 1 (
    echo [警告] 标准打包失败，尝试 spec 文件模式...
    pyinstaller --noconfirm --distpath %DIST% --workpath %BUILD% _cie_win.spec
    if errorlevel 1 (
        echo [错误] 打包失败
        pause & exit /b 1
    )
)

del _cie_win.spec 2>nul

:: ── Step 5: 打包成 zip ────────────────────────────────────
echo [5/5] 打包 zip...
set ZIP_OUT=%DIST%\%APP_NAME%_win.zip
if exist %ZIP_OUT% del %ZIP_OUT%

powershell -NoProfile -Command ^
    "Compress-Archive -Path '%DIST%\%APP_NAME%' -DestinationPath '%ZIP_OUT%' -Force"

:: 清理 venv 和 build
deactivate
rmdir /s /q %VENV%  2>nul
rmdir /s /q %BUILD% 2>nul

:: 显示大小
for %%F in (%ZIP_OUT%) do set ZIP_SIZE=%%~zF
set /a ZIP_MB=!ZIP_SIZE!/1024/1024

echo.
echo ======================================
echo  打包完成！
echo  文件: %ZIP_OUT%
echo  大小: !ZIP_MB! MB
echo ======================================
echo.
echo 分发方式：
echo   1. 解压 zip，运行 %APP_NAME%.exe 即可
echo   2. 需要 Windows 10 v1803+ 或已安装 Edge WebView2
echo.
pause
