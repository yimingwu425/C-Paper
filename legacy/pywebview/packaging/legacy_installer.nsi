!include "MUI2.nsh"

!ifndef APP_VERSION
  !define APP_VERSION "5.2.1"
!endif

!ifndef APP_NAME
  !define APP_NAME "C-Paper"
!endif

!ifndef APP_EXE
  !define APP_EXE "C-Paper.exe"
!endif

!ifndef SOURCE_DIR
  !define SOURCE_DIR "dist\\C-Paper"
!endif

!ifndef OUTPUT_FILE
  !define OUTPUT_FILE "dist\\C-Paper-legacy-${APP_VERSION}-setup.exe"
!endif

Name "${APP_NAME} Legacy ${APP_VERSION}"
OutFile "${OUTPUT_FILE}"
InstallDir "$LOCALAPPDATA\\Programs\\${APP_NAME} Legacy"
RequestExecutionLevel user
Unicode True

!define MUI_ABORTWARNING

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

Section "Install"
  SetOutPath "$INSTDIR"
  File /r "${SOURCE_DIR}\\*.*"

  WriteUninstaller "$INSTDIR\\Uninstall ${APP_NAME} Legacy.exe"

  CreateDirectory "$SMPROGRAMS\\${APP_NAME} Legacy"
  CreateShortcut "$SMPROGRAMS\\${APP_NAME} Legacy\\${APP_NAME} Legacy.lnk" "$INSTDIR\\${APP_EXE}"
  CreateShortcut "$SMPROGRAMS\\${APP_NAME} Legacy\\Uninstall ${APP_NAME} Legacy.lnk" "$INSTDIR\\Uninstall ${APP_NAME} Legacy.exe"
  CreateShortcut "$DESKTOP\\${APP_NAME} Legacy.lnk" "$INSTDIR\\${APP_EXE}"
SectionEnd

Section "Uninstall"
  Delete "$DESKTOP\\${APP_NAME} Legacy.lnk"
  Delete "$SMPROGRAMS\\${APP_NAME} Legacy\\${APP_NAME} Legacy.lnk"
  Delete "$SMPROGRAMS\\${APP_NAME} Legacy\\Uninstall ${APP_NAME} Legacy.lnk"
  RMDir "$SMPROGRAMS\\${APP_NAME} Legacy"
  RMDir /r "$INSTDIR"
SectionEnd
