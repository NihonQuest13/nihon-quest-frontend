#!/bin/bash

echo "📋 Variables d'environnement pour Render"
echo "=========================================="
echo ""
echo "Copiez ces variables dans Render Dashboard :"
echo "https://dashboard.render.com → votre service → Environment"
echo ""
echo "----------------------------------------"

cd ~/nihon_quest_backend

if [ ! -f ".env" ]; then
    echo "❌ Fichier .env introuvable"
    exit 1
fi

# Lire et afficher les variables
echo "📝 VOS VARIABLES À COPIER :"
echo ""
echo "=========================================="

while IFS= read -r line; do
    # Ignorer les commentaires et lignes vides
    if [[ ! "$line" =~ ^#.* ]] && [[ -n "$line" ]]; then
        # Extraire le nom et la valeur
        var_name=$(echo "$line" | cut -d'=' -f1)
        var_value=$(echo "$line" | cut -d'=' -f2-)
        
        echo "Nom  : $var_name"
        echo "Valeur : $var_value"
        echo "----------"
    fi
done < .env

echo "=========================================="
echo ""
echo "🔧 ÉTAPES SUR RENDER :"
echo "1. Allez sur https://dashboard.render.com"
echo "2. Cliquez sur votre service backend"
echo "3. Menu de gauche → Environment"
echo "4. Cliquez 'Add Environment Variable'"
echo "5. Pour chaque variable ci-dessus :"
echo "   - Collez le Nom dans 'Key'"
echo "   - Collez la Valeur dans 'Value'"
echo "   - Cliquez 'Add'"
echo "6. Cliquez 'Save Changes' en bas"
echo ""
echo "⚠️  Render va automatiquement redéployer après l'ajout"
echo ""
echo "✅ Une fois terminé, votre backend utilisera Supabase !"