# Veylor

Veylor é um aplicativo **beta** de comunicação por texto para Windows, Android e Linux, com cliente Flutter e backend Node.js/PostgreSQL. O objetivo é oferecer servidores, canais de texto e conversas privadas com sincronização em tempo real.

> **Estado atual:** V0.3.8 beta publicada; V0.4.0 em testes com sala de voz LiveKit. Um servidor LiveKit com credenciais é necessário para mídia real.

## Recursos atuais

- Cadastro, login, servidores, convites, cargos básicos e canais.
- Navegação desktop inspirada em mensageiros modernos: servidores, DMs, canais, chat, painel de membros responsivo e filtro local de mensagens.
- Identidade Veylor azul/ciano no Windows (app e instalador), Android e tela Flutter.
- Mensagens em canais e conversas privadas, com autorização pelo backend.
- WebSocket para avisos de atualização, reconexão progressiva e recuperação de mensagens via REST.
- Reenvio de mensagens com identificador de idempotência (evita duplicatas em timeout).
- Armazenamento de sessão local em Secure Storage do Flutter.
- Atualizações Android: abre a página oficial do GitHub, sem instalar APKs automaticamente.
- Atualizações Windows (V0.3.7+): baixa uma Release oficial no app com SHA-256 obrigatório e até três tentativas em falhas temporárias, solicita confirmação e usa helper externo com backup, recibo de inicialização e rollback em falha no setup ou na abertura inicial.
- Logs redigidos de atualização em `%LOCALAPPDATA%\\Veylor\\Logs`. A versão exibida na interface agora é consultada do pacote instalado.
- Servidor compatível com PostgreSQL ou SQLite local para desenvolvimento.

**V0.4.0 (beta em preparação):** permite entrar em salas de voz LiveKit e publicar tela no Windows/macOS, somente se a API tiver LiveKit configurado. Ainda não foram validadas chamadas de ponta a ponta em dois aparelhos. Não oferece gravação nem atualização silenciosa.

## Downloads beta

Depois de uma execução aprovada, procure os artefatos em **[GitHub Actions](https://github.com/night02/discord2/actions)**. O instalador Windows (`Setup-Windows-x64.exe`) e os pacotes portáteis são gerados separadamente. Os arquivos de Actions expiram após o prazo de retenção.

As **[GitHub Releases](https://github.com/night02/discord2/releases)** são o canal planejado para downloads duradouros. Uma prerelease é publicada automaticamente somente após builds e testes obrigatórios aprovados no mesmo commit de `main`. A instalação e a validação em dispositivos reais continuam manuais. Não considere uma tag ou APK disponível até que os arquivos realmente existam.

- **Windows:** instalar usando o Setup.exe ou extrair o pacote portátil completo (inclui DLLs).
- **Android:** APK debug exclusivamente para testes; assinatura permanente ainda pendente. Não há versão Play Store.
- **Linux:** extrair todo o tarball portátil.
- **iOS:** código Flutter possível, mas sem IPA compilado/assinado neste repositório.

Sem certificado Authenticode configurado, o instalador Windows é uma beta **não assinada**; o fluxo CI também testa instalação, integridade do executável e desinstalação. Não desative as proteções do sistema para instalar.

## Desenvolver localmente

Requisitos: Node.js 22 ou superior, Flutter stable, e as ferramentas nativas do sistema.

Backend SQLite de desenvolvimento:

```bash
cd apps/server
npm install
npm start
```

Cliente Flutter:

```bash
cd apps/client
flutter create --project-name veylor --platforms=windows,android,linux .
flutter pub get
flutter test
flutter run -d windows --dart-define=VEYLOR_API_URL=http://127.0.0.1:8080
```

Para o Android e outros computadores use uma URL HTTPS do backend acessível pela rede. Não publique credenciais, tokens, chaves Android, URLs PostgreSQL com senha nem arquivos `.env`.

## Integração e publicação

- PRs permanecem em rascunho até concluir testes Flutter, API SQLite/PostgreSQL, verificação HTTPS da API hospedada e os builds Windows/Linux/Android.
- O workflow **Veylor preview builds** compila Windows (`.exe` e ZIP), Android (APK debug) e Linux ao atualizar o código do cliente em `main`. **Veylor beta Releases** cria automaticamente uma *prerelease* numerada para cada build bem-sucedido, apenas quando Flutter, API SQLite/PostgreSQL e teste hospedado também passarem no MESMO SHA. Publicações nunca fazem deploy no Render. Os arquivos ficam em [Releases](https://github.com/night02/discord2/releases).
- A aplicação verifica apenas links HTTPS de `github.com/night02/discord2/actions/runs/...` ou `github.com/night02/discord2/releases/tag/vX.Y.Z-beta`; tags devem corresponder à versão anunciada.
- Somente após conferir os artefatos e a aplicação em Windows e Android reais, atualizar os manifestos da API no Render.
- O backend hospedado e o banco PostgreSQL são ambientes separados do ciclo de CI. Nenhum merge de código, por si só, deve apagar ou migrar dados do servidor.

## Documentação

- [Arquitetura](docs/ARCHITECTURE.md)
- [Estratégia de releases V0.3.4](docs/V0.3.4_RELEASES.md)
- [Estabilidade V0.3.3](docs/V0.3.3_STABILITY.md)
- [Instaladores e assinatura Android](docs/INSTALLERS.md)
- [Atualizador Windows e recuperação V0.3.6](docs/V0.3.6_UPDATER.md)
- [Watchdog e rollback V0.3.7](docs/V0.3.7_UPDATER.md)
- [Interface e identidade visual V0.3.8](docs/V0.3.8_INTERFACE.md)
- [Salas LiveKit e transmissão experimental V0.4.0](docs/V0.4.0_VOICE.md)
- [PostgreSQL no Render](docs/RENDER_STAGING.md)

**Importante:** o banco PostgreSQL gratuito do ambiente de homologação foi criado com vencimento previsto para **11/11/2026**. Faça migração/backup para armazenamento durável antes de manter usuários reais nessa base.
