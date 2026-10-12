# PostgreSQL migration — Veylor

## Estado

- `feature/veylor-postgres` inclui PostgreSQL como backend selecionado automaticamente quando `DATABASE_URL` existe.
- Quando `DATABASE_URL` não existe, o Veylor mantém SQLite para desenvolvimento e rollback.
- **Nenhum deploy de produção foi feito.**
- A conta Render `My Workspace` já utiliza seu único banco PostgreSQL gratuito em outro projeto. O Render rejeitou criar um segundo banco gratuito. Não misture as tabelas dos dois projetos nem contrate recursos sem aprovação.
- Um banco Render PostgreSQL gratuito expira após o período de avaliação; não serve como persistência permanente.

## Dependências

Node.js 22.13+, PostgreSQL e o driver `pg` na API.

```bash
cd apps/server
npm install
DATABASE_URL=postgres://usuario:senha@host:5432/veylor npm start
```

O schema PostgreSQL é criado no startup. Nunca publique `DATABASE_URL` no repositório; configure-o apenas em variáveis de ambiente protegidas.

## Pré-condições para migração real

1. Obter um PostgreSQL **dedicado ao Veylor**, vazio, persistente e com backups. O plano deve ser explicitamente aprovado antes de qualquer cobrança.
2. Restringir o acesso de escrita à API SQLite anterior e colocar o sistema em manutenção para obter um snapshot consistente. **Não copie o banco enquanto usuários estiverem escrevendo.**
3. Gerar ou extrair um snapshot confiável do SQLite, preservando tabelas, contas, sessões, membros, canais e mensagens. No Render gratuito o disco é efêmero; se ele já reiniciou, dados antigos podem estar irrecuperáveis.
4. Executar o importador **offline** contra o snapshot e o PostgreSQL vazio. A ferramenta aborta se detectar dados no destino.
5. Conferir contagens e amostras, testar login antigo, canais, DMs e WebSocket num **serviço Render de homologação** conectado ao PostgreSQL.
6. Somente depois direcionar clientes para a URL nova. Manter um backup offline cifrado para rollback e não permitir escrita simultânea nos dois bancos.

## Importar um snapshot

Na raiz do repositório, com as dependências instaladas em `apps/server`:

```bash
DATABASE_URL='postgres://...' node apps/server/scripts/import-sqlite.mjs --confirm /caminho/veylor.sqlite
```

No Windows PowerShell:

```powershell
$env:DATABASE_URL = 'postgres://...'
node apps/server/scripts/import-sqlite.mjs --confirm 'C:\caminho\veylor.sqlite'
```

A operação é transacional, verifica a integridade SQLite, preserva IDs e sequências de mensagens e exige as nove tabelas vazias no destino. Nenhuma credencial ou conteúdo de mensagens é mostrado no resumo de importação. O arquivo SQLite original permanece inalterado.

Não compartilhe URL de banco, senhas ou snapshots de usuários num chat ou commit.

## Testes CI

O GitHub Actions inicializa um PostgreSQL descartável, importa uma base fictícia, valida que tentativas de importação repetida são recusadas e testa a API de mensagens e permissões, inclusive persistência após reiniciar o processo Node.

Esses testes não substituem os testes de recuperação de backup, carga, segurança e privacidade de produção.

## Atualizações do aplicativo

A API V0.2.1 contém `GET /api/updates/android`. Não habilite esse fluxo no Render antes do banco persistente e da revisão de assinatura do APK. Builds `debug` podem usar certificados diferentes e não garantem atualização sobre versões instaladas.
