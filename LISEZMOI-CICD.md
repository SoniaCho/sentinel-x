# Pipeline CI/CD Sentinel-X : où copier chaque fichier

Copiez ces fichiers à la racine de votre dépôt (en gardant les dossiers) :

| Fichier | Rôle |
|---|---|
| `.github/workflows/ci-cd.yml` | Le pipeline (5 tests + déploiement sur le Pi) |
| `tests/telemetry.test.ts` | Test 1 : tests unitaires de `lib/telemetry.ts` |
| `tests/mqtt_tls_test.sh` | Test 3 : broker Mosquitto (TLS, comptes, ACL) |
| `tests/smoke_dashboard.sh` | Test 4 : conteneur + API du dashboard |
| `app/api/health/route.ts` | **Nouvelle route** `/api/health` (smoke test et déploiement) |
| `package.json`, `tsconfig.json` | Versions modifiées : scripts `test` et `typecheck`, option `allowImportingTsExtensions` |

## Installer le runner sur le Raspberry Pi (une seule fois)
1. GitHub > Settings > Actions > Runners > New self-hosted runner > **Linux / ARM64**, puis copiez les commandes dans le terminal du Pi, **avec l'utilisateur qui possède ~/sentinel-x**.
2. Service : `sudo ./svc.sh install && sudo ./svc.sh start`
3. `sudo apt install -y rsync` et vérifier que l'utilisateur est dans le groupe docker.
4. Autoriser le redémarrage de la caméra sans mot de passe :
   `echo "$USER ALL=(root) NOPASSWD: /usr/bin/systemctl restart sentinel-vision" | sudo tee /etc/sudoers.d/sentinel-deploy`
5. Gardez le dépôt **privé** (le runner exécute du code venant de GitHub).
