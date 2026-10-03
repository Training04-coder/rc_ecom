# Projet : BricoShop — site e-commerce de démo pour formation

## Contexte
- Site de TRAINING, pas de production. Objectif final : générer des logs riches,
  les envoyer dans AWS CloudWatch et démontrer les fonctionnalités IA de CloudWatch
  (Logs Insights en langage naturel, patterns, détection d'anomalies, investigations).
- Stack : Java (une seule classe principale), infra Terraform (un seul fichier), EC2.

## Règles de code
- MINIMUM de code. Pas de framework supplémentaire sans me demander.
- Garder une seule classe Java tant que c'est raisonnable ; HTML/CSS/JS en ressources statiques.
- Pas de base de données : stockage en mémoire (Map) pour utilisateurs, produits, paniers.
- Pas de sur-ingénierie : pas d'interfaces, pas de couches inutiles.
- Ne jamais modifier le DNS ni l'endpoint existant dans Terraform sans me le demander.

## Règles de logging (OBLIGATOIRES pour toute nouvelle fonctionnalité)
- Chaque action utilisateur ET chaque requête HTTP produit un log.
- Format : une ligne JSON par événement, sur stdout ET dans /var/log/bricoshop/app.log.
- Voir le skill `structured-logging` pour le schéma exact.
- Ne JAMAIS logger un mot de passe en clair.

## Workflow
- Avant de coder : proposer un plan court et attendre ma validation.
- Après chaque modification : compiler, lancer l'appli, tester avec curl,
  et me montrer 3 exemples de logs produits.
- Une fonctionnalité = un commit git avec un message clair.