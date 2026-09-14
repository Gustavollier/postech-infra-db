-- Schema do PosTechChallenge para AZURE SQL DATABASE
--
-- Diferenças em relação a infra/sql/init.sql (SQL Server local):
--   * o banco é criado pelo Terraform, então não há CREATE/DROP DATABASE nem USE
--   * Azure SQL Database não usa login de servidor aqui: 'appchat' é um CONTAINED USER
--     com senha própria, criado com CREATE USER ... WITH PASSWORD
--   * drops idempotentes no topo, para o script poder ser reaplicado pela pipeline
--
-- Seed login: todos os funcionarios compartilham a mesma senha inicial, cujo
-- hash BCrypt esta em @SenhaPadrao. O texto plano nao fica aqui — este
-- repositorio e publico e o valor vale em producao ate ser trocado.
--
-- Os CPFs do seed sao validos de verdade, com digito verificador correto. Nao e
-- preciosismo: o login valida o CPF como value object antes de consultar o
-- banco, entao um CPF de digitos repetidos (11111111111) nunca chega a ser
-- procurado — a requisicao morre em 400 e nenhum funcionario consegue entrar.

-- Remove objetos na ordem inversa das dependências de FK
DROP TABLE IF EXISTS Orcamento;
DROP TABLE IF EXISTS Status;
DROP TABLE IF EXISTS Itens;
DROP TABLE IF EXISTS OrdemServico;
DROP TABLE IF EXISTS Veiculo;
DROP TABLE IF EXISTS Seguranca;
DROP TABLE IF EXISTS Cliente;
DROP TABLE IF EXISTS Pecas;
DROP TABLE IF EXISTS Funcionario;
DROP TABLE IF EXISTS EmailOutbox;
GO

-- Usuário da aplicação (contained user)
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'appchat')
BEGIN
    CREATE USER appchat WITH PASSWORD = '$(APP_DB_PASSWORD)';
END
GO

SET NOCOUNT ON;
GO

CREATE TABLE Funcionario (
    Id INT PRIMARY KEY IDENTITY(1,1),
    Nome NVARCHAR(100) NOT NULL,
    Contato NVARCHAR(50),
    CPF NVARCHAR(14) NOT NULL,
    Cargo INT NOT NULL,
    ValorHora DECIMAL(10, 2) NOT NULL
);

CREATE TABLE Seguranca (
    Id INT PRIMARY KEY IDENTITY(1,1),
    FuncionarioId INT NOT NULL,
    SenhaHash NVARCHAR(255) NOT NULL,
    CriadoEm DATETIME NOT NULL DEFAULT GETUTCDATE(),
    CONSTRAINT UQ_Seguranca_FuncionarioId UNIQUE (FuncionarioId),
    FOREIGN KEY (FuncionarioId) REFERENCES Funcionario(Id)
);

CREATE TABLE Cliente (
    Id INT PRIMARY KEY IDENTITY(1,1),
    CreatedAt DATETIME NOT NULL,
    UpdatedAt DATETIME NOT NULL,
    CPF NVARCHAR(14),
    CNPJ NVARCHAR(18),
    NomeCompleto NVARCHAR(100) NOT NULL,
    Telefone NVARCHAR(20),
    Email NVARCHAR(100),
    Ativo BIT NOT NULL DEFAULT 1
);

CREATE TABLE Pecas (
    Id INT PRIMARY KEY IDENTITY(1,1),
    Nome NVARCHAR(100) NOT NULL,
    Marca NVARCHAR(50),
    Codigo NVARCHAR(50),
    Preco DECIMAL(10, 2) NOT NULL,
    UnidadeMedida INT NOT NULL,
    QuantidadeEstoque INT NOT NULL DEFAULT 0,
    CriadoEm DATETIME NOT NULL,
    AtualizadoEm DATETIME NOT NULL,
    Ativo BIT NOT NULL DEFAULT 1
);

CREATE TABLE Veiculo (
    Id INT PRIMARY KEY IDENTITY(1,1),
    ClienteId INT NOT NULL,
    Marca NVARCHAR(50) NOT NULL,
    Modelo NVARCHAR(50) NOT NULL,
    Placa NVARCHAR(10) NOT NULL,
    Cor NVARCHAR(30),
    AnoModelo INT NOT NULL,
    AnoFabricacao INT NOT NULL,
    KmEntrada INT NOT NULL,
    Ativo BIT NOT NULL DEFAULT 1,
    FOREIGN KEY (ClienteId) REFERENCES Cliente(Id)
);

CREATE TABLE OrdemServico (
    Id INT PRIMARY KEY IDENTITY(1,1),
    IdCliente INT NOT NULL,
    IdVeiculo INT NOT NULL,
    IdFuncionario INT NOT NULL,
    Status INT NOT NULL,
    CriadoEm DATETIME NOT NULL,
    AtualizadoEm DATETIME NOT NULL,
    FOREIGN KEY (IdCliente) REFERENCES Cliente(Id),
    FOREIGN KEY (IdVeiculo) REFERENCES Veiculo(Id),
    FOREIGN KEY (IdFuncionario) REFERENCES Funcionario(Id)
);

CREATE TABLE Itens (
    Id INT PRIMARY KEY IDENTITY(1,1),
    IdOS INT NOT NULL,
    TipoItem INT NOT NULL,
    QuantidadeItem INT NOT NULL,
    IdFuncionario INT NULL,
    IdPeca INT NULL,
    FOREIGN KEY (IdOS) REFERENCES OrdemServico(Id),
    FOREIGN KEY (IdFuncionario) REFERENCES Funcionario(Id),
    FOREIGN KEY (IdPeca) REFERENCES Pecas(Id)
);

CREATE TABLE Status (
    Id INT PRIMARY KEY IDENTITY(1,1),
    IdOS INT NOT NULL,
    UpdatedAt DATETIME NOT NULL,
    IdFuncionario INT NOT NULL,
    StatusAtual INT NOT NULL,
    FOREIGN KEY (IdOS) REFERENCES OrdemServico(Id),
    FOREIGN KEY (IdFuncionario) REFERENCES Funcionario(Id)
);

CREATE TABLE Orcamento (
    Id INT PRIMARY KEY IDENTITY(1,1),
    IdOS INT NOT NULL,
    ValorMaoDeObra DECIMAL(10, 2) NOT NULL,
    ValorPecas DECIMAL(10, 2) NOT NULL,
    ValorTotal DECIMAL(10, 2) NOT NULL,
    Status INT NOT NULL,
    CriadoEm DATETIME NOT NULL,
    AtualizadoEm DATETIME NOT NULL,
    CONSTRAINT UQ_Orcamento_IdOS UNIQUE (IdOS),
    FOREIGN KEY (IdOS) REFERENCES OrdemServico(Id)
);

CREATE TABLE EmailOutbox (
    Id INT PRIMARY KEY IDENTITY(1,1),
    Destinatario NVARCHAR(100) NOT NULL,
    Assunto NVARCHAR(200) NOT NULL,
    Corpo NVARCHAR(MAX) NOT NULL,
    Status INT NOT NULL,
    Tentativas INT NOT NULL DEFAULT 0,
    CriadoEm DATETIME NOT NULL,
    ProcessadoEm DATETIME NULL
);
GO

DECLARE @Agora DATETIME = GETUTCDATE();
DECLARE @SenhaPadrao NVARCHAR(255) = '$2a$11$Kz1iJ7wrLPvoD1XdqBN3Ge8hul.Tq2.4YqeM1h6iQxDbX/FIF4sj2';

-- Cargo enum
-- 0 Mecanico
-- 1 Recepcionista
-- 2 Gerente
-- 3 Estoquista

INSERT INTO Funcionario (Nome, Contato, CPF, Cargo, ValorHora)
VALUES
    ('Carlos Mendes', '(11) 99999-1001', '11144477735', 2, 180.00),
    ('Bruno Lima', '(11) 99999-1002', '22233344405', 0, 120.00),
    ('Ana Souza', '(11) 99999-1003', '33355577782', 1, 90.00),
    ('Paulo Reis', '(11) 99999-1004', '44466688893', 3, 95.00);

INSERT INTO Seguranca (FuncionarioId, SenhaHash, CriadoEm)
VALUES
    (1, @SenhaPadrao, @Agora),
    (2, @SenhaPadrao, @Agora),
    (3, @SenhaPadrao, @Agora),
    (4, @SenhaPadrao, @Agora);

INSERT INTO Cliente (CreatedAt, UpdatedAt, CPF, CNPJ, NomeCompleto, Telefone, Email, Ativo)
VALUES
    (@Agora, @Agora, '12345678909', NULL, 'Joao da Silva', '(11) 98888-0001', 'joao.silva@teste.com', 1),
    (@Agora, @Agora, NULL, '12345678000199', 'Auto Frotas LTDA', '(11) 4002-8922', 'contato@autofrotas.com', 1),
    (@Agora, @Agora, '98765432100', NULL, 'Maria Oliveira', '(11) 97777-0003', 'maria.oliveira@teste.com', 1);

-- UnidadeMedida values are following the current application enum contract
INSERT INTO Pecas (Nome, Marca, Codigo, Preco, UnidadeMedida, QuantidadeEstoque, CriadoEm, AtualizadoEm, Ativo)
VALUES
    ('Filtro de Oleo', 'Bosch', 'PEC-001', 39.90, 0, 15, @Agora, @Agora, 1),
    ('Pastilha de Freio', 'Cobreq', 'PEC-002', 149.90, 0, 8, @Agora, @Agora, 1),
    ('Oleo 5W30', 'Mobil', 'INS-001', 59.90, 0, 30, @Agora, @Agora, 1),
    ('Lampada H7', 'Philips', 'PEC-003', 24.90, 0, 20, @Agora, @Agora, 1);

INSERT INTO Veiculo (ClienteId, Marca, Modelo, Placa, Cor, AnoModelo, AnoFabricacao, KmEntrada, Ativo)
VALUES
    (1, 'Toyota', 'Corolla', 'ABC1D23', 'Prata', 2022, 2021, 45210, 1),
    (2, 'Fiat', 'Ducato', 'XYZ9K87', 'Branca', 2021, 2021, 120340, 1),
    (3, 'Chevrolet', 'Onix', 'BRA2E45', 'Preto', 2023, 2022, 18300, 1);

-- StatusServico enum
-- 0 Recebida
-- 1 EmDiagnostico
-- 2 AguardandoAprovacao
-- 3 EmExecucao
-- 4 Finalizada
-- 5 Entregue

INSERT INTO OrdemServico (IdCliente, IdVeiculo, IdFuncionario, Status, CriadoEm, AtualizadoEm)
VALUES
    (1, 1, 3, 2, DATEADD(HOUR, -8, @Agora), DATEADD(HOUR, -2, @Agora)),
    (2, 2, 2, 3, DATEADD(DAY, -1, @Agora), DATEADD(HOUR, -1, @Agora)),
    (3, 3, 3, 0, DATEADD(HOUR, -3, @Agora), DATEADD(HOUR, -3, @Agora));

-- ETipoItemOrdemServico enum
-- 0 MaoDeObra
-- 1 Peca

INSERT INTO Itens (IdOS, TipoItem, QuantidadeItem, IdFuncionario, IdPeca)
VALUES
    (1, 0, 1, 2, NULL),
    (1, 1, 2, NULL, 1),
    (1, 1, 4, NULL, 3),
    (2, 0, 1, 2, NULL),
    (2, 1, 1, NULL, 2),
    (3, 0, 1, 2, NULL);

INSERT INTO Status (IdOS, UpdatedAt, IdFuncionario, StatusAtual)
VALUES
    (1, DATEADD(HOUR, -8, @Agora), 3, 0),
    (1, DATEADD(HOUR, -5, @Agora), 2, 1),
    (1, DATEADD(HOUR, -2, @Agora), 3, 2),
    (2, DATEADD(DAY, -1, @Agora), 3, 0),
    (2, DATEADD(HOUR, -20, @Agora), 2, 1),
    (2, DATEADD(HOUR, -1, @Agora), 2, 3),
    (3, DATEADD(HOUR, -3, @Agora), 3, 0);

INSERT INTO Orcamento (IdOS, ValorMaoDeObra, ValorPecas, ValorTotal, Status, CriadoEm, AtualizadoEm)
VALUES
    (1, 120.00, 319.40, 439.40, 0, DATEADD(HOUR, -2, @Agora), DATEADD(HOUR, -2, @Agora)),
    (2, 120.00, 149.90, 269.90, 1, DATEADD(HOUR, -1, @Agora), DATEADD(HOUR, -1, @Agora));
GO

GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::dbo TO appchat;
GO
