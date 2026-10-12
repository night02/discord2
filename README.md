# Veylor

Veylor é um aplicativo **beta** de comunicação por texto para Windows, Android e Linux, com cliente Flutter e backend Node.js/PostgreSQL. O objetivo é oferecer servidores, canais de texto e conversas privadas com sincronização em tempo real.

> **Estado atual:** V0.3.4 em desenvolvimento. O `main` pode estar atrás da branch de testes. Não trate builds de depuração como versão estável.

## Recursos atuais

- Cadastro, login, servidores, convites, cargos básicos e canais.
- Mensagens em canais e conversas privadas, com autorização pelo backend.
- WebSocket para avisos de atualização, reconexão progressiva e recuperação de mensagens via REST.
- Reenvio de mensagens com identificador de idempotência (evita duplicatas em timeout).
- Armazenamento de sessão local em Secure Storage do Flutter.
- Verificador de novas versões no Windows e Android: abre a página oficial do GitHub, sem executar downloads automaticamente.
- Servidor compatível com PostgreSQL ou SQLite local para desenvolvimento.

**Ainda não oferece chamadas de voz, vídeo, compartilhamento de tela nem atualização silenciosa.** Canais de voz podem existir na interface, mas a conexão de mídia não está concluída.

## Downloads beta

Depois de uma execução aprovada, procure os artefatos em **[GitHub Actions](https://github.com/night02/discord2/actions)**. O instalador Windows (`Setup-Windows-x64.exe`) e os pacotes portáteis são gerados separadamente. Os arquivos de Actions expiram após o prazo de retenção.

As **[GitHub Releases](https://github.com/night02/discord2/releases)** são o canal planejado para downloads duradouros. Uma prerelease só será anunciada após **testes completos e publicação manual**. Não considere uma tag ou APK disponível até que os arquivos realmente existam.

- **Windows:** instalar usando o Setup.exe ou extrair o pacote portátil completo (inclui DLLs).
- **Android:** APK debug exclusivamente para testes; assinatura permanente ainda pendente. Não há versão Play Store.
- **Linux:** extrair todo o tarball portátil.
- **iOS:** código Flutter possível, mas sem IPA compilado/assinado neste repositório.

O instalador Windows ainda não está assinado com certificado Authenticode. Não desative as proteções do sistema para instalar.

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
- O workflow de **GitHub Releases** publica apenas **manualmente**, a partir do **commit testado no branch `main`**. O branch `main` gera seus próprios builds e checagens para garantir o mesmo SHA.
- A aplicação verifica apenas links HTTPS de `github.com/night02/discord2/actions/runs/...` ou `github.com/night02/discord2/releases/tag/vX.Y.Z-beta`; tags devem corresponder à versão anunciada.
- Somente após conferir os artefatos e a aplicação em Windows e Android reais, atualizar os manifestos da API no Render.
- O backend hospedado e o banco PostgreSQL são ambientes separados do ciclo de CI. Nenhum merge de código, por si só, deve apagar ou migrar dados do servidor.

## Documentação

- [Arquitetura](docs/ARCHITECTURE.md)
- [Estratégia de releases V0.3.4](docs/V0.3.4_RELEASES.md)
- [Estabilidade V0.3.3](docs/V0.3.3_STABILITY.md)
- [Instaladores e assinatura Android](docs/INSTALLERS.md)
- [PostgreSQL no Render](docs/RENDER_STAGING.md)

**Importante:** o banco PostgreSQL gratuito do ambiente de homologação foi criado com vencimento previsto para **11/11/2026**. Faça migração/backup para armazenamento durável antes de manter usuários reais nessa base.
