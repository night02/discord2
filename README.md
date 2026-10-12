# Veylor V0.2

Aplicativo de comunicação em desenvolvimento para Windows, Linux, Android e iOS.

## Incluído na V0.2
- DMs por nome de usuário com consultas autorizadas no backend.
- Notificações em tempo real autenticadas por WebSocket. REST permanece a fonte de verdade e há consulta de segurança a cada 30 s.
- Criação de canais de texto e voz por proprietário/moderador.
- Gestão básica de membros: proprietário concede/remove moderador; moderadores podem remover membros comuns.
- Sessão salva em armazenamento seguro nativo pelo pacote flutter_secure_storage.
- Migração de schema SQLite não destrutiva a partir da V0.1.

## Não implementado
- Streaming, voz e vídeo ainda não operacionais; LiveKit aguarda o cliente da V0.3.
- WebSocket distribui sinais de atualização, **não** payload de mensagens; dados só pela API autorizada.
- Não há presença persistente, typing indicators, moderação avançada, bloqueios de usuário ou uploads.
- Testes de carga, TLS, hardening, publicação e builds assinados ainda não foram concluídos.

## API
Node 22.13+:
```bash
cd apps/server
npm install
npm start
```

## Cliente
Flutter SDK mais ferramentas de cada destino:
```bash
cd apps/client
flutter create --project-name veylor --platforms=windows,linux,android,ios .
flutter pub get
flutter run -d windows --dart-define=VEYLOR_API_URL=http://127.0.0.1:8080
```
No Linux use `-d linux`. No Android/iOS configure endereço HTTPS acessível pelo dispositivo; o host local do seu PC não corresponde a 127.0.0.1 do celular. Windows requer Visual Studio Build Tools; Linux com flutter_secure_storage pode exigir pacote libsecret-1-dev e dependências de desktop; iOS requer Mac/Xcode, assinatura e permissões nativas.

**Segurança:** backend local para desenvolvimento. Sessões são armazenadas em Secure Storage no cliente, não em texto simples. Para disponibilização pública ainda faltam infraestrutura HTTPS/WSS, rate limit distribuído, controle de abuso e monitoramento. Mantenha LIVEKIT_API_SECRET somente no servidor.

Veja [arquitetura](docs/ARCHITECTURE.md).

## V0.2 Preview - teste multiplataforma

Os três pacotes são gerados pelo workflow [Veylor V0.2 preview builds](https://github.com/Night0231-creator/discord2/actions) na branch `feature/veylor-v0.2`.

- Windows x64: `Veylor-v0.2-Windows-x64.zip` com executável **e DLLs** (extraia o ZIP inteiro).
- Linux x64: `Veylor-v0.2-Linux-x64.tar.gz` contendo o bundle portátil.
- Android: `Veylor-v0.2-Android-debug` com `app-debug.apk`. Somente para testes, não Play Store.

Depois de um workflow bem-sucedido, use **Artifacts** na página da execução (conta GitHub com acesso ao repositório privado). Prazo de retenção de 7 dias. Builds não incluem servidor de mídia nem um backend hospedado.

Para conversar entre dispositivos: execute a API Node num host compartilhado e coloque-a atrás de HTTPS, entre no app > **Servidor** e digite sua URL `https://...` antes de fazer login. O aplicativo não envia tokens por HTTP remoto; somente `http://127.0.0.1` e `localhost` são permitidos para desenvolvimento. 

Se precisar testar via HTTP na LAN, a aplicação deve ser recompilada explicitamente com `--dart-define=ALLOW_INSECURE_DEV_API=true`, e a plataforma pode exigir configuração de tráfego não criptografado. Não utilize isso em produção.

O iOS exige Mac/Xcode e assinatura e **não** faz parte destes 3 pacotes.

## Atualizações de aplicativo Android (V0.2.1 beta)

O Veylor V0.2.1+3 verifica automaticamente a versão publicada quando inicia e permite verificar manualmente no login e em **Verificar atualização** na barra lateral.
A API fornece apenas metadados em `GET /api/updates/android`. O manifesto em `apps/server/mobile-release.json` aponta inicialmente para o último APK **testado** da V0.2.0+2. Não aponte o manifesto para novas versões antes de os builds passarem pelos testes.

**Limitações reais:** o APK está em um repositório privado do GitHub. É necessário acesso ao repositório para baixar os artefatos e a instalação é manual via sistema Android. Chaves de assinatura de builds debug podem mudar a cada execução do CI, impedindo instalar por cima da versão antiga. Para distribuição estável e upgrades preservando sessão, precisamos criar uma assinatura de release permanente e segura, armazenada como segredo de CI (nunca em GitHub público). A versão atual **não baixa e instala automaticamente** o APK.
