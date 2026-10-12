# Conectar PostgreSQL ao Render — Veylor (homologação)

## Recursos existentes

- Banco PostgreSQL dedicado: **veylor-postgres** (ID: `dpg-db6g0kajnfac73dkv1l0-a`)
- API de homologação: **veylor-postgres-staging** (ID: `srv-db6g2mqd0e5s73akc500`)
- API anterior: **veylor-v02-api** (ID: `srv-db6f9pss728c738ahmt0`) — **não alterar ainda**

Banco: https://dashboard.render.com/d/dpg-db6g0kajnfac73dkv1l0-a

Homologação: https://dashboard.render.com/web/srv-db6g2mqd0e5s73akc500

## Passos obrigatórios no painel Render

1. Entre no PostgreSQL **veylor-postgres** e localize **Connections / Internal Database URL**. A API e o banco estão na mesma região (Virginia): use a URL **interna**, não a externa.
2. Copie a URL completa da conexão **somente dentro do próprio painel Render**.
3. Abra o serviço **veylor-postgres-staging** → **Environment** → adicione a variável `DATABASE_URL` e cole a URL.
4. Mantenha `REQUIRE_POSTGRES=true`, `HOST=0.0.0.0` e `PG_POOL_MAX=5`. Salve e inicie um deploy do serviço (a opção pode aparecer como **Save, deploy**).
5. Aguarde o deploy ficar **Live** e verifique `https://veylor-postgres-staging.onrender.com/health`. O esperado é uma resposta como `{"status":"ok","app":"Veylor","storage":"postgres"}`.

**Nunca publique a senha, a URL de conexão ou capturas com credenciais no GitHub, em chats ou no app Flutter.** Não é necessário liberar acesso externo nem mexer no IP allowlist do banco.

A API de homologação tem `autoDeploy` desligado: mudanças no código serão enviadas somente mediante deploy manual. Ela foi configurada para falhar de propósito se a variável `DATABASE_URL` estiver ausente.

## Validação após a conexão

Use somente **contas de teste fictícias**. Teste cadastro, login, canais, DMs, convites e reinicialização do serviço. Confirme que as mesmas contas e mensagens sobrevivem à reinicialização.

A API anterior continua em SQLite efêmero. **A migração de contas já existentes só poderá ocorrer depois de conseguir um snapshot confiável e consistente** da instância antiga. A integração Render disponível aqui não oferece acesso ao arquivo SQLite desse servidor, portanto não é possível prometer a migração automática dos dados existentes.

## Limites da versão gratuita

O banco gratuito atual vence **11 de novembro de 2026** e não é solução definitiva para contas reais. Planeje atualização de plano ou migração para armazenamento durável ANTES da expiração; verifique as condições vigentes na sua conta Render.

## Próximas etapas

- Com a URL interna configurada no Render, confirmar o status Live e executar smoke tests de isolamento de contas.
- Somente depois discutir a migração dos dados atuais ou a mudança do endereço usado pelos clientes.
- Preparar assinatura Android permanente fora do repositório; os APKs debug ainda podem exigir reinstalação.
