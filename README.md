# Storage Layer - PostgreSQL & MinIO

Ce dépôt contient les services de base de stockage :
- PostgreSQL : entrepôt relationnel
- MinIO : stockage d’objets compatible S3

Démarrage :
docker-compose --env-file .env up -d

 Accès :
- MinIO UI : http://localhost:9001 (minioadmin / minioadmin)
- PostgreSQL : localhost:5432 (admin / admin)
