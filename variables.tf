variable "resource_group_name" {
  description = "Resource group existente onde o banco será criado."
  type        = string
  default     = "pos-tech-fiap"
}

variable "location" {
  description = <<-EOT
    Região do Azure. A mesma de postech-infra-k8s.

    Fase 4: a política "Allowed resource deployment regions" da subscription
    só aceita brazilsouth, canadacentral, francecentral, italynorth e
    belgiumcentral. canadacentral foi escolhida por custo.
  EOT
  type        = string
  default     = "canadacentral"
}

variable "sql_location" {
  description = <<-EOT
    Região do SQL Server, separada da região principal.

    Na Fase 3 a subscription tinha Azure SQL BLOQUEADO em eastus
    ("ProvisioningDisabled"), e o banco foi para centralus enquanto o resto
    ficava em eastus.

    Na Fase 4 a política de regiões recusa centralus, e canadacentral aceita
    Azure SQL (capabilities: Available, 02/11/2026). O banco volta a ficar na
    mesma região da aplicação. A variável continua separada para o caso de
    outro bloqueio regional aparecer.
  EOT
  type        = string
  default     = "canadacentral"
}

variable "sql_server_name" {
  description = <<-EOT
    Nome do SQL Server lógico. Precisa ser único globalmente.

    O sufixo indica a região. Na Fase 3, a primeira tentativa sem sufixo em
    eastus falhou e o Azure manteve a reserva do nome atrelada àquela região;
    -cus foi o nome em centralus. Na Fase 4, em canadacentral, o sufixo é -cac
    pelo mesmo motivo: nome com reserva presa a outra região não pode ser
    reaproveitado.
  EOT
  type        = string
  default     = "postech-sql-13soat-cac"
}

variable "bancos" {
  description = <<-EOT
    Um banco por serviço que usa SQL. A chave é o prefixo dos segredos no Key
    Vault e do usuário contido (os_app, identidade_app); o valor é o nome do
    banco.
  EOT
  type        = map(string)
  default = {
    os         = "os-db"
    identidade = "identidade-db"
  }
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
    fase    = "4"
    owner   = "terraform"
  }
}
