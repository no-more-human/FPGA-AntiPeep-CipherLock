@echo off
chcp 65001 >nul
cd /d "%~dp0.."
if not exist ".venv\Scripts\python.exe" python -m venv .venv
if errorlevel 1 goto fail
.venv\Scripts\python.exe -m pip install -r pc\requirements.txt
if errorlevel 1 goto fail
rem Ultralytics installs opencv-python transitively; retain only the contrib cv2 package.
.venv\Scripts\python.exe -m pip uninstall -y opencv-python opencv-python-headless opencv-contrib-python-headless
.venv\Scripts\python.exe -m pip install --force-reinstall --no-deps "opencv-contrib-python>=4.8,<6"
if errorlevel 1 goto fail
.venv\Scripts\python.exe -X utf8 pc\tools\check_environment.py
pause
exit /b
:fail
echo Installation failed. Check the error above.
pause
exit /b 1
