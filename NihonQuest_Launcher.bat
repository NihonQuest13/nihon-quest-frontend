@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
color 0B
title NihonQuest - Dev Launcher

REM ========================================
REM Vérification des dossiers au démarrage
REM ========================================
set "FRONTEND=%USERPROFILE%\nihon_quest"
set "BACKEND=%USERPROFILE%\nihon_quest_backend"

if not exist "!FRONTEND!" (
    cls
    echo.
    echo ╔════════════════════════════════════════╗
    echo ║   ❌ ERREUR                            ║
    echo ╚════════════════════════════════════════╝
    echo.
    echo Dossier introuvable: !FRONTEND!
    echo.
    echo Appuyez sur une touche pour quitter...
    pause >nul
    exit /b
)

if not exist "!BACKEND!" (
    cls
    echo.
    echo ╔════════════════════════════════════════╗
    echo ║   ❌ ERREUR                            ║
    echo ╚════════════════════════════════════════╝
    echo.
    echo Dossier introuvable: !BACKEND!
    echo.
    echo Appuyez sur une touche pour quitter...
    pause >nul
    exit /b
)

REM ========================================
REM MENU PRINCIPAL
REM ========================================
:menu
cls
echo.
echo ╔════════════════════════════════════════╗
echo ║   🎮 NihonQuest - Dev Launcher         ║
echo ╚════════════════════════════════════════╝
echo.
echo  1. 🎨 Travailler sur le FRONTEND
echo  2. ⚙️  Travailler sur le BACKEND
echo  3. 🚀 Deploy FRONTEND (push auto-build)
echo  4. 🚀 Deploy BACKEND (push)
echo  5. 📊 Status des projets
echo  6. 🌐 Ouvrir les URLs
echo  7. 💻 Ouvrir VS Code
echo  8. ❌ Quitter
echo.
set /p "choice=Votre choix (1-8): "

if "!choice!"=="1" goto frontend
if "!choice!"=="2" goto backend
if "!choice!"=="3" goto deploy_frontend
if "!choice!"=="4" goto deploy_backend
if "!choice!"=="5" goto status
if "!choice!"=="6" goto open_urls
if "!choice!"=="7" goto vscode
if "!choice!"=="8" goto quit
echo.
echo ⚠️  Choix invalide!
timeout /t 2 >nul
goto menu

REM ========================================
REM FRONTEND
REM ========================================
:frontend
cls
echo.
echo ╔════════════════════════════════════════╗
echo ║   🎨 FRONTEND                          ║
echo ╚════════════════════════════════════════╝
echo.
echo  1. Lancer Flutter (chrome)
echo  2. Build web (local test)
echo  3. Commit et push
echo  4. Retour
echo.
set /p "fe_choice=Choix (1-4): "

if "!fe_choice!"=="1" (
    echo.
    echo 🚀 Lancement de Flutter...
    cd /d "!FRONTEND!"
    start cmd /k "title NihonQuest Frontend && flutter run -d chrome"
    echo ✅ Lancé!
    timeout /t 2 >nul
    goto frontend
)

if "!fe_choice!"=="2" (
    echo.
    echo 🔨 Build local en cours...
    echo (Ce build est pour tester localement uniquement)
    echo.
    cd /d "!FRONTEND!"
    flutter build web --release
    echo.
    echo ✅ Build terminé!
    echo 📂 Fichiers dans: build\web
    echo.
    pause
    goto frontend
)

if "!fe_choice!"=="3" (
    cd /d "!FRONTEND!"
    echo.
    echo 📂 Fichiers modifiés:
    git status -s
    echo.
    set /p "msg=Message de commit: "
    if "!msg!"=="" (
        echo ❌ Message vide
        pause
        goto frontend
    )
    git add .
    git commit -m "!msg!"
    git push origin main
    echo.
    echo ✅ Pushed!
    pause
    goto frontend
)

if "!fe_choice!"=="4" goto menu
goto frontend

REM ========================================
REM BACKEND
REM ========================================
:backend
cls
echo.
echo ╔════════════════════════════════════════╗
echo ║   ⚙️  BACKEND                          ║
echo ╚════════════════════════════════════════╝
echo.
echo  1. Lancer serveur local
echo  2. Commit et push
echo  3. Retour
echo.
set /p "be_choice=Choix (1-3): "

if "!be_choice!"=="1" (
    echo.
    echo 🚀 Lancement du serveur...
    cd /d "!BACKEND!"
    start cmd /k "title NihonQuest Backend && python app.py"
    echo ✅ Lancé!
    timeout /t 2 >nul
    goto backend
)

if "!be_choice!"=="2" (
    cd /d "!BACKEND!"
    echo.
    echo 📂 Fichiers modifiés:
    git status -s
    echo.
    set /p "msg=Message de commit: "
    if "!msg!"=="" (
        echo ❌ Message vide
        pause
        goto backend
    )
    git add .
    git commit -m "!msg!"
    git push origin main
    echo.
    echo ✅ Pushed!
    pause
    goto backend
)

if "!be_choice!"=="3" goto menu
goto backend

REM ========================================
REM DEPLOY FRONTEND
REM ========================================
:deploy_frontend
cls
echo.
echo ╔════════════════════════════════════════╗
echo ║   🚀 Deploy FRONTEND                   ║
echo ╚════════════════════════════════════════╝
echo.
cd /d "!FRONTEND!"

echo 📂 Fichiers modifiés:
git status -s
echo.
set /p "msg=Message de commit: "
if "!msg!"=="" (
    echo ❌ Message vide
    pause
    goto menu
)

echo.
echo 📤 Commit et push du code source...
git add .
git commit -m "!msg!"
git push origin main

if errorlevel 1 (
    echo.
    echo ❌ Push échoué!
    pause
    goto menu
)

echo.
echo ═══════════════════════════════════════
echo ✅ Code source pushed!
echo ═══════════════════════════════════════
echo.
echo 🔨 Cloudflare Pages va maintenant:
echo    1. Détecter le push automatiquement
echo    2. Cloner le repository
echo    3. Exécuter build.sh (installer Flutter + compiler)
echo    4. Déployer le site
echo.
echo 🌐 URL: https://nihonquest.pages.dev
echo ⏱️  Temps estimé: 3-5 minutes
echo.
echo 💡 Astuce: Ouvrez le dashboard Cloudflare pour suivre le build
echo    (Menu option 6 puis sélectionnez Cloudflare)
echo.
pause
goto menu

REM ========================================
REM DEPLOY BACKEND
REM ========================================
:deploy_backend
cls
echo.
echo ╔════════════════════════════════════════╗
echo ║   🚀 Deploy BACKEND                    ║
echo ╚════════════════════════════════════════╝
echo.
cd /d "!BACKEND!"

echo 📂 Fichiers modifiés:
git status -s
echo.
set /p "msg=Message de commit: "
if "!msg!"=="" (
    echo ❌ Message vide
    pause
    goto menu
)

echo.
echo 📤 Ajout des fichiers...
git add .

echo 💾 Commit...
git commit -m "!msg!"

echo 🚀 Push...
git push origin main
if errorlevel 1 (
    echo.
    echo ❌ Push échoué!
    pause
    goto menu
)

echo.
echo ═══════════════════════════════════════
echo ✅ Déployé!
echo ═══════════════════════════════════════
echo.
echo 🌐 https://nihon-quest-api.onrender.com
echo ⏱️  Disponible dans 2-5 minutes
echo.
pause
goto menu

REM ========================================
REM STATUS
REM ========================================
:status
cls
echo.
echo ╔════════════════════════════════════════╗
echo ║   📊 Status                            ║
echo ╚════════════════════════════════════════╝
echo.
echo ═══ FRONTEND ═══
cd /d "!FRONTEND!"
git status -s
echo.
echo ═══ BACKEND ═══
cd /d "!BACKEND!"
git status -s
echo.
echo ═══ URLs ═══
echo Frontend: https://nihonquest.pages.dev
echo Backend:  https://nihon-quest-api.onrender.com
echo.
pause
goto menu

REM ========================================
REM OPEN URLS
REM ========================================
:open_urls
cls
echo.
echo 🌐 Ouverture des URLs...
echo.
start https://nihonquest.pages.dev
timeout /t 1 >nul
start https://nihon-quest-api.onrender.com
timeout /t 1 >nul
start https://dashboard.render.com
timeout /t 1 >nul
start https://dash.cloudflare.com
echo ✅ Ouvert!
timeout /t 2 >nul
goto menu

REM ========================================
REM VS CODE
REM ========================================
:vscode
cls
echo.
echo 💻 Ouverture VS Code...
echo.
start code "!FRONTEND!"
timeout /t 1 >nul
start code "!BACKEND!"
echo ✅ Ouvert!
timeout /t 2 >nul
goto menu

REM ========================================
REM QUIT
REM ========================================
:quit
cls
echo.
echo 👋 Au revoir!
timeout /t 1 >nul
exit