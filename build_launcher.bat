@echo off
echo --- Compilation du Lanceur Nihon Quest ---
REM Assurez-vous que votre venv Python est active
call .\\backend\\venv\\Scripts\\activate.bat

REM Installez PyInstaller si ce n'est pas deja fait
pip install pyinstaller

pyinstaller ^
    --name NihonQuest ^
    --onefile ^
    --windowed ^
    --icon=assets/logo.ico ^
    --distpath=release ^
    launcher.py

echo --- Lanceur compile dans le dossier 'release' ---
pause
