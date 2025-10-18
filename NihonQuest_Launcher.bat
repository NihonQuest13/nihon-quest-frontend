@echo off
chcp 65001 >nul
color 0B
title NihonQuest - Dev Launcher

:menu
cls
echo ╔════════════════════════════════════════╗
echo ║   🎮 NihonQuest - Dev Launcher         ║
echo ╚════════════════════════════════════════╝
echo.
echo  1. 🎨 Travailler sur le FRONTEND
echo  2. ⚙️  Travailler sur le BACKEND
echo  3. 🔄 Workflow FULLSTACK
echo  4. 🚀 Deploy FRONTEND (build + push)
echo  5. 🚀 Deploy BACKEND (push)
echo  6. 📊 Status des projets
echo  7. 🌐 Ouvrir les URLs de production
echo  8. 💻 Ouvrir VS Code (Frontend + Backend)
echo  9. ❌ Quitter
echo.
set /p choice="Votre choix (1-9): "

if "%choice%"=="1" goto frontend
if "%choice%"=="2" goto backend
if "%choice%"=="3" goto fullstack
if "%choice%"=="4" goto deploy_frontend
if "%choice%"=="5" goto deploy_backend
if "%choice%"=="6" goto status
if "%choice%"=="7" goto open_urls
if "%choice%"=="8" goto vscode
if "%choice%"=="9" goto end
goto menu

:frontend
cls
echo 🎨 FRONTEND - Menu
echo ==================
echo.
echo  1. Lancer Flutter (chrome)
echo  2. Build web
echo  3. Commit et push
echo  4. Retour
echo.
set /p fe_choice="Choix (1-4): "

if "%fe_choice%"=="1" (
    cd /d %USERPROFILE%\nihon_quest
    start cmd /k "flutter run -d chrome"
    pause
)
if "%fe_choice%"=="2" (
    cd /d %USERPROFILE%\nihon_quest
    flutter build web --release
    pause
)
if "%fe_choice%"=="3" (
    cd /d %USERPROFILE%\nihon_quest
    set /p msg="Message de commit: "
    git add .
    git commit -m "%msg%"
    git push origin main
    echo ✅ Pushed! Cloudflare déploie...
    pause
)
if "%fe_choice%"=="4" goto menu
goto frontend

:backend
cls
echo ⚙️  BACKEND - Menu
echo ==================
echo.
echo  1. Lancer serveur local
echo  2. Commit et push
echo  3. Retour
echo.
set /p be_choice="Choix (1-3): "

if "%be_choice%"=="1" (
    cd /d %USERPROFILE%\nihon_quest_backend
    start cmd /k "python app.py"
    pause
)
if "%be_choice%"=="2" (
    cd /d %USERPROFILE%\nihon_quest_backend
    set /p msg="Message de commit: "
    git add .
    git commit -m "%msg%"
    git push origin main
    echo ✅ Pushed! Render redéploie...
    pause
)
if "%be_choice%"=="3" goto menu
goto backend

:fullstack
cls
echo 🔄 Workflow FULLSTACK
echo ====================
echo.
echo Étape 1: Modifier le BACKEND
pause
cd /d %USERPROFILE%\nihon_quest_backend
start cmd /k "echo Backend - Faites vos modifs puis tapez 'exit'"
pause

set /p be_msg="Message de commit backend: "
cd /d %USERPROFILE%\nihon_quest_backend
git add .
git commit -m "%be_msg%"
git push origin main
echo ✅ Backend pushed!
echo.
echo ⏳ Attendez le déploiement Render (2-5 min)...
pause

echo.
echo Étape 2: Modifier le FRONTEND
pause
cd /d %USERPROFILE%\nihon_quest
start cmd /k "echo Frontend - Faites vos modifs puis tapez 'exit'"
pause

set /p fe_msg="Message de commit frontend: "
cd /d %USERPROFILE%\nihon_quest
flutter build web --release
git add .
git commit -m "%fe_msg%"
git push origin main
echo ✅ Frontend pushed!
pause
goto menu

:deploy_frontend
cls
echo 🚀 Déploiement FRONTEND
echo =======================
echo.
cd /d %USERPROFILE%\nihon_quest
echo.
echo ⚠️  IMPORTANT: Ne pas faire flutter clean (garde build/web)
echo.
echo 🔨 Build en cours...
flutter build web --release
if errorlevel 1 (
    echo ❌ Erreur lors du build!
    pause
    goto menu
)
echo.
echo ✅ Build réussi!
echo.
set /p msg="Message de commit: "
git add -A
git commit -m "%msg%"
if errorlevel 1 (
    echo ⚠️  Rien à commiter ou erreur
    pause
    goto menu
)
git push origin main
if errorlevel 1 (
    echo ❌ Erreur lors du push!
    pause
    goto menu
)
echo.
echo ✅ Déployé! Vérifiez: https://nihonquest.pages.dev
pause
goto menu

:deploy_backend
cls
echo 🚀 Déploiement BACKEND
echo ======================
echo.
cd /d %USERPROFILE%\nihon_quest_backend
set /p msg="Message de commit: "
git add .
git commit -m "%msg%"
git push origin main
echo.
echo ✅ Déployé! Render redéploie automatiquement
echo Vérifiez: https://nihon-quest-api.onrender.com
pause
goto menu

:status
cls
echo 📊 Status des projets
echo ====================
echo.
echo === FRONTEND ===
cd /d %USERPROFILE%\nihon_quest
git status -s
echo.
echo === BACKEND ===
cd /d %USERPROFILE%\nihon_quest_backend
git status -s
echo.
echo 🌐 URLs de production:
echo Frontend: https://nihonquest.pages.dev
echo Backend: https://nihon-quest-api.onrender.com
echo.
pause
goto menu

:open_urls
cls
echo 🌐 Ouverture des URLs...
start https://nihonquest.pages.dev
start https://nihon-quest-api.onrender.com
start https://dashboard.render.com
start https://dash.cloudflare.com
echo ✅ URLs ouvertes!
timeout /t 2 >nul
goto menu

:vscode
cls
echo 💻 Ouverture de VS Code...
start code %USERPROFILE%\nihon_quest
start code %USERPROFILE%\nihon_quest_backend
echo ✅ VS Code lancé!
timeout /t 2 >nul
goto menu

:end
cls
echo 👋 Au revoir!
timeout /t 1 >nul
exit