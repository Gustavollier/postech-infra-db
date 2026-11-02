-- ---------------------------------------------------------------------------
-- Usuário contido do serviço dono deste banco.
--
-- Roda uma vez por banco (os-db, identidade-db), com as variáveis do sqlcmd:
--   $(APP_USER)         os_app | identidade_app
--   $(APP_DB_PASSWORD)  a senha que o Terraform gerou e guardou no Key Vault
--
-- Usuário CONTIDO: existe só dentro deste banco, sem login de servidor. Ele não
-- enxerga nenhum outro banco do mesmo servidor lógico, que é o que garante,
-- na credencial, que o OS Service não lê o identidade-db e vice-versa.
--
-- db_owner porque cada serviço aplica o próprio schema na partida (CREATE
-- TABLE, CREATE INDEX), e o schema é do serviço, não da infraestrutura.
--
-- Idempotente: reaplicar só atualiza a senha.
-- ---------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '$(APP_USER)')
BEGIN
    CREATE USER [$(APP_USER)] WITH PASSWORD = '$(APP_DB_PASSWORD)';
END
ELSE
BEGIN
    ALTER USER [$(APP_USER)] WITH PASSWORD = '$(APP_DB_PASSWORD)';
END
GO

ALTER ROLE db_owner ADD MEMBER [$(APP_USER)];
GO
