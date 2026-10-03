# Lab AWS Security Agent – mini site Java + Terraform + DNS

Objectif : avoir en ~15 min un site web **Java** public, en **HTTPS**, sur un **nom de domaine Route 53**,
deployé par **Terraform**, pour lancer un pentest **AWS Security Agent**.

```
Internet ──> app.mondomaine.tld (Route 53, A record)
          ──> Elastic IP ──> EC2 t3.micro (Amazon Linux 2023)
                               ├─ Caddy :80/:443  (certificat Let's Encrypt automatique)
                               └─ java App.java  127.0.0.1:8080 (JDK 21, zéro build, zéro dépendance)
```

Pas de Docker, pas de Maven, pas d'ECR, pas d'ALB, pas d'ACM : le moins de pièces possible.

## Prérequis (une seule fois)
1. AWS CLI configurée (`aws sts get-caller-identity` OK) + Terraform >= 1.5.
2. Une **zone hébergée publique Route 53** dans le **même compte** :
   - pas de domaine ? Route 53 > Registered domains > Register (un `.click` / `.link` coûte quelques $/an) – la zone est créée automatiquement ;
   - domaine chez un autre registrar ? créer la hosted zone dans Route 53 et recopier ses 4 NS chez le registrar.

## Déployer
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # mettre ton domain_name
terraform init
terraform apply
```
Attendre 2–3 min (install Java + Caddy + certificat), puis :
```bash
curl https://app.mondomaine.tld/health
```
Debug sans SSH : `terraform output ssm_connect`, puis `sudo journalctl -u javaapp -u caddy -f`.

## Pages du site
| URL | Rôle |
|---|---|
| `/` | accueil |
| `/hello?name=...` | paramètre échappé (sain) |
| `/search?q=...` | sain par défaut ; **XSS réfléchie volontaire** si `demo_vuln = true` |
| `/health` | JSON de santé |

`demo_vuln = true` donne au moins une vraie vulnérabilité à trouver à Security Agent (utile en formation).
Ne laisse jamais ce mode actif hors du lab.

## Lancer AWS Security Agent
1. Console AWS Security Agent > *Set up* > créer un **Agent Space** (accès IAM-only pour aller vite).
2. Onglet *Penetration test* > *Set up penetration test* > domaine `app.mondomaine.tld`
   > **One-click verification** (Route 53 du même compte).
3. (Optionnel) Pousser ce dossier sur GitHub et connecter le repo (contexte code + remédiation par PR).
4. Web app > *Create a penetration test* > Target URL `https://app.mondomaine.tld`
   > **fixer Max task hours au minimum (20)** pour plafonner le coût.

## Nettoyer
```bash
terraform destroy
```
Le domaine Route 53 éventuellement acheté n'est pas géré par ce Terraform (pas supprimé).

## Coûts indicatifs
- EC2 t3.micro + EIP + zone Route 53 : quelques centimes/heure ; détruire après le lab.
- Security Agent pentest : facturé à la task-hour (essai gratuit pour les nouveaux clients) – vérifier la page pricing avant de lancer.
