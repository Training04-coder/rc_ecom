# CI/CD — build & déploiement via GitHub Actions (OIDC, sans clé IAM)

Ce dépôt se déploie sur AWS par **GitHub Actions**, avec une authentification
**OIDC GitHub → AWS** : **aucune clé d'accès IAM** n'est stockée dans GitHub.
GitHub présente un jeton OIDC signé, AWS vérifie l'émetteur + les conditions
(`aud` et `sub`) et délivre des identifiants STS temporaires.

```
PR      ──> build + compile-check + terraform plan   (rôle lecture seule)
push master ──> build + plan + apply                 (rôle deploy, env "production")
```

Deux rôles distincts, chacun assumable depuis un seul contexte :

| Rôle                   | Assumable depuis                                   | Droits                              |
|------------------------|----------------------------------------------------|-------------------------------------|
| `github-actions-plan`  | les **pull requests** du dépôt (`sub = …:pull_request`) | lecture seule + lecture du state    |
| `github-actions-deploy`| l'**environnement `production`** (`sub = …:environment:production`) | moindre privilège sur les ressources du projet |

Les deux exigent `aud = sts.amazonaws.com`. **Aucun wildcard `repo:*`.**

---

## Étape 1 — Bootstrap (une seule fois, en local)

Le dossier [`terraform/bootstrap/`](../terraform/bootstrap/) crée le socle de confiance :
fournisseur OIDC, bucket S3 du state (versionné + chiffré + privé) et les deux rôles IAM.
Il a **son propre state local** (il ne peut pas se stocker dans le bucket qu'il crée).

```bash
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars   # ajuste github_org / github_repo / state_bucket_name
terraform init
terraform apply
```

> ⚠️ `terraform apply` ici crée des ressources AWS (OIDC + IAM + bucket de state).
> C'est la **seule** commande `apply` à lancer à la main. Elle est rejouable sans danger.

Récupère les outputs (à reporter dans GitHub à l'étape 3) :

```bash
terraform output
# oidc_provider_arn = "arn:aws:iam::<account>:oidc-provider/token.actions.githubusercontent.com"
# role_plan_arn     = "arn:aws:iam::<account>:role/github-actions-plan"
# role_deploy_arn   = "arn:aws:iam::<account>:role/github-actions-deploy"
# state_bucket      = "lims931-secagent-lab-beautify-tfstate"
```

Variables utiles du bootstrap (voir [`variables.tf`](../terraform/bootstrap/variables.tf)) :

- `github_org` / `github_repo` — défaut `lims931` / `secagent-lab-beautify`.
- `state_bucket_name` — nom **globalement unique** du bucket de state ; vide ⇒ `<org>-<repo>-tfstate`.
- `route53_zone_id` — *(optionnel)* restreint les écritures DNS du rôle deploy à cette seule zone.

---

## Étape 2 — Migrer le state du Terraform principal vers S3 (une seule fois, en local)

Le Terraform principal utilisait un **state local**. [`terraform/backend.tf`](../terraform/backend.tf)
ajoute un backend S3 (configuration **partielle** : le nom du bucket est fourni au `init`).
Migre ton state existant **une fois**, depuis ta machine :

```bash
cd terraform
terraform init -migrate-state -backend-config="bucket=<state_bucket du bootstrap>"
# Terraform propose de copier le state local vers S3 -> répondre "yes"
```

Ensuite, en local comme en CI, le `init` se fait toujours avec le même `-backend-config`.
Si tu n'as encore **jamais** appliqué le Terraform principal, saute la migration :
un simple `terraform init -backend-config="bucket=…"` suffit.

---

## Étape 3 — Variables GitHub

GitHub → **Settings → Secrets and variables → Actions → onglet _Variables_** (ce sont
des **Variables**, pas des Secrets : ce ne sont que des ARN et un domaine, rien de sensible).

| Variable             | Valeur                                             |
|----------------------|----------------------------------------------------|
| `AWS_ROLE_ARN_PLAN`  | output `role_plan_arn` du bootstrap                |
| `AWS_ROLE_ARN_DEPLOY`| output `role_deploy_arn` du bootstrap              |
| `TF_STATE_BUCKET`    | output `state_bucket` du bootstrap                 |
| `TF_DOMAIN_NAME`     | ta zone Route 53 publique (ex. `mondomaine.click`) |
| `TF_SUBDOMAIN`       | *(optionnel)* sous-domaine, défaut `app`           |

> Le workflow ne force **jamais** `demo_vuln` : il reste à `false` (défaut). Ne jamais
> activer la XSS de démo via la CI.

---

## Étape 4 — Environnement `production` avec required reviewers

GitHub → **Settings → Environments → New environment → `production`**, puis :

- **Required reviewers** : ajoute-toi (et/ou l'équipe). Chaque `apply` sera **mis en pause
  en attente d'approbation**.
- *(Optionnel)* **Deployment branches** : limiter à `master`.

Ce nom `production` est **doublement** structurant :
1. il déclenche l'approbation manuelle avant l'`apply` ;
2. il conditionne la confiance OIDC du rôle deploy (`sub = …:environment:production`).
   Si tu renommes l'environnement, mets à jour `github_environment` dans le bootstrap et réapplique-le.

---

## Étape 5 — Supprimer les anciennes clés d'accès IAM

Si un déploiement manuel utilisait auparavant une clé d'accès IAM (`aws configure`,
secret GitHub `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`, etc.), **supprime-les** :
l'OIDC les rend inutiles et une clé longue durée est le principal risque à éliminer.

- GitHub : **Settings → Secrets** → supprimer tout secret `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`.
- AWS : **IAM → Users → <ton user CI> → Security credentials** → désactiver puis supprimer les access keys devenues inutiles.

---

## Comportement du pipeline

Workflow : [`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml).
`permissions: id-token: write, contents: read, pull-requests: write`.

- **Sur une pull request** : job `build` (compile-check `javac` + artefact), puis job `plan`
  (rôle **plan**, `fmt -check`, `validate`, `plan -lock=false`) ; le résumé du plan est posté
  **en commentaire de la PR** (mis à jour à chaque push).
- **Sur un push vers `master`** : job `build`, puis job `deploy` (environnement `production`,
  donc **approbation requise**) qui refait `plan` puis **`apply`** avec le rôle **deploy**.

### Détails utiles

- **Build** : l'appli est un *single-file* Java lancé en source-launcher (`java App.java`),
  **sans Maven/Gradle ni tests**. Le job build fait donc un **compile-check** (`javac`) ;
  l'artefact `app-source` est fourni par conformité mais **n'est pas consommé** par le déploiement
  (le code part vers S3 via Terraform, qui lit directement les fichiers du dépôt).
- **Actions épinglées** : toutes les actions sont figées à un **SHA de commit** (le tag est en
  commentaire), pour éviter qu'un tag mutable change le code exécuté.
- **Branche `master` vs `main`** : la branche par défaut du dépôt est **`master`**. Le workflow
  cible `master` (push + `if` du job deploy). Si tu renommes en `main`, modifie ces deux endroits.

---

## Rappel moindre privilège (rôle deploy)

La politique du rôle deploy ([`terraform/bootstrap/main.tf`](../terraform/bootstrap/main.tf)) est
construite à partir des ressources réellement gérées : EC2/SG/EIP, IAM (uniquement le rôle et
l'instance-profile du projet, `PassRole` restreint à EC2), S3 (bucket app + state), CloudWatch
Logs (le seul log group `/bricoshop/app`), Route 53 (lecture + `ChangeResourceRecordSets`), SSM
GetParameter (AMI). **Pas d'`AdministratorAccess`.** Si tu ajoutes une ressource au Terraform
principal, étends cette politique en conséquence puis réapplique le bootstrap.
