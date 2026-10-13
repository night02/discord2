# Veylor

Veylor é um aplicativo de comunicação para Windows, Android e Linux, com
Flutter, API Node.js e PostgreSQL (SQLite no desenvolvimento).

**V0.5.0: reconstrução do cliente.** Sessão, mensagens, reconexão e chamadas
estão separados da interface. Servidores, canais, membros, cargos básicos,
convites e conversas privadas usam a API real. A chamada continua conectada
durante a navegação. Os perfis de tela são liberados para todas as contas.

A V0.4.3 publicada foi preservada. A nova versão depende dos builds e checks
aprovados e deve ser identificada como V0.5.0. Não confunda o instalador antigo
com esta reconstrução. Não houve configuração/limpeza do Render ou exclusão
de contas e bancos.

LiveKit precisa ser configurado para chamadas reais. 1080p/60 e 1440p/30 são
experimentais. Áudio do jogo no Windows, captura de tela Android/Linux e IA
de supressão no Windows/Linux continuam pendentes; a interface informa isso.
Voz/transmissão devem ser testadas em aparelhos reais antes de serem chamadas
de estáveis.

[Detalhes da reconstrução e critérios de aceite](docs/V0.5.0_REBUILD.md)

[Builds no GitHub Actions](https://github.com/night02/discord2/actions) ·
[Betas publicadas](https://github.com/night02/discord2/releases)

Atualização Windows mantém SHA-256, confirmação, backup e rollback. Windows
continua beta sem Authenticode enquanto o certificado não for configurado;
Android permanece APK de teste enquanto a assinatura definitiva não existir.
Não há versão Play Store nem IPA assinado.

Requisitos de desenvolvimento: Node.js 22.13+, Flutter stable e ferramentas
nativas. Execute a API na raiz:

~~~bash
npm --prefix apps/server install
npm --prefix apps/server start
npm --prefix apps/server test
~~~

O teste padrão usa bancos temporários SQLite. DATABASE_URL normal nunca é
usada para testes; configure VEYLOR_TEST_DATABASE_URL com uma base descartável
se desejar validar PostgreSQL localmente.

Cliente, em apps/client:

~~~bash
flutter create --project-name veylor --platforms=windows,android,linux .
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter run -d windows --dart-define=VEYLOR_API_URL=http://127.0.0.1:8080
~~~

API remota exige HTTPS; mídia exige WSS. Senhas, tokens, chaves de assinatura
e arquivos .env não devem ser publicados. A configuração segue
[as instruções de hospedagem](docs/V0.4.3_HOSTING.md).

A publicação automática de beta depende de Flutter, API SQLite/PostgreSQL,
SFU e builds Windows/Android/Linux aprovados no mesmo commit. Os builds não
configuram a hospedagem nem instalam atualizações sem confirmação.
