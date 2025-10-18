# launcher.py
# Ce script est la porte d'entrée de l'application, compilé en NihonQuest.exe.
# VERSION CORRIGÉE : Ajout de la définition du répertoire de travail pour le backend.

import subprocess
import sys
import os
import logging
import time
from pathlib import Path

# --- Configuration des chemins ---
# Détermine le répertoire de base de l'application, que ce soit en mode compilé ou en développement.
if getattr(sys, 'frozen', False):
    # Si l'application est compilée (par PyInstaller), BASE_DIR est le répertoire de l'exécutable.
    BASE_DIR = Path(sys.executable).parent
else:
    # Si c'est en mode développement, BASE_DIR est le répertoire du script launcher.py.
    BASE_DIR = Path(__file__).parent

# --- Configuration de la journalisation (Logging) ---
# Les logs du lanceur seront écrits dans 'launcher.log' à côté de NihonQuest.exe.
log_file_path = BASE_DIR / "launcher.log"
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - LAUNCHER - %(levelname)s - %(message)s",
    handlers=[
        logging.FileHandler(log_file_path, encoding='utf-8'),
        logging.StreamHandler(sys.stdout) # Afficher aussi dans la console pour le debug
    ]
)

# --- Définition des chemins relatifs vers les exécutables ---
# On suppose qu'ils sont dans des sous-dossiers pour une meilleure organisation.
BACKEND_EXE_PATH = BASE_DIR / "backend" / "backend_service.exe"
FRONTEND_EXE_PATH = BASE_DIR / "flutter" / "nihon_quest.exe"

def main():
    """
    Fonction principale qui orchestre le lancement et l'arrêt des processus 
    du backend et du frontend.
    """
    logging.info("Démarrage du lanceur Nihon Quest...")

    backend_process = None
    frontend_process = None

    try:
        # --- Étape 1: Démarrage du Backend ---
        if not BACKEND_EXE_PATH.exists():
            logging.error(f"Erreur: Le fichier du backend n'a pas été trouvé à: {BACKEND_EXE_PATH}")
            sys.exit(1)

        # --- MODIFICATION CRUCIALE ---
        # On définit explicitement le répertoire de travail (cwd) du backend.
        # C'est le dossier où se trouve backend_service.exe.
        # Cela garantit que les logs et le dossier 'storage' sont créés au bon endroit.
        backend_working_directory = BACKEND_EXE_PATH.parent
        logging.info(f"Définition du répertoire de travail du backend à : {backend_working_directory}")
        # --- FIN DE LA MODIFICATION ---

        logging.info(f"Démarrage du backend depuis: {BACKEND_EXE_PATH}")
        
        backend_process = subprocess.Popen(
            [str(BACKEND_EXE_PATH)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            # --- AJOUT DE L'ARGUMENT 'cwd' ---
            cwd=str(backend_working_directory),
            # ---------------------------------
            # Cache la fenêtre de console du backend sur Windows
            creationflags=subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0
        )
        logging.info(f"Backend démarré avec PID: {backend_process.pid}")

        # Laisser un peu de temps au backend pour s'initialiser.
        # Une vérification de port serait plus robuste, mais ceci est simple et efficace.
        time.sleep(5)
        logging.info("Attente de 5 secondes pour le démarrage du backend terminée.")

        # --- Étape 2: Démarrage du Frontend ---
        if not FRONTEND_EXE_PATH.exists():
            logging.error(f"Erreur: Le fichier du frontend n'a pas été trouvé à: {FRONTEND_EXE_PATH}")
            sys.exit(1)

        logging.info(f"Démarrage du frontend depuis: {FRONTEND_EXE_PATH}")
        frontend_process = subprocess.Popen(
            [str(FRONTEND_EXE_PATH)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        logging.info(f"Frontend démarré avec PID: {frontend_process.pid}")

        # Le lanceur attend que l'utilisateur ferme la fenêtre du frontend.
        logging.info("Le lanceur attend la fermeture du frontend...")
        frontend_process.wait()
        logging.info(f"Le frontend s'est fermé avec le code de sortie : {frontend_process.returncode}")

    except Exception as e:
        logging.error(f"Une erreur inattendue est survenue dans le lanceur : {e}", exc_info=True)
    finally:
        # --- Étape 3: Nettoyage des processus ---
        # Cette partie s'exécute toujours, assurant que le backend est bien fermé
        # quand le frontend se ferme.
        
        # On vérifie si le frontend est toujours actif (au cas où)
        if frontend_process and frontend_process.poll() is None:
            logging.info(f"Le frontend est toujours actif (PID: {frontend_process.pid}), tentative de terminaison...")
            frontend_process.terminate()
            try:
                frontend_process.wait(timeout=5)
                logging.info("Processus frontend terminé proprement.")
            except subprocess.TimeoutExpired:
                logging.warning("Le frontend n'a pas répondu, forçage de l'arrêt...")
                frontend_process.kill()

        # On arrête le backend
        if backend_process and backend_process.poll() is None:
            logging.info(f"Le frontend est fermé, arrêt du backend (PID: {backend_process.pid})...")
            backend_process.terminate() # Envoie un signal de terminaison propre
            try:
                backend_process.wait(timeout=5)
                logging.info("Processus backend terminé proprement.")
            except subprocess.TimeoutExpired:
                logging.warning("Le backend n'a pas répondu, forçage de l'arrêt...")
                backend_process.kill()
                logging.info("Processus backend tué.")
        
        logging.info("Le lanceur a terminé son exécution.")

if __name__ == "__main__":
    main()
