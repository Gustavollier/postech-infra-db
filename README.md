# PosTech Infra — Banco de Dados

Terraform do banco gerenciado do Tech Challenge Fase 3 (15SOAT): Azure SQL Database, Azure Key Vault e os segredos que os outros três repositórios da entrega consomem.

É o item 2 dos quatro repositórios da entrega. Os outros três rodam a aplicação, a autenticação e o cluster; este entrega o banco e a fonte única dos segredos que os une.

## O que este repositório provisiona

| Recurso | Descrição |
|---|---|
| `azurerm_mssql_server` + `azurerm_mssql_database` | Azure SQL Database gerenciado, tier `Basic` (5 DTU / 2 GB) |
| `azurerm_mssql_firewall_rule` | Libera "serviços do Azure" (AKS e Container Apps saem por IP dinâmico) e as faixas extras em `allowed_ip_ranges` |
| `azurerm_key_vault` | Key Vault com RBAC, único ponto de leitura da connection string e do segredo do JWT |
| `azurerm_key_vault_secret` (4x) | Connection string da aplicação, segredo HMAC do JWT, senha do admin do SQL e senha do usuário `appchat`, todas geradas por `random_password` — nenhuma é digitada por uma pessoa |
| `sql/schema-azure.sql` | Schema do banco (tabelas, seed), aplicado pela pipeline via `sqlcmd` |

## Por que Azure SQL Database

Motor já usado na Fase 2 (SQL Server), compatibilidade total com o schema e as queries Dapper/T-SQL herdadas, sem custo de portar a camada de persistência sob o prazo do desafio. O comparativo formal com PostgreSQL/MySQL Flexible Server e a justificativa completa estão na Seção 7 do [documento de entrega](https://github.com/Gustavollier/postech-app/tree/main/Documents).

## Decisões que o ambiente impôs

**O banco fica em `centralus`, não em `eastus` como o resto da plataforma.** Esta subscription acadêmica bloqueia provisionamento de Azure SQL em `eastus`/`eastus2` (`ProvisioningDisabled`). Custo: ~10-20 ms de latência adicional entre a aplicação e o banco, sem tráfego cobrado — mesma geografia. Efeito colateral favorável: o banco ficou colocalizado com a Auth Function (`postech-infra-k8s`), que por outro motivo de quota também foi parar em `centralus`.

**O nome do SQL Server logico leva o sufixo `-cus`.** A primeira tentativa, sem sufixo, falhou em `eastus` com `ProvisioningDisabled` e o Azure manteve a reserva do nome atrelada àquela região — recriar em `centralus` exigiu um nome novo.

**`prevent_destroy = true` no banco.** Evita que um `terraform apply` acidental derrube o banco com os dados do seed.

## Segredos gerados pelo Terraform

Nenhuma senha é digitada por uma pessoa nem passa por variável de ambiente: o Terraform gera com `random_password`, grava no Key Vault, e os consumidores leem de lá.

| Segredo | Nome no Key Vault | Quem consome |
|---|---|---|
| Connection string da aplicação | `SqlConnectionString` | API (AKS) e Auth Function (Container Apps) |
| Chave de assinatura do JWT | `JwtSecretKey` | API e Auth Function — precisam assinar/validar com a mesma chave |
| Senha do admin do SQL | `SqlAdminPassword` | Pipeline deste repositório, para aplicar o schema |
| Senha do usuário `appchat` | `AppDbPassword` | Contained user usado pela aplicação em runtime |

A permissão de escrita no Key Vault (papel `Key Vault Secrets Officer`) é concedida ao service principal da pipeline **fora** do Terraform, no bootstrap — geri-la aqui criaria uma dependência circular com o próprio `apply` que precisa dela.

## Pipeline

`.github/workflows/terraform.yml`, autenticando no Azure por OIDC — sem senha nem certificado guardados.

| Job | Quando | O que faz |
|---|---|---|
| `plan` | Pull request | `fmt -check`, `init`, `validate`, `plan` — o plano é comentado no PR |
| `apply` | Push em `main` ou `develop` | `terraform apply -auto-approve` — ambiente `production` (branch `main`) ou `homolog` (demais) |
| `schema` | Após o `apply` | Libera o IP do runner no firewall, instala o `sqlcmd`, aplica `sql/schema-azure.sql`, remove a regra de firewall — inclusive em caso de falha |

O schema é aplicado com `IF NOT EXISTS`/drops idempotentes, então pode ser reaplicado com segurança a cada execução.

## Executar localmente

```bash
terraform init
terraform plan
terraform apply
```

O backend do state (`azurerm`, container `tfstate` no storage account `postechtfstate13soat`) é compartilhado com os demais repositórios Terraform da entrega — cada um com sua própria chave de state (`infra-db.tfstate`, por exemplo). Aplicar o schema manualmente contra o banco provisionado:

```bash
sqlcmd -S <fqdn-do-servidor>.database.windows.net -d PosTechChallenge \
       -U postechadmin -P "<senha-do-admin>" \
       -v APP_DB_PASSWORD="<senha-do-appchat>" \
       -i sql/schema-azure.sql
```

As senhas atuais estão no Key Vault (`SqlAdminPassword`, `AppDbPassword`), nunca neste repositório.

## Segredos — o que nunca é versionado

Nada sensível é commitado. `*.tfvars`, `*.tfstate` e `*.tfplan`/`tfplan` estão no `.gitignore` — o arquivo de plano embute o state inteiro, com as senhas em claro, e não deve virar artefato de pipeline.

## Repositórios da entrega

| Repo | Conteúdo |
|---|---|
| [postech-app](https://github.com/Gustavollier/postech-app) | Aplicação principal (.NET) e manifestos do AKS |
| [postech-auth-function](https://github.com/Gustavollier/postech-auth-function) | Autenticação de cliente por CPF, emite o JWT |
| **postech-infra-db** | este repositório |
| [postech-infra-k8s](https://github.com/Gustavollier/postech-infra-k8s) | Terraform: AKS, ACR, APIM, Datadog |

Documentação arquitetural completa (componentes, sequência, RFCs, ADRs, justificativa de banco + ER): [`postech-app/Documents`](https://github.com/Gustavollier/postech-app/tree/main/Documents).
