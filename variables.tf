variable "resource_group_name" {
  description = "Resource group existente onde o banco será criado."
  type        = string
  default     = "pos-tech-fiap"
}

variable "location" {
  description = "Região do Azure. Mesma do APIM já provisionado."
  type        = string
  default     = "eastus"
}

variable "sql_server_name" {
  description = "Nome do SQL Server lógico. Precisa ser único globalmente."
  type        = string
  default     = "postech-sql-13soat"
}

variable "database_name" {
  description = "Nome do banco de dados."
  type        = string
  default     = "PosTechChallenge"
}

variable "sku_name" {
  description = <<-EOT
    SKU do Azure SQL Database. Basic (5 DTU, 2 GB) é suficiente para o desafio
    e é a opção mais barata; S0 se precisar de mais throughput.
  EOT
  type        = string
  default     = "Basic"
}

variable "max_size_gb" {
  description = "Tamanho máximo do banco em GB. O tier Basic aceita no máximo 2."
  type        = number
  default     = 2
}

variable "administrator_login" {
  description = "Usuário administrador do SQL Server."
  type        = string
  default     = "postechadmin"
}

# As senhas do admin, do usuário da aplicação e o segredo do JWT não são
# variáveis: o Terraform gera com random_password e publica no Key Vault.
# Ninguém digita nem transporta esses valores.

variable "allowed_ip_ranges" {
  description = <<-EOT
    Faixas de IP liberadas no firewall do SQL Server, além dos serviços do Azure.
    Usado para a pipeline aplicar o schema e para depuração local.
  EOT
  type = map(object({
    start_ip = string
    end_ip   = string
  }))
  default = {}
}

variable "key_vault_name" {
  description = "Key Vault onde a connection string é publicada. Único globalmente."
  type        = string
  default     = "postech-kv-13soat"
}

variable "tags" {
  description = "Tags aplicadas a todos os recursos."
  type        = map(string)
  default = {
    projeto = "postech-13soat"
    fase    = "3"
    owner   = "terraform"
  }
}
