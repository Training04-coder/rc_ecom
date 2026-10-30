# Déployer BricoShop avec GitHub Actions (fiche participant)

Chaque participant déploie **sa propre copie** du site, dans **son compte AWS**, depuis
**son dépôt GitHub**, sur **son nom de domaine**. Aucune clé d'accès AWS n'est stockée
dans GitHub : le pipeline s'authentifie par **OIDC** (identifiants temporaires).

```
pull request      ──> build + terraform plan   (rôle rch-github-actions-plan, lecture seule)
push branche par défaut ──> build + destroy + plan + apply (rôle rch-github-actions-deploy, après approbation)
```

**Tu ne renseignes tes valeurs qu'à deux endroits** : un fichier `terraform.tfvars` sur ta
machine, et 1 variable (`AWS_ACCOUNT_ID`) dans GitHub. Région (`eu-west-1`), initiales (`rch`,
préfixe de chaque nom de ressource), domaine (`alpha-awslab26.click`) et sous-domaine (`rch`)
sont forcés dans le code.

---

## Prérequis

| Quoi | Vérification |
|---|---|
| Un compte AWS avec des droits admin, configuré en local | `aws sts get-caller-identity` répond |
| Terraform **≥ 1.10** | `terraform version` |
| Une **zone hébergée publique Route 53** dans **ce même compte** AWS | Route 53 → Hosted zones |
| Un compte GitHub | — |

Pas encore de domaine ? Route 53 → *Registered domains* → *Register* (un `.click` coûte
quelques $/an, la zone est créée automatiquement). Domaine chez un autre registrar ? Créer la
hosted zone dans Route 53 et recopier ses 4 serveurs NS chez le registrar.

---

## 1. Copier le dépôt sur ton compte GitHub

*Fork* (ou *Use this template*) du dépôt du formateur vers ton compte. Note le **nom de ton
compte** et le **nom du dépôt** : `https://github.com/<github_owner>/<github_repo>`.

```bash
git clone https://github.com/<github_owner>/<github_repo>.git
cd <github_repo>
```

## 2. Renseigner ta configuration

```bash
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars
```

Édite `terraform.tfvars` :

```hcl
aws_region   = "eu-west-1"             # forcée
initials     = "rch"                   # préfixe de chaque nom de ressource
github_owner = "participant-42"        # ton compte GitHub
github_repo  = "bricoshop"             # ton dépôt
domain_name  = "alpha-awslab26.click"  # zone Route 53 existante
subdomain    = "rch"                   # => https://rch.alpha-awslab26.click
```

## 3. Lancer le bootstrap (une seule fois)

```bash
terraform init
terraform apply      # répondre "yes"
```

Il crée dans **ton** compte AWS : la confiance OIDC avec GitHub, le bucket du state Terraform
(`rch-bricoshop-tfstate-<account_id>`) et les deux rôles IAM du pipeline
(`rch-github-actions-plan`, `rch-github-actions-deploy`). Il vérifie aussi que ta zone Route 53
existe.

À la fin, il affiche ce qu'il faut recopier dans GitHub :

```
github_environment = "production"
github_variables = {
  "AWS_ACCOUNT_ID" = "123456789012"
}
site_url = "https://rch.alpha-awslab26.click"
```

(Pour le réafficher plus tard : `terraform output`.)

## 4. Configurer GitHub

Dans ton dépôt GitHub :

**a) Variables** — *Settings → Secrets and variables → Actions → onglet **Variables** →
New repository variable*. Crée la variable `AWS_ACCOUNT_ID` de `github_variables`, avec
**exactement** ce nom et cette valeur. C'est une *Variable*, pas un *Secret* : rien de sensible.

**b) Environnement** — *Settings → Environments → New environment* → nom **`production`**
(exactement). Coche **Required reviewers** et ajoute-toi : chaque déploiement attendra ton
approbation.

**c) Actions** — sur un fork, ouvre l'onglet **Actions** et clique *I understand… enable
workflows* (GitHub désactive les workflows des forks par défaut).

## 5. Déployer

Pousse un commit sur la branche par défaut (ou *Actions → build-and-deploy → Run workflow*) :

```bash
git commit --allow-empty -m "Premier déploiement"
git push
```

Dans l'onglet **Actions**, le job `deploy` attend ton approbation (*Review deployments →
Approve*), puis lance `terraform destroy` sur la stack principale (`terraform/` uniquement, le
bootstrap n'est jamais touché ; au premier run le state est vide et rien n'est détruit), puis
`terraform plan` et `terraform apply`. Pour sauter le destroy : *Actions → build-and-deploy →
Run workflow* avec `destroy_before_apply` = false. Le résumé du run affiche l'URL du site. Le
HTTPS est disponible **1 à 3 min** après l'apply, le temps d'obtenir le certificat Let's Encrypt.

> **Attention** : le destroy supprime aussi le bucket de l'appli, donc la sauvegarde des
> certificats Caddy. Chaque déploiement redemande un certificat Let's Encrypt (limite de 5 par
> semaine pour le même nom) et coupe le site quelques minutes.

```bash
curl https://rch.alpha-awslab26.click/health
```

Ensuite : toute **pull request** affiche le `terraform plan` en commentaire ; tout **merge** sur
la branche par défaut redéploie.

---

## Dépannage

| Symptôme | Cause / correction |
|---|---|
| Job build : `Variable GitHub … manquante` | Étape 4a incomplète ou nom de variable mal orthographié. |
| `bootstrap apply` : `EntityAlreadyExists … token.actions.githubusercontent.com` | Le compte a déjà un fournisseur OIDC GitHub (cas habituel d'un compte de formation partagé). Ajouter `create_oidc_provider = false` dans `terraform.tfvars` et relancer. |
| `Invalid value for variable` sur `aws_region` | La région est forcée à `eu-west-1` : retirer toute autre valeur de `terraform.tfvars`. |
| `bootstrap apply` : `no matching Route 53 Hosted Zone found` | `domain_name` ne correspond à aucune zone publique de ce compte AWS. |
| `bootstrap apply` : `BucketAlreadyExists` | Rarissime (nom basé sur l'ID du compte). Vérifier qu'on est sur le bon compte AWS. |
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | `github_owner` / `github_repo` du tfvars ≠ dépôt réel (attention à la casse), ou environnement GitHub pas nommé exactement `production`. Corriger puis relancer `terraform apply` dans le bootstrap. |
| Le job `deploy` ne se lance pas après un push | Le push n'est pas sur la branche par défaut du dépôt, ou le workflow est désactivé (fork : étape 4c). |
| Le site ne répond pas en HTTPS | Attendre 3 min. Puis vérifier que les NS du domaine pointent bien vers la zone Route 53. |

---

## Lancer Terraform depuis sa machine (facultatif)

Le pipeline suffit. Pour travailler en local sur le même state que la CI :

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # mêmes initials / domain_name / subdomain / aws_region
terraform init -backend-config="bucket=rch-bricoshop-tfstate-<account_id>"
```

La commande `init` exacte est donnée par `terraform output local_init_command` dans
`terraform/bootstrap`. Le state est verrouillé (lockfile S3) : pas de risque de conflit avec un
run CI en cours.

> **Formateur — infra déjà déployée avec un state local ?** Ajoute `-migrate-state` à la
> commande `init` ci-dessus, une seule fois, pour envoyer ton state existant dans le bucket.

---

## Nettoyage en fin de formation

Dans cet ordre (le state du site est dans le bucket que supprime le bootstrap) :

```bash
cd terraform            && terraform destroy   # le site (après l'init ci-dessus)
cd terraform/bootstrap  && terraform destroy   # OIDC, rôles, bucket de state
```

Puis, si un ancien déploiement utilisait des **clés d'accès IAM** (`aws configure` d'un user
CI, secrets `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` dans GitHub) : les supprimer
(*GitHub → Settings → Secrets* et *IAM → Users → Security credentials*). L'OIDC les rend
inutiles.

---

## Pour le formateur : ce qui est figé dans le code

Ces noms sont des **conventions partagées** entre [`terraform/bootstrap/main.tf`](../terraform/bootstrap/main.tf)
et [`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml). Ils sont identiques dans
chaque compte, c'est ce qui permet de n'avoir qu'une variable :

| Convention | Valeur |
|---|---|
| Initiales | `rch` (variable `initials` des deux stacks + valeurs en dur dans le workflow + clé du state) |
| Région | `eu-west-1` (validation des variables `aws_region` + `backend.tf` + workflow) |
| Domaine / sous-domaine | `alpha-awslab26.click` / `rch` (=> `rch.alpha-awslab26.click`) |
| Rôles IAM | `rch-github-actions-plan`, `rch-github-actions-deploy` |
| Bucket de state | `rch-bricoshop-tfstate-<account_id>` |
| Clé du state | `rch-bricoshop/terraform.tfstate` ([`terraform/backend.tf`](../terraform/backend.tf)) |
| Environnement GitHub | `production` |
| Version Terraform en CI | `TF_VERSION` dans le workflow |

Sécurité : le rôle plan n'est assumable que depuis une **pull request** du dépôt du participant,
le rôle deploy que depuis son environnement **`production`** (conditions `sub` exactes + `aud =
sts.amazonaws.com`, jamais `repo:*`). Le rôle deploy n'a pas `AdministratorAccess` : sa
politique ne couvre que les ressources du projet (EC2/SG/EIP, rôle et instance-profile
`rch-secagent-java-ec2-*`, buckets `rch-secagent-java-app-*`, log group `/rch-bricoshop/app`, **la seule zone Route 53
du participant**). Si tu ajoutes une ressource au Terraform principal, étends cette politique
puis fais réappliquer le bootstrap.
