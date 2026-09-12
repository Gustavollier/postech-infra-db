data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

data "azurerm_client_config" "current" {}

# ---------------------------------------------------------------------------
# Azure SQL Database (banco gerenciado exigido pela Fase 3)
# ---------------------------------------------------------------------------

resource "azurerm_mssql_server" "main" {
  name                         = var.sql_server_name
  resource_group_name          = data.azurerm_resource_group.main.name
  location                     = var.location
  version                      = "12.0"
  administrator_login          = var.administrator_login
  administrator_login_password = var.administrator_password
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
    "Password=${var.app_db_password};",
    "Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
  ])

  depends_on = [azurerm_role_assignment.terraform_secrets]
}

# O segredo do JWT é compartilhado entre a API e a Function: as duas precisam
# assinar/validar com exatamente a mesma chave.
resource "azurerm_key_vault_secret" "jwt_secret" {
  name         = "JwtSecretKey"
  key_vault_id = azurerm_key_vault.main.id
  value        = var.jwt_secret_key

  depends_on = [azurerm_role_assignment.terraform_secrets]
}
