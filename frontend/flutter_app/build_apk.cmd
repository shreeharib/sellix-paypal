@echo off
setlocal
rem Builds the sellix release APK (signed with android\key.properties).
rem   build_apk.cmd                          the app asks for the server on its sign-in screen ("Server")
rem   build_apk.cmd https://api.example.com  the server is built in (the app can still change it)
cd /d "%~dp0"
if "%~1"=="" (
  call "D:\Android\flutter-direct.cmd" build apk --release
) else (
  call "D:\Android\flutter-direct.cmd" build apk --release --dart-define=API_BASE_URL=%~1
)
if errorlevel 1 (
  echo.
  echo Build failed. The first error above says what went wrong.
  pause
  exit /b 1
)
echo.
echo Your APK: %~dp0build\app\outputs\flutter-apk\app-release.apk
explorer "%~dp0build\app\outputs\flutter-apk"
endlocal
