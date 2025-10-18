#!/bin/bash

echo "🧹 Nettoyage du projet Flutter..."

# 1. Nettoyer Flutter
echo "📦 Nettoyage des caches Flutter..."
flutter clean

# 2. Supprimer les builds
echo "🗑️ Suppression des dossiers de build..."
rm -rf build/
rm -rf .dart_tool/
rm -rf .flutter-plugins
rm -rf .flutter-plugins-dependencies

# 3. Supprimer les fichiers exe et installateurs
echo "🚫 Suppression des fichiers .exe..."
find . -name "*.exe" -type f -delete
rm -rf installers/
rm -rf release/

# 4. Supprimer les fichiers Nuitka
echo "🐍 Suppression des artefacts Nuitka..."
rm -rf *.build
rm -rf *.dist
rm -rf *.onefile-build
find . -name "*.pyi" -type f -delete
find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null

# 5. Supprimer les logs et temporaires
echo "📝 Suppression des fichiers temporaires..."
find . -name "*.log" -type f -delete
find . -name "*.tmp" -type f -delete
find . -name ".DS_Store" -type f -delete
rm -rf tmp/
rm -rf temp/

# 6. Supprimer les node_modules si présents
if [ -d "node_modules" ]; then
    echo "📦 Suppression de node_modules..."
    rm -rf node_modules/
fi

# 7. Supprimer les fichiers de couverture et tests
echo "🧪 Suppression des fichiers de test..."
rm -rf coverage/
rm -rf test_results/

# 8. Afficher la taille du projet
echo ""
echo "✅ Nettoyage terminé!"
echo ""
echo "📊 Taille actuelle du projet:"
du -sh .
echo ""
echo "📁 Principaux dossiers:"
du -sh */ 2>/dev/null | sort -hr | head -10

echo ""
echo "💡 N'oubliez pas de créer/mettre à jour votre .gitignore!"