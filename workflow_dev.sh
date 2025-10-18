#!/bin/bash

# ========================================
# CONFIGURATION NIHONQUEST
# ========================================

BACKEND_REPO="https://github.com/NihonQuest13/nihon-quest-backend"
FRONTEND_URL="https://nihonquest.nathangrondin681.workers.dev"
BACKEND_URL="https://nihon-quest-api.onrender.com"

# ========================================
# SETUP INITIAL
# ========================================

initial_setup() {
    echo "🏗️  Configuration initiale de NihonQuest"
    echo ""
    
    # Clone du backend
    cd ~
    if [ ! -d "nihon_quest_backend" ]; then
        echo "📦 Clonage du backend..."
        git clone $BACKEND_REPO nihon_quest_backend
        echo "✅ Backend cloné"
    else
        echo "✅ Backend déjà présent"
    fi
    
    # Configuration Frontend
    echo ""
    echo "🎨 Configuration du FRONTEND..."
    cd ~/nihon_quest
    
    cat > .env << EOF
# API Backend URL
API_BASE_URL=$BACKEND_URL

# Environment
FLUTTER_ENV=production
EOF
    
    # Ajouter .env au .gitignore si pas déjà fait
    if ! grep -q "^.env$" .gitignore 2>/dev/null; then
        echo ".env" >> .gitignore
    fi
    
    echo "✅ Frontend configuré (.env créé)"
    
    # Configuration Backend
    echo ""
    echo "⚙️  Configuration du BACKEND..."
    cd ~/nihon_quest_backend
    
    cat > .env << EOF
# Frontend URL
FRONTEND_URL=$FRONTEND_URL

# CORS Configuration
CORS_ORIGINS=$FRONTEND_URL,http://localhost:3000,http://localhost:8080

# Environment
ENVIRONMENT=production

# Database (à compléter)
DATABASE_URL=your_database_url_here

# Secret Keys (à compléter)
SECRET_KEY=your_secret_key_here
JWT_SECRET=your_jwt_secret_here
EOF
    
    # Ajouter .env au .gitignore si pas déjà fait
    if ! grep -q "^.env$" .gitignore 2>/dev/null; then
        echo ".env" >> .gitignore
    fi
    
    echo "✅ Backend configuré (.env créé)"
    echo ""
    echo "⚠️  N'oubliez pas de compléter les variables sensibles dans:"
    echo "   ~/nihon_quest_backend/.env"
    echo ""
    echo "📊 Structure finale:"
    echo "   ~/nihon_quest/          → Frontend (Flutter)"
    echo "   ~/nihon_quest_backend/  → Backend (API)"
    echo ""
    echo "🌐 URLs de production:"
    echo "   Frontend: $FRONTEND_URL"
    echo "   Backend:  $BACKEND_URL"
}

# ========================================
# WORKFLOW FRONTEND
# ========================================

work_on_frontend() {
    echo "🎨 Travail sur le FRONTEND"
    echo ""
    cd ~/nihon_quest
    
    echo "📝 Que voulez-vous faire ?"
    echo "1) Lancer le dev local (flutter run)"
    echo "2) Build pour le web"
    echo "3) Commit et push (déploie sur Cloudflare)"
    echo "4) Retour au menu"
    echo ""
    read -p "Choix (1-4): " choice
    
    case $choice in
        1)
            echo "🚀 Lancement du serveur de développement..."
            flutter run -d chrome
            ;;
        2)
            echo "🔨 Build Flutter Web..."
            flutter build web
            echo "✅ Build terminé dans build/web/"
            ;;
        3)
            read -p "Message de commit: " msg
            git add .
            git commit -m "$msg"
            git push origin main
            echo "✅ Pushed! Cloudflare déploie automatiquement..."
            echo "🌐 Vérifiez: $FRONTEND_URL"
            ;;
        4)
            return
            ;;
    esac
}

# ========================================
# WORKFLOW BACKEND
# ========================================

work_on_backend() {
    echo "⚙️  Travail sur le BACKEND"
    echo ""
    cd ~/nihon_quest_backend
    
    echo "📝 Que voulez-vous faire ?"
    echo "1) Lancer le dev local"
    echo "2) Test des endpoints"
    echo "3) Commit et push (déploie sur Render)"
    echo "4) Retour au menu"
    echo ""
    read -p "Choix (1-4): " choice
    
    case $choice in
        1)
            echo "🚀 Lancement du serveur local..."
            if [ -f "requirements.txt" ]; then
                pip install -r requirements.txt
            fi
            python app.py || python main.py || python server.py
            ;;
        2)
            echo "🧪 Test de l'API..."
            curl $BACKEND_URL/health || curl $BACKEND_URL/
            ;;
        3)
            read -p "Message de commit: " msg
            git add .
            git commit -m "$msg"
            git push origin main
            echo "✅ Pushed! Render redéploie automatiquement..."
            echo "🌐 Vérifiez: $BACKEND_URL"
            ;;
        4)
            return
            ;;
    esac
}

# ========================================
# WORKFLOW FULLSTACK
# ========================================

work_on_both() {
    echo "🔄 Workflow FULLSTACK"
    echo ""
    echo "Ordre recommandé:"
    echo "1. Modifier le BACKEND d'abord"
    echo "2. Déployer le backend"
    echo "3. Modifier le FRONTEND pour utiliser les nouveaux endpoints"
    echo "4. Déployer le frontend"
    echo ""
    read -p "Appuyez sur Entrée pour commencer..."
    
    # Backend
    echo ""
    echo "========== BACKEND =========="
    cd ~/nihon_quest_backend
    echo "📂 Vous êtes dans: $(pwd)"
    echo "Faites vos modifications au backend..."
    read -p "Appuyez sur Entrée quand prêt à commit..."
    
    read -p "Message de commit backend: " backend_msg
    git add .
    git commit -m "$backend_msg"
    git push origin main
    echo "✅ Backend pushed!"
    
    # Attendre confirmation déploiement
    echo ""
    echo "⏳ Attendez le déploiement Render (2-5 min)..."
    read -p "Appuyez sur Entrée quand le backend est déployé..."
    
    # Frontend
    echo ""
    echo "========== FRONTEND =========="
    cd ~/nihon_quest
    echo "📂 Vous êtes dans: $(pwd)"
    echo "Faites vos modifications au frontend..."
    read -p "Appuyez sur Entrée quand prêt à commit..."
    
    read -p "Message de commit frontend: " frontend_msg
    git add .
    git commit -m "$frontend_msg"
    git push origin main
    echo "✅ Frontend pushed!"
    
    echo ""
    echo "🎉 Déploiements lancés!"
    echo "Frontend: $FRONTEND_URL"
    echo "Backend:  $BACKEND_URL"
}

# ========================================
# VÉRIFICATION STATUS
# ========================================

check_status() {
    echo "📊 Status des projets"
    echo ""
    
    echo "========== FRONTEND =========="
    cd ~/nihon_quest
    echo "📂 $(pwd)"
    git status -s
    echo ""
    
    echo "========== BACKEND =========="
    cd ~/nihon_quest_backend 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "📂 $(pwd)"
        git status -s
    else
        echo "❌ Backend pas encore cloné (lancez l'option 4)"
    fi
    echo ""
    
    echo "🌐 URLs de production:"
    echo "   Frontend: $FRONTEND_URL"
    echo "   Backend:  $BACKEND_URL"
}

# ========================================
# MENU PRINCIPAL
# ========================================

main_menu() {
    while true; do
        clear
        echo "================================"
        echo "🎮 NihonQuest - Workflow Dev"
        echo "================================"
        echo ""
        echo "1) 🎨 Travailler sur le FRONTEND"
        echo "2) ⚙️  Travailler sur le BACKEND"
        echo "3) 🔄 Travailler sur les DEUX (fullstack)"
        echo "4) 🏗️  Configuration initiale"
        echo "5) 📊 Vérifier le status"
        echo "6) ❌ Quitter"
        echo ""
        read -p "Choix (1-6): " choice
        
        case $choice in
            1) work_on_frontend ;;
            2) work_on_backend ;;
            3) work_on_both ;;
            4) initial_setup ;;
            5) check_status ;;
            6) echo "👋 Au revoir!"; exit 0 ;;
            *) echo "❌ Choix invalide" ;;
        esac
        
        echo ""
        read -p "Appuyez sur Entrée pour continuer..."
    done
}

# Lancer le menu
main_menu