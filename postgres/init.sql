-- Script d'initialisation complet pour PostgreSQL
-- Créer les bases de données d'abord

-- Créer les bases de données
CREATE DATABASE "PlatformDB";
CREATE DATABASE "DatalakeDB";

-- Configurer PlatformDB
\connect PlatformDB

-- Créer les rôles
CREATE ROLE anon;
CREATE ROLE authenticator NOINHERIT;
GRANT anon TO authenticator;

-- Table Email (emails autorisés)
CREATE TABLE email (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    departement VARCHAR(100),
    status VARCHAR(20) NOT NULL CHECK (status IN ('Autoriser', 'Non Autoriser')),
    descriptions VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Table pour les expéditeurs inconnus
CREATE TABLE expediteurs_inconnus (
    id SERIAL PRIMARY KEY,
    email_expediteur VARCHAR(255) UNIQUE NOT NULL,
    descriptions VARCHAR(100),
    nombre_tentatives INTEGER DEFAULT 1,
    derniere_tentative TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Table pour les emails reçus
CREATE TABLE emails_recus (
    id SERIAL PRIMARY KEY,
    email_expediteur VARCHAR(255) NOT NULL,
    email_destinataire VARCHAR(255) NOT NULL,
    sujet TEXT,
    contenu TEXT,
    date_reception TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    statut_autorisation VARCHAR(20),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Fonction pour gérer la réception d'emails
CREATE OR REPLACE FUNCTION handle_email_received()
RETURNS TRIGGER AS $$
BEGIN
    -- Vérifier si l'expéditeur existe dans la table email
    IF EXISTS (SELECT 1 FROM email WHERE email.email = NEW.email_expediteur) THEN
        -- L'expéditeur existe, récupérer son statut
        SELECT status INTO NEW.statut_autorisation 
        FROM email 
        WHERE email.email = NEW.email_expediteur;
    ELSE
        -- L'expéditeur n'existe pas dans la table email
        -- Vérifier s'il existe déjà dans expediteurs_inconnus
        IF EXISTS (SELECT 1 FROM expediteurs_inconnus WHERE expediteurs_inconnus.email_expediteur = NEW.email_expediteur) THEN
            -- Incrémenter le nombre de tentatives
            UPDATE expediteurs_inconnus 
            SET nombre_tentatives = nombre_tentatives + 1,
                derniere_tentative = CURRENT_TIMESTAMP
            WHERE expediteurs_inconnus.email_expediteur = NEW.email_expediteur;
        ELSE
            -- Ajouter le nouvel expéditeur inconnu
            INSERT INTO expediteurs_inconnus (email_expediteur, descriptions)
            VALUES (NEW.email_expediteur, 'Expéditeur non autorisé détecté automatiquement');
        END IF;
        
        -- Définir le statut comme non autorisé
        NEW.statut_autorisation := 'Non Autoriser';
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Créer les vues
CREATE VIEW emails_autorises AS
    SELECT e.email, e.departement, e.status, e.descriptions
    FROM email e
    WHERE e.status = 'Autoriser';

CREATE VIEW emails_non_autorises AS
    SELECT e.email, e.departement, e.status, e.descriptions
    FROM email e
    WHERE e.status = 'Non Autoriser';

CREATE VIEW statistiques_emails AS
    SELECT 
        e.departement,
        COUNT(*) as total_emails,
        SUM(CASE WHEN e.status = 'Autoriser' THEN 1 ELSE 0 END) as emails_autorises,
        SUM(CASE WHEN e.status = 'Non Autoriser' THEN 1 ELSE 0 END) as emails_non_autorises
    FROM email e
    GROUP BY e.departement;

-- Appliquer le trigger sur la table emails_recus
CREATE TRIGGER trigger_email_received
    BEFORE INSERT ON emails_recus
    FOR EACH ROW
    EXECUTE FUNCTION handle_email_received();

-- Configurer les permissions pour PostgREST
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticator;

-- Permissions pour les tables
GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticator;

-- Permissions pour les séquences
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO anon;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticator;

-- Permissions par défaut pour les nouvelles tables
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO authenticator;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticator;

-- Permettre la connexion aux bases
GRANT CONNECT ON DATABASE "PlatformDB" TO authenticator;
GRANT CONNECT ON DATABASE "PlatformDB" TO anon;

-- Créer des index pour optimiser les performances
CREATE INDEX idx_email_status ON email(status);
CREATE INDEX idx_emails_recus_expediteur ON emails_recus(email_expediteur);
CREATE INDEX idx_expediteurs_inconnus_email ON expediteurs_inconnus(email_expediteur);

-- Insérer quelques données de test
INSERT INTO email (email, departement, status, descriptions) VALUES
('admin@company.com', 'IT', 'Autoriser', 'Administrateur système'),
('hr@company.com', 'RH', 'Autoriser', 'Ressources humaines'),
('spam@external.com', 'Externe', 'Non Autoriser', 'Adresse spam connue');

-- Configurer DatalakeDB
\connect DatalakeDB

CREATE TABLE datalake_objects (
    id SERIAL PRIMARY KEY,
    bucket_name VARCHAR(255),
    object_key VARCHAR(255),
    metadata JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Permissions pour DatalakeDB (les rôles existent déjà)
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticator;
GRANT ALL ON datalake_objects TO authenticator;
GRANT SELECT ON datalake_objects TO anon;
GRANT CONNECT ON DATABASE "DatalakeDB" TO authenticator;
GRANT CONNECT ON DATABASE "DatalakeDB" TO anon;