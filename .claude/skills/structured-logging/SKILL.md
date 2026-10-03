---
name: structured-logging
description: Convention de logs JSON du projet BricoShop. À utiliser chaque fois qu'on ajoute ou modifie une fonctionnalité, un endpoint ou une gestion d'erreur.
---

# Schéma de log (une ligne JSON par événement)

Champs communs :
- timestamp (ISO-8601 UTC), level (INFO|WARN|ERROR), event (snake_case)
- requestId (UUID par requête), sessionId, userId (ou "anonymous")
- ip, userAgent, method, path, status, durationMs

Champs métier selon l'événement : productId, productName, quantity,
cartTotal, cartSize, reason (pour les échecs), errorType, stackTrace (si ERROR)

# Catalogue d'événements
http_request, page_view, signup_success, signup_failed, login_success,
login_failed, logout, product_view, cart_add, cart_remove, cart_view,
checkout_started, checkout_success, checkout_failed, app_error, app_startup

# Règles
- level WARN pour les échecs métier (login_failed), ERROR pour les exceptions.
- Toujours un champ `reason` explicite en cas d'échec (ex: "wrong_password", "user_not_found").
- Jamais de mot de passe, jamais de token complet.
- Logger durationMs pour pouvoir détecter des lenteurs.