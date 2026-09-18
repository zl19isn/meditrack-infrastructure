Markdown

# MediTrack - Infrastructure Cloud & Automatisation (GreenOps Solutions)

Ce dépôt contient l'infrastructure as Code (IaC) et les scripts d'automatisation pour le projet **MediTrack**, répondant aux exigences de sécurité, de haute disponibilité et de conformité pour l'hébergement de données de santé (RGPD / HDS).

---

## Architecture du Projet

L'infrastructure est déployée sur le cloud **AWS (Région `eu-west-3` - Paris)** et repose sur les composants suivants :
* **Réseau :** VPC dédié (`10.0.0.0/16`), sous-réseau public, Internet Gateway et table de routage associée.
* **Calcul :** Instance EC2 (`t3.micro` sous Ubuntu 22.04 LTS) hébergeant un serveur web Nginx, sécurisée via un pare-feu local UFW et un disque root EBS chiffré (AES-256).
* **Stockage & CDN :** Bucket S3 privé pour les assets statiques, couplé à une distribution **CloudFront** via l'utilisation d'un *Origin Access Control (OAC)* pour un accès global sécurisé en HTTPS (redirection forcée).

---

## Structure du Dépôt

```text
meditrack-infrastructure/
├── terraform/
│   ├── provider.tf
│   ├── variables.tf
│   ├── main.tf
│   └── outputs.tf
├── ansible/
│   ├── inventory.ini
│   └── playbook.yml
└── site_static/
    └── index.html

Guide de Déploiement
1. Provisionnement avec Terraform

Positionne-toi dans le dossier Terraform, initialise le projet et déploie l'infrastructure :
Bash

cd terraform
terraform init
terraform plan
terraform apply -auto-approve

2. Configuration du serveur avec Ansible

Depuis la racine du projet, exécute le playbook de configuration en ciblant l'IP publique affichée par les outputs Terraform :
Bash

ansible-playbook -i ansible/inventory.ini ansible/playbook.yml
