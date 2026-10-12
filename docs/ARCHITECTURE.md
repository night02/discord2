# Veylor 2.0 - Arquitetura

```
Flutter UI (Windows/Linux/Android/iOS)
            |
          HTTPS
            |
    Node API/Auth/Chat
      SQLite (MVP)
     PostgreSQL (futuro)
            |
      Media Auth API
            |
       LiveKit SFU
            |
  Captura nativa + encode GPU
```

## Roadmap
1. **v0.1:** interface Flutter, API com sessão e isolamento de servidores, convites, chat por polling.
2. **v0.2:** WebSockets, DMs, cargos/permissões, persistência segura de sessão por plataforma.
3. **v0.3:** integração real LiveKit áudio/câmera/captura em desktop e mobile, testes de 1080p60.
4. **v0.4:** 1440p60 e 4K60 experimental, bitrate adaptativo, telemetria e qualidade real medida.
5. **v0.5:** distribuidores Windows/Linux/Android e pipeline macOS/Xcode para iOS.

## Transmissão
Windows: Windows Graphics Capture; Linux Wayland: portal PipeWire; Android: MediaProjection; iOS: ReplayKit Broadcast Extension. Captura tem regras específicas por plataforma. Avaliar H.264 acelerado, AV1 onde suportado. Não prometer 4K/60 sem testes de captura, encode, rede, SFU e decode.

## Segurança
Autenticação para todas as rotas privadas, membership para canais, segredo de mídia exclusivamente no servidor, TLS, limites de requisição, antiabuso e moderação antes de abrir inscrições públicas. MVP usa SQLite e polling, ambos precisam evoluir para uma base escalável.
