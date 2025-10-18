@echo off
chcp 65001 >nul
color 0B
title NihonQuest - Dev Launcher

REM Vérification des dossiers
if not exist "%USERPROFILE%\nihon_quest" (
    echo ❌ Dossier nihon_quest introuvable!
    pause
    exit
)
if not exist "%USERPROFILE%\nihon_quest_backend" (
    echo ❌ Dossier nihon_quest_backend introuvable!
    pause
    exit
)

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
echo ⚠️  Choix invalide!
timeout /t 2 >nul
goto menu

:frontend
cls
echo ╔════════════════════════════════════════╗
echo ║   🎨 FRONTEND - Menu                   ║
echo ╚════════════════════════════════════════╝
echo.
echo  1. Lancer Flutter (chrome)
echo  2. Build web
echo  3. Commit et push
echo  4. Retour
echo.
set /p fe_choice="Choix (1-4): "

if "%fe_choice%"=="1" (
    echo.
    echo 🚀 Lancement de Flutter...
    cd /d "%USERPROFILE%\nihon_quest"
    start cmd /k "title NihonQuest - Flutter Dev Server && flutter run -d chrome"
    echo ✅ Serveur lancé dans une nouvelle fenêtre!
    timeout /t 2 >nul
)
if "%fe_choice%"=="2" (
    echo.
    echo 🔨 Build en cours...
    cd /d "%USERPROFILE%\nihon_quest"
    flutter build web --release
    if errorlevel 1 (
        echo ❌ Erreur lors du build!
        pause
        goto frontend
    )
    echo ✅ Build réussi!
    pause
)
if "%fe_choice%"=="3" (
    cd /d "%USERPROFILE%\nihon_quest"
    echo.
    git status -s
    echo.
    set /p msg="Message de commit: "
    if "%msg%"=="" (
        echo ❌ Message vide, opération annulée
        pause
        goto frontend
    )
    git add .
    git commit -m "%msg%"
    if errorlevel 1 (
        echo ⚠️  Rien à commiter
        pause
        goto frontend
    )
    git push origin main
    if errorlevel 1 (
        echo ❌ Erreur lors du push!
        pause
        goto frontend
    )
    echo ✅ Pushed! Cloudflare déploie automatiquement...
    echo 🌐 Vérifiez dans quelques secondes: https://nihonquest.pages.dev
    pause
)
if "%fe_choice%"=="4" goto menu
goto frontend

:backend
cls
echo ╔════════════════════════════════════════╗
echo ║   ⚙️  BACKEND - Menu                   ║
echo ╚════════════════════════════════════════╝
echo.
echo  1. Lancer serveur local
echo  2. Commit et push
echo  3. Retour
echo.
set /p be_choice="Choix (1-3): "

if "%be_choice%"=="1" (
    echo.
    echo 🚀 Lancement du serveur backend...
    cd /d "%USERPROFILE%\nihon_quest_backend"
    start cmd /k "title NihonQuest - Backend Server && python app.py"
    echo ✅ Serveur lancé dans une nouvelle fenêtre!
    timeout /t 2 >nul
)
if "%be_choice%"=="2" (
    cd /d "%USERPROFILE%\nihon_quest_backend"
    echo.
    git status -s
    echo.
    set /p msg="Message de commit: "
    if "%msg%"=="" (
        echo ❌ Message vide, opération annulée
        pause
        goto backend
    )
    git add .
    git commit -m "%msg%"
    if errorlevel 1 (
        echo ⚠️  Rien à commiter
        pause
        goto backend
    )
    git push origin main
    if errorlevel 1 (
        echo ❌ Erreur lors du push!
        pause
        goto backend
    )
    echo ✅ Pushed! Render redéploie automatiquement...
    echo 🌐 Vérifiez dans 2-5 min: https://nihon-quest-api.onrender.com
    pause
)
if "%be_choice%"=="3" goto menu
goto backend

:fullstack
cls
echo ╔════════════════════════════════════════╗
echo ║   🔄 Workflow FULLSTACK                ║
echo ╚════════════════════════════════════════╝
echo.
echo Ce workflow vous guide pour:
echo 1. Modifier et déployer le BACKEND
echo 2. Attendre le déploiement Render
echo 3. Modifier et déployer le FRONTEND
echo.
echo Appuyez sur une touche pour commencer...
pause >nul

REM --- BACKEND ---
cls
echo ╔════════════════════════════════════════╗
echo ║   📝 Étape 1/3: BACKEND                ║
echo ╚════════════════════════════════════════╝
echo.
echo Ouvrez VS Code pour modifier le backend...
cd /d "%USERPROFILE%\nihon_quest_backend"
start code "%USERPROFILE%\nihon_quest_backend"
echo.
echo Une fois vos modifications terminées:
pause

echo.
git status -s
echo.
set /p be_msg="Message de commit backend: "
if "%be_msg%"=="" (
    echo ❌ Message vide, workflow annulé
    pause
    goto menu
)

git add .
git commit -m "%be_msg%"
if errorlevel 1 (
    echo ⚠️  Rien à commiter pour le backend
    set /p continue="Continuer quand même? (O/N): "
    if /i not "%continue%"=="O" goto menu
) else (
    git push origin main
    if errorlevel 1 (
        echo ❌ Erreur lors du push backend!
        pause
        goto menu
    )
    echo ✅ Backend pushed!
)

REM --- ATTENTE RENDER ---
cls
echo ╔════════════════════════════════════════╗
echo ║   ⏳ Étape 2/3: Attente déploiement    ║
echo ╚════════════════════════════════════════╝
echo.
echo 🌐 Render est en train de redéployer le backend...
echo 📊 Vous pouvez vérifier sur: https://dashboard.render.com
echo.
echo ⏱️  Temps estimé: 2-5 minutes
echo.
echo Appuyez sur une touche quand le backend est déployé...
pause >nul

REM --- FRONTEND ---
cls
echo ╔════════════════════════════════════════╗
echo ║   📝 Étape 3/3: FRONTEND               ║
echo ╚════════════════════════════════════════╝
echo.
echo Ouvrez VS Code pour modifier le frontend...
cd /d "%USERPROFILE%\nihon_quest"
start code "%USERPROFILE%\nihon_quest"
echo.
echo Une fois vos modifications terminées:
pause

echo.
echo 🔨 Build web en cours...
flutter build web --release
if errorlevel 1 (
    echo ❌ Erreur lors du build!
    pause
    goto menu
)

echo.
git status -s
echo.
set /p fe_msg="Message de commit frontend: "
if "%fe_msg%"=="" (
    echo ❌ Message vide, workflow annulé
    pause
    goto menu
)

git add .
git commit -m "%fe_msg%"
if errorlevel 1 (
    echo ⚠️  Rien à commiter pour le frontend
    pause
    goto menu
)

git push origin main
if errorlevel 1 (
    echo ❌ Erreur lors du push frontend!
    pause
    goto menu
)

echo.
echo ✅ Workflow FULLSTACK terminé!
echo.
echo 🌐 Frontend: https://nihonquest.pages.dev
echo 🌐 Backend: https://nihon-quest-api.onrender.com
pause
goto menu

:deploy_frontend
cls
echo ╔════════════════════════════════════════╗
echo ║   🚀 Déploiement FRONTEND              ║
echo ╚════════════════════════════════════════╝
echo.
cd /d "%USERPROFILE%\nihon_quest"
echo ⚠️  IMPORTANT: Ne pas faire flutter clean (garde build/web)
echo.
echo 🔨 Build en cours...
flutter build web --release
if errorlevel 1 (
    echo.
    echo ❌ Erreur lors du build!
    pause
    goto menu
)

echo.
echo ✅ Build réussi!
echo.
echo 📂 Fichiers modifiés:
git status -s
echo.
set /p msg="Message de commit: "
if "%msg%"=="" (
    echo ❌ Message vide, déploiement annulé
    pause
    goto menu
)

echo.
echo 📤 Ajout des fichiers...
git add -A

echo 💾 Commit en cours...
git commit -m "%msg%"
if errorlevel 1 (
    echo.
    echo ⚠️  Rien de nouveau à commiter
    set /p force="Forcer le push quand même? (O/N): "
    if /i not "%force%"=="O" (
        pause
        goto menu
    )
)

echo 🚀 Push vers GitHub...
git push origin main
if errorlevel 1 (
    echo.
    echo ❌ Erreur lors du push!
    echo Vérifiez votre connexion Git et GitHub
    pause
    goto menu
)

echo.
echo ═══════════════════════════════════════
echo ✅ Déploiement réussi!
echo ═══════════════════════════════════════
echo.
echo 🌐 Cloudflare Pages déploie automatiquement...
echo 📍 URL: https://nihonquest.pages.dev
echo ⏱️  Disponible dans 30-60 secondes
echo.
pause
goto menu

:deploy_backend
cls
echo ╔════════════════════════════════════════╗
echo ║   🚀 Déploiement BACKEND               ║
echo ╚════════════════════════════════════════╝
echo.
cd /d "%USERPROFILE%\nihon_quest_backend"
echo 📂 Fichiers modifiés:
git status -s
echo.
set /p msg="Message de commit: "
if "%msg%"=="" (
    echo ❌ Message vide, déploiement annulé
    pause
    goto menu
)

echo.
echo 📤 Ajout des fichiers...
git add .

echo 💾 Commit en cours...
git commit -m "%msg%"
if errorlevel 1 (
    echo.
    echo ⚠️  Rien de nouveau à commiter
    set /p force="Forcer le push quand même? (O/N): "
    if /i not "%force%"=="O" (
        pause
        goto menu
    )
)

echo 🚀 Push vers GitHub...
git push origin main
if errorlevel 1 (
    echo.
    echo ❌ Erreur lors du push!
    echo Vérifiez votre connexion Git et GitHub
    pause
    goto menu
)

echo.
echo ═══════════════════════════════════════
echo ✅ Déploiement réussi!
echo ═══════════════════════════════════════
echo.
echo 🌐 Render redéploie automatiquement...
echo 📍 URL: https://nihon-quest-api.onrender.com
echo ⏱️  Disponible dans 2-5 minutes
echo.
pause
goto menu

:status
cls
echo ╔════════════════════════════════════════╗
echo ║   📊 Status des projets                ║
echo ╚════════════════════════════════════════╝
echo.
echo ═══════════════════════════════════════
echo 🎨 FRONTEND
echo ═══════════════════════════════════════
cd /d "%USERPROFILE%\nihon_quest"
git status
echo.
echo ═══════════════════════════════════════
echo ⚙️  BACKEND
echo ═══════════════════════════════════════
cd /d "%USERPROFILE%\nihon_quest_backend"
git status
echo.
echo ═══════════════════════════════════════
echo 🌐 URLs de production
echo ═══════════════════════════════════════
echo Frontend: https://nihonquest.pages.dev
echo Backend:  https://nihon-quest-api.onrender.com
echo.
pause
goto menu

:open_urls
cls
echo ╔════════════════════════════════════════╗
echo ║   🌐 Ouverture des URLs                ║
echo ╚════════════════════════════════════════╝
echo.
echo Ouverture des pages...
start https://nihonquest.pages.dev
timeout /t 1 >nul
start https://nihon-quest-api.onrender.com
timeout /t 1 >nul
start https://dashboard.render.com
timeout /t 1 >nul
start https://dash.cloudflare.com
echo.
echo ✅ 4 onglets ouverts!
timeout /t 2 >nul
goto menu

:vscode
cls
echo ╔════════════════════════════════════════╗
echo ║   💻 Ouverture VS Code                 ║
echo ╚════════════════════════════════════════╝
echo.
echo Lancement de VS Code...
start code "%USERPROFILE%\nihon_quest"
timeout /t 1 >nul
start code "%USERPROFILE%\nihon_quest_backend"
echo.
echo ✅ 2 fenêtres VS Code lancées!
timeout /t 2 >nul
goto menu

:end
cls
echo ╔════════════════════════════════════════╗
echo ║   👋 Au revoir!                        ║
echo ╚════════════════════════════════════════╝
echo.
echo Merci d'avoir utilisé NihonQuest Launcher
timeout /t 2 >nul
exit