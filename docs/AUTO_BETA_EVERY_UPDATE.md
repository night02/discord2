# Veylor — publicação automática de cada atualização aprovada

**Regra de projeto:** toda atualização finalizada e integrada na branch
`main` deve produzir uma **nova beta** do aplicativo, identificada
separadamente, sem sobrescrever ou apagar versões anteriores.

## O que acontece automaticamente

1. Cada `push` em `main` inicia o workflow `Veylor preview builds`,
   inclusive alterações de servidor, documentação ou configuração.
2. O GitHub compila Windows (instalador `.exe` + ZIP portátil), Linux
   (`.tar.gz`) e Android (APK debug para testes). Os pacotes incluem
   `github.run_number` como **build number crescente**, além da versão
   semântica declarada em `apps/client/pubspec.yaml`.
3. O workflow `Veylor beta Releases` publica somente quando o **mesmo
   SHA de `main`** tiver:
   - Windows, Linux e Android compilados, com smoke tests do instalador
     e rollback aprovados;
   - `Flutter analyze and tests` aprovados;
   - `API tests` aprovados (SQLite **e** PostgreSQL).
4. Release publicada em `https://github.com/night02/discord2/releases`
   sob tag imutável `vMAJOR.MINOR.PATCH-beta.<run_id>`. Arquivos
   têm SHA-256 em `SHA256SUMS.txt`. Mantêm-se as releases antigas.
5. Caso qualquer gate falhe, **não há publicação**. Corrigir erro,
   executar CI novamente e publicar somente a versão aprovada.

## Render fica para o final

O `Veylor hosted Postgres health` continua como monitoramento independente.
O servidor Render foi adiado deliberadamente e a hospedagem antiga não é
pré-requisito para compilar o aplicativo offline. Por isso a publicação da
beta depende dos **testes de PostgreSQL descartável em CI**, não do
staging externo. Isso não comprova que Discord OAuth, LiveKit ou os dados
remotos estejam operacionais.

**Nenhum build do GitHub Actions modifica Render, seu PostgreSQL ou
configura um servidor LiveKit automaticamente.**

## Limites e transparência

- Uma edição no PR/branch de desenvolvimento **não** é uma atualização
  publicada; a nova beta sai depois da revisão, testes e merge em `main`.
- O aplicativo Windows ainda pode exibir SmartScreen sem certificado de
  assinatura Authenticode oficial.
- Android debug não é uma release Play Store; se houver chave de produção
  validada em GitHub Actions, também gera APK/AAB assinados.
- A notificação de atualização **dentro do aplicativo** ainda depende da
  API `/api/updates/windows` e `/api/updates/android` anunciar o build
  e tag novos. Enquanto Render estiver pendente, consultar manualmente
  a página de Releases.
- O número `github.run_number` é aplicado pelas builds automatizadas,
  não por `flutter run` local. Novas versões semânticas exigem atualizar
  `pubspec.yaml`, `windows-installer.iss` e os nomes de artefato juntos.
- Smoke tests não substituem teste real de voz, vídeo, câmera e
  supressão de ruído entre Windows e Android. Publicar beta não equivale
  a garantir que essas funções estejam ativas no servidor de produção.
