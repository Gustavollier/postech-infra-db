data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

data "azurerm_client_config" "current" {}

# ---------------------------------------------------------------------------
# Segredos gerados pelo Terraform
#
# Nenhuma senha é digitada por uma pessoa nem passa por variável de ambiente:
# o Terraform gera, grava no Key Vault e os consumidores (AKS e Function App)
# leem de lá. O valor só existe no state remoto, que fica em Storage privado.
# ---------------------------------------------------------------------------

resource "random_password" "sql_admin" {
  length  = 32
  special = true
  # Azure SQL rejeita alguns caracteres em senha; este conjunto é seguro.
  override_special = "!#$%&*()-_=+[]{}<>?"

  min_upper   = 2
  min_lower   = 2
  min_numeric = 2
  min_special = 2
}

resource "random_password" "app_db" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>?"

  min_upper   = 2
  min_lower   = 2
  min_numeric = 2
  min_special = 2
}

# A API exige >= 32 bytes (ver PosTechChallenge/Program.cs). 64 caracteres
# alfanuméricos evitam qualquer problema de escaping ao passar por App Settings,
# variável de ambiente do container e named value do APIM.
resource "random_password" "jwt_secret" {
  length  = 64
  special = false
}

# ---------------------------------------------------------------------------
# Azure SQL Database (banco gerenciado exigido pela Fase 3)
# ---------------------------------------------------------------------------

resource "azurerm_mssql_server" "main" {
  name                = var.sql_server_name
  resource_group_name = data.azurerm_resource_group.main.name

  # Propositalmente diferente de var.location — ver a justificativa em
  # variables.tf: eastus recusa provisionamento de Azure SQL nesta subscription.
  location                     = var.sql_location
  version                      = "12.0"
  administrator_login          = var.administrator_login
  administrator_login_password = random_password.sql_admin.result
  minimum_tls_version          = "1.2"

  tags = var.tags
}

resource "azurerm_mssql_database" "main" {
  name           = var.database_name
  server_id      = azurerm_mssql_server.main.id
  sku_name       = var.sku_name
  max_size_gb    = var.max_size_gb
  collation      = "SQL_Latin1_General_CP1_CI_AS"
  zone_redundant = false

  # O tier Basic não suporta retenção configurável de backup de longo prazo.
  # O backup automático de 7 dias do Azure SQL já atende o desafio.

  tags = var.tags

  lifecycle {
    # Evita que um terraform apply acidental destrua o banco com os dados do seed.
    prevent_destroy = true
  }
}

# Libera serviços do Azure (AKS e Function App saem por IPs dinâmicos do Azure).
# Regra 0.0.0.0 é a convenção do Azure para "Allow Azure services".
resource "azurerm_mssql_firewall_rule" "azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# IPs adicionais liberados para rodar a carga de schema e depurar localmente.
resource "azurerm_mssql_firewall_rule" "allowed" {
  for_each = var.allowed_ip_ranges

  name             = each.key
  server_id        = azurerm_mssql_server.main.id
  start_ip_address = each.value.start_ip
  end_ip_address   = each.value.end_ip
}

# ---------------------------------------------------------------------------
# Key Vault — a connection string é consumida pela aplicação (AKS) e pela Function
# ---------------------------------------------------------------------------

resource "azurerm_key_vault" "main" {
  name                       = var.key_vault_name
  resource_group_name        = data.azurerm_resource_group.main.name
  location                   = var.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  rbac_authorization_enabled = true

  tags = var.tags
}

# Quem roda o Terraform precisa de permissão para gravar os segredos abaixo.
resource "azurerm_role_assignment" "terraform_secrets" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_key_vault_secret" "connection_string" {
  name         = "SqlConnectionString"
  key_vault_id = azurerm_key_vault.main.id

  value = join("", [
    "Server=tcp:${azurerm_mssql_server.main.fully_qualified_domain_name},1433;",
    "Initial Catalog=${azurerm_mssql_database.main.name};",
    "User ID=appchat;",
    "Password=${random_password.app_db.result};",
    "Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
  ])

  depends_on = [azurerm_role_assignment.terraform_secrets]
}

# O segredo do JWT é compartilhado entre a API e a Function: as duas precisam
# assinar/validar com exatamente a mesma chave.
resource "azurerm_key_vault_secret" "jwt_secret" {
  name         = "JwtSecretKey"
  key_vault_id = azurerm_key_vault.main.id
  value        = random_password.jwt_secret.result

  depends_on = [azurerm_role_assignment.terraform_secrets]
}

# A pipeline precisa da senha do admin para aplicar o schema (cria o contained
# user appchat, o que exige privilégio de administrador do banco).
resource "azurerm_key_vault_secret" "sql_admin_password" {
  name         = "SqlAdminPassword"
  key_vault_id = azurerm_key_vault.main.id
  value        = random_password.sql_admin.result

  depends_on = [azurerm_role_assignment.terraform_secrets]
}

# Passada ao script de schema como a sqlcmd variable $(APP_DB_PASSWORD).
resource "azurerm_key_vault_secret" "app_db_password" {
  name         = "AppDbPassword"
  key_vault_id = azurerm_key_vault.main.id
  value        = random_password.app_db.result

  depends_on = [azurerm_role_assignment.terraform_secrets]
}
