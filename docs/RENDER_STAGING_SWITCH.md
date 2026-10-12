# Veylor — migração segura do Render para o repositório oficial

**Status:** procedimento preparado. A API em Render pode ainda apontar para
`Night0231-creator/discord2` e **a troca não acontece por editar apenas o GitHub**.

## Recursos existentes — NÃO recriar ou apagar

- Workspace Render: `My Workspace`
- Web service: `veylor-postgres-staging`, id `srv-db6g2mqd0e5s73akc500`
- URL: `https://veylor-postgres-staging.onrender.com`
- PostgreSQL: `veylor-postgres`, id `dpg-db6g0kajnfac73dkv1l0-a`
- Repo antigo do serviço: `Night0231-creator/discord2`
- Repo oficial: `night02/discord2`
- Branch validada para staging: `staging/veylor-v0.4.0-discord-livekit`

**Não copie a URL interna do PostgreSQL para logs, Discord, GitHub ou chat.
Não modifique a allowlist de rede externa do banco.**

## Troca de origem (no dashboard do Render)

1. Abra https://dashboard.render.com/web/srv-db6g2mqd0e5s73akc500
2. Confirme que **Auto-Deploy está desligado** e registre em local privado a
   configuração atual do serviço. A troca de origem poderá iniciar um deploy.
3. Em **Settings → Build → Source → Edit**, escolha **o repositório exato**
   `night02/discord2` e a branch `staging/veylor-v0.4.0-discord-livekit`.
4. Deixe **Root Directory** vazio (raiz do repositório), runtime **Node**,
   Build Command `cd apps/server && npm install --omit=dev --no-audit --no-fund`,
   Start Command `node apps/server/server.mjs`.
5. Em **Environment**, apenas confira que `DATABASE_URL` continua ligado ao
   PostgreSQL existente e que `REQUIRE_POSTGRES=1`. **Não** sobrescreva
   `DATABASE_URL`, não apague variáveis existentes e não ative fallback
   SQLite. Proteja todos os segredos em variáveis privadas.
6. Confirme o deploy e veja os logs do novo commit. Se houver falha,
   interrompa o rollout e volte à configuração anterior registrada. Não
   force uma migração destrutiva ou substituição de banco.

## Ordem de verificação após deploy

1. **GET `/health`** retorna 200, `status=ok` e `storage=postgres`.
   Se não houver conexão com o banco, o servidor deve falhar em vez de
   criar SQLite vazio.
2. Confirme login Veylor por usuário/senha EXISTENTE, servidores, canais e
   mensagens anteriores. Não crie dados de teste na conta de outras pessoas.
3. Com sessão autenticada, acesse **GET `/api/integrations/status`**.
   Resposta esperada, sem valores de credenciais:

   ```json
   {"discord":{"configured":false},"livekit":{"configured":false}}
   ```

   Cada flag passa para `true` apenas quando o conjunto respectivo de
   variáveis do serviço estiver corretamente formatado. **Isso não significa**
   que a conta Discord real ou a chamada entre dois aparelhos já tenha sido
   testada.
4. Cadastre no Discord Developer Portal OAuth2 Redirect URI EXATAMENTE:
   `https://veylor-postgres-staging.onrender.com/api/auth/discord/callback`.
   No Render configure `DISCORD_CLIENT_ID`, `DISCORD_CLIENT_SECRET` e
   `DISCORD_REDIRECT_URI` como environment privado. Nunca envie
   `DISCORD_CLIENT_SECRET` no chat.
5. No LiveKit Cloud crie um projeto de teste e configure no Render
   `LIVEKIT_URL` (`wss://...`), `LIVEKIT_API_KEY` e
   `LIVEKIT_API_SECRET`, privados. Teste em dois dispositivos com microfone
   e câmera desligados por padrão, depois ative voluntariamente.
6. Verifique se o endpoint de configuração exige **Bearer Veylor válido**
   e se jamais revela senha, token ou API key. Teste consentimento Discord
   negado, retorno ao app e expiração do fluxo.
7. Só depois atualize o manifesto público de novas betas e publique
   instaladores se o mesmo commit passar os checks completos de CI.

## Limitações

- A integração atual do Render não oferece ação para trocar a origem Git de
  um web service existente; realizar a etapa 3 no Dashboard.
- Nenhuma release substitui testes de áudio/vídeo PC ↔ Android com usuário real.
- A edição da origem do serviço não altera automaticamente as configurações
  do Discord Developer Portal ou cria projetos LiveKit.
- Free PostgreSQL listado com expiração em **11/11/2026** no Render:
  planejar backup e retenção ANTES desse prazo, sem abrir acesso externo.
- O PR V0.4.0 pode permanecer draft até validar as credenciais e os testes
  reais; a beta V0.3.8 publicada segue preservada.
