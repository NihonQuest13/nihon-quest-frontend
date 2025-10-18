#!/bin/bash

echo "☢️  NETTOYAGE COMPLET DU PROJET"
echo "================================"
echo ""
echo "⚠️  ATTENTION : Ceci va supprimer TOUT l'historique Git !"
echo "Voulez-vous continuer ? (o/n)"
read -r response

if [[ ! "$response" =~ ^[Oo]$ ]]; then
    echo "❌ Annulé"
    exit 1
fi

echo ""
echo "🗑️  ÉTAPE 1/7 : Suppression de tous les dossiers .git..."
rm -rf .git .git_old
echo "✅ .git supprimé"

echo ""
echo "🗑️  ÉTAPE 2/7 : Suppression des fichiers volumineux..."
# Supprimer tous les exe
find . -name "*.exe" -type f -delete 2>/dev/null
# Supprimer les archives
find . \( -name "*.zip" -o -name "*.tar.gz" -o -name "*.rar" \) -type f -delete 2>/dev/null
# Supprimer les APK/IPA
find . \( -name "*.apk" -o -name "*.ipa" -o -name "*.aab" \) -type f -delete 2>/dev/null
echo "✅ Fichiers volumineux supprimés"

echo ""
echo "🗑️  ÉTAPE 3/7 : Suppression des dossiers de build..."
rm -rf build/ dist/ release/ installers/ out/
rm -rf android/app/build/ android/.gradle/
rm -rf ios/build/ ios/Pods/
rm -rf windows/build/
rm -rf linux/build/
rm -rf macos/build/
rm -rf web/build/
rm -rf .dart_tool/
rm -rf .flutter-plugins .flutter-plugins-dependencies
echo "✅ Dossiers de build supprimés"

echo ""
echo "🗑️  ÉTAPE 4/7 : Suppression des artefacts Nuitka/Python..."
find . -name "*.build" -type d -exec rm -rf {} + 2>/dev/null
find . -name "*.dist" -type d -exec rm -rf {} + 2>/dev/null
find . -name "*.onefile-build" -type d -exec rm -rf {} + 2>/dev/null
find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null
find . -name "*.pyc" -type f -delete 2>/dev/null
echo "✅ Artefacts Python supprimés"

echo ""
echo "🧹 ÉTAPE 5/7 : Nettoyage Flutter..."
flutter clean
echo "✅ Flutter clean terminé"

echo ""
echo "📄 ÉTAPE 6/7 : Création du .gitignore..."
cat > .gitignore << 'EOF'
# Compiled files
*.exe
*.msi
*.dmg
*.apk
*.ipa
*.aab

# Build directories
build/
dist/
release/
installers/
out/
*.build/
*.dist/
*.onefile-build/

# Flutter/Dart
.dart_tool/
.flutter-plugins
.flutter-plugins-dependencies
.packages
.pub-cache/
.pub/

# Android
android/app/debug
android/app/profile
android/app/release
android/.gradle/
android/app/build/
*.jks

# iOS
ios/build/
ios/Pods/
ios/.symlinks/
*.pbxuser
*.mode1v3
*.mode2v3
*.perspectivev3
*.hmap
*.ipa

# IDE
.idea/
.vscode/
*.iml
*.ipr
*.iws
*.swp

# Python
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
venv/
ENV/

# Logs
*.log
npm-debug.log*

# OS
.DS_Store
Thumbs.db
desktop.ini

# Misc
.env
.env.local
node_modules/
coverage/
*.tmp
*.temp
EOF
echo "✅ .gitignore créé"

echo ""
echo "🎯 ÉTAPE 7/7 : Initialisation du nouveau dépôt Git..."
git init
git add .
git commit -m "Initial commit - clean project"
git remote add origin https://github.com/NihonQuest13/nihon-quest-frontend.git
echo "✅ Nouveau dépôt Git créé"

echo ""
echo "================================"
echo "✅ NETTOYAGE TERMINÉ !"
echo "================================"
echo ""

echo "📊 Taille du projet :"
du -sh .

echo ""
echo "📊 Taille du dépôt Git :"
git count-objects -vH

echo ""
echo "📁 Vérification des gros fichiers restants (> 10MB) :"
large_files=$(find . -type f -size +10M -not -path "./.git/*" 2>/dev/null)
if [ -z "$large_files" ]; then
    echo "✅ Aucun fichier volumineux trouvé !"
else
    echo "⚠️  Fichiers volumineux détectés :"
    find . -type f -size +10M -not -path "./.git/*" -exec ls -lh {} \;
fi

echo ""
echo "🚀 Prochaine étape :"
echo "   git push -u origin main --force"
echo ""
echo "⚠️  Cela va remplacer complètement le dépôt sur GitHub"