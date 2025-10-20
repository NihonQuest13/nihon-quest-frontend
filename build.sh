#!/bin/bash
set -e

echo "🔵 Installation de Flutter..."
git clone https://github.com/flutter/flutter.git -b stable --depth 1
export PATH="$PATH:`pwd`/flutter/bin"

echo "✅ Flutter installé"
flutter --version

echo "🔵 Build Web..."
flutter clean
flutter pub get
flutter build web --release --web-renderer canvaskit

echo "✅ Build terminé !"