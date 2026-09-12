output "sql_server_fqdn" {
  description = "FQDN do SQL Server. Usado pela pipeline para aplicar o schema."
  value       = azurerm_mssql_server.main.fully_qualified_domain_name
}

output "database_name" {
  description = "Nome do banco de dados."
  value       = azurerm_mssql_database.main.name
}

output "key_vault_name" {
  description = "Key Vault com a connection string e o segredo do JWT."
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "URI do Key Vault, usado nas Key Vault references dos App Settings."
  value       = azurerm_key_vault.main.vault_uri
}

output "connection_string_secret_id" {
  description = "ID do segredo da connection string, para referência nos outros repos."
  value       = azurerm_key_vault_secret.connection_string.versionless_id
}

output "jwt_secret_id" {
  description = "ID do segredo do JWT, consumido pela API e pela Auth Function."
  value       = azurerm_key_vault_secret.jwt_secret.versionless_id
}
