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

# Uma senha por banco: cada serviço tem o seu usuário, e o usuário do OS
# Service não abre o banco do Identidade. É a regra "nenhum serviço acessa o
# banco de outro" valendo na credencial, e não só na disciplina do código.
resource "random_password" "app_db" {
  for_each = var.bancos

  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>?"

  min_upper   = 2
  min_lower   = 2
  min_numeric = 2
  min_special = 2
}

# O Identidade exige >= 32 bytes (ver EmissorDeToken). 64 caracteres
# alfanuméricos evitam qualquer problema de escaping ao passar por App Settings,
# variável de ambiente do container e named value do APIM.
resource "random_password" "jwt_secret" {
  length  = 64
  special = false
}

# ---------------------------------------------------------------------------
# Azure SQL: um servidor lógico, um banco por serviço
#
# Fase 4: o banco único do monólito dá lugar ao os-db (OS Service) e ao
# identidade-db (Identidade). Billing e Execução ficam no MongoDB Atlas.
#
# Um servidor lógico só, com dois bancos, e não dois servidores: o servidor
# lógico não custa nada, o custo é do banco, e cada banco tem o seu usuário
# contido. O isolamento que o enunciado pede está no banco e na credencial.
# ---------------------------------------------------------------------------

resource "azurerm_mssql_server" "main" {
  name                = var.sql_server_name
  resource_group_name = data.azurerm_resource_group.main.name

  # var.sql_location é separada de var.location por histórico de bloqueio
  # regional de Azure SQL nesta subscription — ver variables.tf.
  location                     = var.sql_location
  version                      = "12.0"
  administrator_login          = var.administrator_login
  administrator_login_password = random_password.sql_admin.result
  minimum_tls_version          = "1.2"

  tags = var.tags
}

resource "azurerm_mssql_database" "servico" {
  for_each = var.bancos

  name           = each.value
  server_id      = azurerm_mssql_server.main.id
  sku_name       = var.sku_name
  max_size_gb    = var.max_size_gb
  collation      = "SQL_Latin1_General_CP1_CI_AS"
  zone_redundant = false

  # Sem prevent_destroy, ao contrário da Fase 3: o ambiente é recriado perto
  # da gravação e destruído depois da entrega, e o destroy tem que funcionar.
  # Os bancos não guardam nada que não se recrie: os serviços aplicam o
  # próprio schema na partida.

  tags = var.tags
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

# A permissão de escrita nos segredos NÃO é gerenciada aqui, de propósito.
#
# Quem roda o Terraform precisa conseguir gravar no Key Vault já na primeira
# execução — não dá para o próprio apply conceder a permissão que ele mesmo
# depende para funcionar. É ovo e galinha.
#
# O papel "Key Vault Secrets Officer" é concedido ao service principal da
# pipeline no bootstrap, fora do Terraform:
#
#   az role assignment create \
#     --assignee <appId> \
#     --role "Key Vault Secrets Officer" \
#     --scope <id do Key Vault>
#
# Tentar gerenciar isso aqui quebrava o apply na pipeline com
# "RoleAssignmentExists", porque o principal ja tinha o papel.

# Uma connection string por serviço, cada uma com o usuário contido daquele
# banco. Os nomes seguem o que os manifestos dos serviços esperam.
resource "azurerm_key_vault_secret" "connection_string" {
  for_each = var.bancos

  name         = "${each.key}-sql-connection-string"
  key_vault_id = azurerm_key_vault.main.id

  value = join("", [
    "Server=tcp:${azurerm_mssql_server.main.fully_qualified_domain_name},1433;",
    "Initial Catalog=${azurerm_mssql_database.servico[each.key].name};",
    "User ID=${each.key}_app;",
    "Password=${random_password.app_db[each.key].result};",
    "Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
  ])
}

# O segredo do JWT é compartilhado entre o Identidade, a Auth Function e o
# APIM: os três precisam assinar ou validar com exatamente a mesma chave.
resource "azurerm_key_vault_secret" "jwt_secret" {
  name         = "JwtSecretKey"
  key_vault_id = azurerm_key_vault.main.id
  value        = random_password.jwt_secret.result
}

# A pipeline precisa da senha do admin para criar os usuários contidos de
# cada banco, o que exige privilégio de administrador.
resource "azurerm_key_vault_secret" "sql_admin_password" {
  name         = "SqlAdminPassword"
  key_vault_id = azurerm_key_vault.main.id
  value        = random_password.sql_admin.result
}

# Passada ao script de usuários como a sqlcmd variable $(APP_DB_PASSWORD).
resource "azurerm_key_vault_secret" "app_db_password" {
  for_each = var.bancos

  name         = "${each.key}-db-app-password"
  key_vault_id = azurerm_key_vault.main.id
  value        = random_password.app_db[each.key].result
}
