# CoreERP Database

Modelo inicial do CoreERP em **PostgreSQL**, preparado para uma plataforma ERP genérica com mais de uma empresa na mesma instalação.

## Estado atual

Este repositório define a estrutura e os scripts de criação do banco. **A API ainda não está conectada a ele**: clientes, produtos e pedidos da versão atual ficam em memória e desaparecem ao reiniciar o Node. Aqui já fica o destino de persistência para a próxima etapa.

## O que o schema cobre

- Empresas, usuários e associação de usuários às empresas.
- Clientes, fornecedores, produtos e depósitos.
- Saldo atual e livro de movimentações de estoque.
- Pedidos de venda e itens.
- Pedidos de compra e itens.
- Contas a receber e a pagar.
- Valores monetários em centavos inteiros e quantidades em decimal.
- Chaves estrangeiras compostas que impedem ligar registros de empresas diferentes.
- Atualização transacional do saldo ao registrar uma movimentação de estoque.

## Aplicar localmente

Requer PostgreSQL instalado e `psql` disponível. Crie o banco vazio:

```bash
psql -v ON_ERROR_STOP=1 -d postgres -f database/000_create_database.sql
psql -v ON_ERROR_STOP=1 -d coreerp -f database/001_initial_schema.sql
psql -v ON_ERROR_STOP=1 -d coreerp -f database/002_stock_ledger.sql
```

Cada arquivo é uma migração versionada. A tabela `schema_migrations` registra o que foi aplicado. Execute as migrações uma única vez em cada banco; faça backup antes de aplicar mudanças em ambientes com dados.

## Como o isolamento por empresa funciona

Tabelas de negócio possuem `organization_id`. As referências entre cliente, pedido, produto, depósito e empresa usam chaves compostas incluindo esse identificador. Isso bloqueia associações entre empresas diferentes no próprio banco.

O serviço ainda precisa autenticar o usuário e verificar a associação dele à empresa em cada request. O banco não substitui essa autorização; Row Level Security ainda não foi ativado nesta versão.

## Módulos conectados

- [API](https://github.com/Mateus-Neinas/coreerp-api): hoje mantém dados temporários em memória; futura integração migrará clientes, produtos e pedidos para estas tabelas.
- [Estoque](https://github.com/Mateus-Neinas/coreerp-inventory): movimentos e saldos.
- [Compras](https://github.com/Mateus-Neinas/coreerp-purchasing): fornecedores e pedidos de compra.
- [Financeiro](https://github.com/Mateus-Neinas/coreerp-finance): contas a pagar e receber.
- [Backend Java](https://github.com/Mateus-Neinas/coreerp-backend-java): relatórios agregados.

## Limites

Este é um schema inicial, ainda sem autenticação integrada, políticas RLS, migrations automáticas na aplicação, auditoria completa ou regras fiscais. Use dados fictícios até essas camadas serem implementadas e revisadas.
