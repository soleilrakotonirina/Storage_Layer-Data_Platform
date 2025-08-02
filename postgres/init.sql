-- storage-layer/postgres/init.sql
-- Script d'initialisation PostgreSQL avec permissions PostgREST

-- Créer les bases de données
CREATE DATABASE "PlatformDB";
CREATE DATABASE "DatalakeDB";

-- Configurer PlatformDB
\connect PlatformDB

-- Supprimer les rôles existants s'ils existent (pour éviter les conflits)
DROP ROLE IF EXISTS anon;
DROP ROLE IF EXISTS authenticator;

-- Créer les rôles pour PostgREST
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticator NOINHERIT LOGIN PASSWORD 'authenticator_password';
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
        SELECT status INTO NEW.statut_autorisation 
        FROM email 
        WHERE email.email = NEW.email_expediteur;
    ELSE
        IF EXISTS (SELECT 1 FROM expediteurs_inconnus WHERE expediteurs_inconnus.email_expediteur = NEW.email_expediteur) THEN
            UPDATE expediteurs_inconnus 
            SET nombre_tentatives = nombre_tentatives + 1,
                derniere_tentative = CURRENT_TIMESTAMP
            WHERE expediteurs_inconnus.email_expediteur = NEW.email_expediteur;
        ELSE
            INSERT INTO expediteurs_inconnus (email_expediteur, descriptions)
            VALUES (NEW.email_expediteur, 'Expéditeur non autorisé détecté automatiquement');
        END IF;
        
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

-- Créer le trigger
CREATE TRIGGER trigger_email_received
    BEFORE INSERT ON emails_recus
    FOR EACH ROW
    EXECUTE FUNCTION handle_email_received();

-- PERMISSIONS POUR POSTGREST - PARTIE CRITIQUE
-- 1. Permissions sur le schéma
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticator;

-- 2. Permissions complètes sur toutes les tables pour anon
GRANT SELECT, INSERT, UPDATE, DELETE ON email TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON expediteurs_inconnus TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON emails_recus TO anon;
GRANT SELECT ON emails_autorises TO anon;
GRANT SELECT ON emails_non_autorises TO anon;
GRANT SELECT ON statistiques_emails TO anon;

-- 3. Permissions sur les séquences (nécessaire pour les SERIAL/auto-increment)
GRANT USAGE, SELECT ON SEQUENCE email_id_seq TO anon;
GRANT USAGE, SELECT ON SEQUENCE expediteurs_inconnus_id_seq TO anon;
GRANT USAGE, SELECT ON SEQUENCE emails_recus_id_seq TO anon;

-- 4. Permissions complètes pour authenticator
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticator;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticator;

-- 5. Permissions par défaut pour les futures tables/séquences
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO authenticator;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticator;

-- 6. Permissions de connexion à la base
GRANT CONNECT ON DATABASE "PlatformDB" TO authenticator;
GRANT CONNECT ON DATABASE "PlatformDB" TO anon;

-- 7. Activer Row Level Security (RLS)
ALTER TABLE email ENABLE ROW LEVEL SECURITY;
ALTER TABLE expediteurs_inconnus ENABLE ROW LEVEL SECURITY;
ALTER TABLE emails_recus ENABLE ROW LEVEL SECURITY;

-- 8. Créer des policies permissives pour anon (accès total)
DROP POLICY IF EXISTS anon_access_email ON email;
CREATE POLICY anon_access_email ON email 
    FOR ALL TO anon 
    USING (true) 
    WITH CHECK (true);

DROP POLICY IF EXISTS anon_access_expediteurs ON expediteurs_inconnus;
CREATE POLICY anon_access_expediteurs ON expediteurs_inconnus 
    FOR ALL TO anon 
    USING (true) 
    WITH CHECK (true);

DROP POLICY IF EXISTS anon_access_emails_recus ON emails_recus;
CREATE POLICY anon_access_emails_recus ON emails_recus 
    FOR ALL TO anon 
    USING (true) 
    WITH CHECK (true);

-- 9. Créer les index pour les performances
CREATE INDEX idx_email_status ON email(status);
CREATE INDEX idx_email_email ON email(email);
CREATE INDEX idx_emails_recus_expediteur ON emails_recus(email_expediteur);
CREATE INDEX idx_emails_recus_destinataire ON emails_recus(email_destinataire);
CREATE INDEX idx_expediteurs_inconnus_email ON expediteurs_inconnus(email_expediteur);
CREATE INDEX idx_emails_recus_date ON emails_recus(date_reception);

-- 10. Insérer des données de test
INSERT INTO email (email, departement, status, descriptions) VALUES
('sunrakotonirina78@gmail.com', 'Departement A', 'Autoriser', 'Droit'),
('finoanar40@gmail.com', 'Departement B', 'Autoriser', 'Informatique'),
('zazahendry366@gmail.com', 'Departement B', 'Non Autoriser', 'Informatique'),
('admin@company.com', 'IT', 'Autoriser', 'Administrateur système'),
('test@example.com', 'Test', 'Autoriser', 'Compte de test');

-- Configurer DatalakeDB
\connect DatalakeDB

-- Table pour le datalake
CREATE TABLE datalake_objects (
    id SERIAL PRIMARY KEY,
    bucket_name VARCHAR(255),
    object_key VARCHAR(255),
    metadata JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Permissions pour DatalakeDB
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticator;
GRANT SELECT, INSERT, UPDATE, DELETE ON datalake_objects TO anon;
GRANT ALL ON datalake_objects TO authenticator;
GRANT USAGE, SELECT ON SEQUENCE datalake_objects_id_seq TO anon;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticator;
GRANT CONNECT ON DATABASE "DatalakeDB" TO authenticator;
GRANT CONNECT ON DATABASE "DatalakeDB" TO anon;

-- Message de confirmation
\connect PlatformDB
SELECT 'Base de données PlatformDB configurée avec succès' as status;