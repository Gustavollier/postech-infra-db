output "sql_server_name" {
  description = "Nome do SQL Server lógico. Usado pela pipeline para liberar o firewall."
  value       = azurerm_mssql_server.main.name
}

output "sql_server_fqdn" {
  description = "FQDN do SQL Server. Usado pela pipeline para criar os usuários."
  value       = azurerm_mssql_server.main.fully_qualified_domain_name
}

output "bancos" {
  description = "Banco de cada serviço."
  value       = { for k, b in azurerm_mssql_database.servico : k => b.name }
}

output "key_vault_name" {
  description = "Key Vault com as connection strings e o segredo do JWT."
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "URI do Key Vault."
  value       = azurerm_key_vault.main.vault_uri
}

output "connection_string_secret_ids" {
  description = "IDs dos segredos de connection string, por serviço."
  value       = { for k, s in azurerm_key_vault_secret.connection_string : k => s.versionless_id }
}

output "jwt_secret_id" {
  description = "ID do segredo do JWT, consumido pelo Identidade, pela Auth Function e pelo APIM."
  value       = azurerm_key_vault_secret.jwt_secret.versionless_id
}
