# Veylor V0.3.5 — assinatura Windows e Android / Google Play

A versão V0.3.4 saiu como beta com Windows **não assinado pelo editor** e Android **debug de teste**. Na V0.3.5, a compilação de editor assinada será ativada automaticamente **depois** que as credenciais corretas forem cadastradas. Não confundimos SHA-256 de download com identidade de editor.

## Android: APK de release e AAB para Play Console

Para novos aplicativos a Google Play usa Android App Bundles (AAB). A chave de upload Android pode ser criada gratuitamente no próprio Windows.

**Criar chave permanente:** instale JDK 17+ e execute localmente no PowerShell:

~~~powershell
keytool -genkeypair -v -keystore veylor-upload.jks -alias veylor -keyalg RSA -keysize 3072 -validity 10000
~~~

Guarde o JKS e senhas num backup criptografado. Não envie a chave nem senhas para este chat.

**Obter fingerprint SHA256 para validar a identidade (público):**

~~~powershell
keytool -list -v -keystore .\veylor-upload.jks -alias veylor
~~~

**Converter JKS em Base64 localmente (dado PRIVADO):**

~~~powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path ".\veylor-upload.jks")))
~~~

No repositório, abra https://github.com/night02/discord2/settings/secrets/actions e adicione os **cinco** Repository secrets sem enviar os valores pelo chat:

| GitHub Secret | Conteúdo |
|---|---|
| VEYLOR_ANDROID_KEYSTORE_BASE64 | Conteúdo Base64 do JKS |
| VEYLOR_ANDROID_STORE_PASSWORD | Senha do armazenamento |
| VEYLOR_ANDROID_KEY_ALIAS | Alias veylor |
| VEYLOR_ANDROID_KEY_PASSWORD | Senha da chave |
| VEYLOR_ANDROID_CERT_SHA256 | Fingerprint SHA256 (64 dígitos hex; com ou sem dois-pontos) |

**Com esses secrets configurados**, o workflow automático da branch main gera APK release e AAB release, verifica assinatura com apksigner/jarsigner, compara certificado ao fingerprint e publica os arquivos somente quando ambos passaram. Também é possível executar o workflow manual "Veylor Android signed beta".

O identificador Android da versão assinada é **com.veylor.app** e não deve mudar depois do lançamento. O APK debug anterior pode usar outro identificador ou assinatura, e talvez não atualize por cima.

**Para aparecer na Play Store ainda faltam etapas no Play Console:** abrir/verificar conta de desenvolvedor, cadastrar app e Play App Signing, enviar AAB, fornecer ícone, capturas, política de privacidade, declaração de coleta/uso de dados, classificação indicativa, testes e cumprir requisitos atuais de versão Android e revisão da loja. O AAB assinado não publica sozinho nem garante aprovação.

## Windows: certificado confiável Authenticode

A assinatura confiável exige identidade de publicador obtida com uma autoridade certificadora / serviço de assinatura confiável, **não** um certificado autoassinado. O SignTool assina o executável interno e instalador final com SHA-256 e timestamp, e depois verifica a confiança com SignTool.

Se você possui **um certificado legítimo de assinatura de código exportável em PFX**, gere o Base64 no seu PC:

~~~powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path ".\seu-certificado.pfx")))
~~~

Adicione diretamente em https://github.com/night02/discord2/settings/secrets/actions:

| GitHub Secret | Conteúdo |
|---|---|
| VEYLOR_WINDOWS_PFX_BASE64 | PFX Base64 |
| VEYLOR_WINDOWS_PFX_PASSWORD | Senha do PFX |

Nunca envie o PFX ou senha pelo chat. **Muitos certificados de assinatura de código recentes exigem hardware e não são exportáveis em PFX**. Para eles, será necessário configurar um serviço de assinatura remota (como Azure Artifact Signing) ou hardware dedicado em vez desta opção. Não contorne a proteção da chave privada.

Se os secrets de Windows não existirem, os builds continuam como beta **não assinada** e a publicação indica esse estado. Se as credenciais estiverem incompletas ou a assinatura não for verificada, a compilação falha e o sistema não divulga uma assinatura inexistente.

A assinatura não elimina necessariamente avisos do SmartScreen imediatamente; a reputação do software também pode influenciar. Não desative proteções do Windows.

## Publicação e atualizações futuras

O workflow automático compila Windows (instalador EXE e ZIP portátil), Linux, Android debug, e, se configurado, Android release (APK e AAB) e Windows Authenticode.

A Release só é criada para um commit exato da branch main com todos os testes aprovados. Verifica integridade e inclui SHA256SUMS.txt. As versões anteriores são preservadas. Os arquivos opcionais de Android assinado não são publicados se incompletos.

Página oficial: https://github.com/night02/discord2/releases

**Limitações reais:** ainda é necessário testar no Windows e Android físicos antes de declarar a versão estável. O cliente abre páginas de download, mas não executa atualizações silenciosas. O servidor e PostgreSQL do Render não são atualizados automaticamente. O PostgreSQL gratuito da homologação tem vencimento previsto para 11/11/2026.
