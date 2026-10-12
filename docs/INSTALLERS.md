# Veylor V0.3.2 — instalador Windows e Android assinado

## Windows 10/11

O GitHub Actions compila dois pacotes para Windows x64:

- **Veylor-v0.3.2-Setup-Windows-x64.exe** — instalador Inno Setup, instala apenas para o usuário, cria atalho no Menu Iniciar, atalho opcional na Área de Trabalho e permite desinstalar em Aplicativos do Windows.
- **Veylor-v0.3.2-Windows-x64.zip** — pacote portátil; não execute o .exe sem os DLLs e a pasta \`data\` que acompanham o build Flutter.

O instalador é **não assinado digitalmente**. O Windows pode exibir SmartScreen/avisos de reputação. A assinatura Authenticode (certificado de publicação) ainda está pendente. Não recomende desligar o SmartScreen para instalar.

Os artefatos ficam no workflow **Veylor V0.3.2 preview builds** por prazo limitado e requerem acesso ao repositório privado. Uma versão pública precisa de canal de distribuição apropriado e assinatura antes de ser anunciada como estável.

## Android — APK beta com assinatura permanente

O workflow manual \`.github/workflows/android-signed.yml\` gera o APK de **release assinado** apenas depois de configurar quatro segredos nas configurações do GitHub:

| Segredo | Conteúdo |
| --- | --- |
| \`VEYLOR_ANDROID_KEYSTORE_BASE64\` | Conteúdo base64 do arquivo \`veylor-release.jks\`, **sem aspas** |
| \`VEYLOR_ANDROID_STORE_PASSWORD\` | Senha do keystore |
| \`VEYLOR_ANDROID_KEY_ALIAS\` | Nome do alias usado no keystore |
| \`VEYLOR_ANDROID_KEY_PASSWORD\` | Senha da chave |

Gerar **uma única chave permanente**, em um ambiente seu, com JDK instalado:

\`\`\`powershell
keytool -genkeypair -v -keystore veylor-release.jks -alias veylor -keyalg RSA -keysize 3072 -validity 10000
\`\`\`

Para obter o base64 no Windows PowerShell local:

\`\`\`powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path ".\veylor-release.jks")))
\`\`\`

Abra seu repositório → **Settings → Secrets and variables → Actions → New repository secret** e insira os segredos sem enviá-los no chat ou fazer commit. Depois vá até **Actions → Veylor Android signed beta → Run workflow**.

A chave é materializada somente no runner temporário e removida ao final. Guarde uma cópia cifrada e segura da chave original e suas senhas: **se perder a chave, não conseguirá atualizar instalações existentes com a mesma identidade Android**.

O build assinado usará \`applicationId=com.veylor.app\` para identificar o produto. APKs anteriores de depuração usam outro identificador e/ou certificado; os APKs assinados **não poderão substituir todos os APKs de teste já instalados**. A partir do primeiro release assinado a chave e o \`applicationId\` devem permanecer constantes.

A versão debug gratuita continua sendo compilada para testes automáticos separadamente. **Não** publique a versão assinada sem verificar login, banco de dados e uso em dois aparelhos reais.

## O que ainda não é automático

- Instalação de atualizações pelo próprio app: o Android abre o link de download, mas o usuário instala manualmente.
- Disponibilidade permanente: os artefatos do GitHub Actions expiram. É necessário publicar releases duradouros/um canal de distribuição antes de apontar o manifesto da API para eles.
- Assinatura do instalador Windows e atualização silenciosa do executável: ainda não implementadas.
- A assinatura Android só ocorrerá após você configurar os segredos no GitHub.

O backend PostgreSQL do Veylor está em https://veylor-postgres-staging.onrender.com. O PostgreSQL gratuito atual expira em **11/11/2026**. Não trate essa infraestrutura como produção duradoura sem migração de dados ou atualização do plano.

## Beta com download duradouro: GitHub Releases

O workflow `.github/workflows/publish-beta.yml` prepara a prerelease `v0.3.2-beta` a partir de um build de preview aprovado. **Publicação manual**, não por commit.

1. Aguarde os três jobs do workflow **Veylor V0.3.2 preview builds** terminarem com sucesso.
2. Anote o GitHub Actions Run ID da execução.
3. Quando o workflow estiver disponível no branch padrão, vá em **Actions → Veylor beta Releases → Run workflow**; selecione o branch de desenvolvimento e informe o Run ID.
4. Verifique os artefatos da prerelease, as somas SHA256 e teste o instalador.
5. Após a publicação e os testes reais, atualize o manifesto da API `GET /api/updates/windows` para apontar ao link oficial.

O destino previsto da prerelease é `https://github.com/Night0231-creator/discord2/releases/tag/v0.3.2-beta` — **não existe até que o workflow seja executado com sucesso**. Em repositório privado, apenas pessoas autorizadas no GitHub podem baixar esses arquivos. Os arquivos da release não estão sujeitos à retenção comum de 7/14 dias dos artifacts.

O pacote Android da prerelease será claramente marcado como **DEBUG, SOMENTE TESTE**, não assinado de forma permanente. O workflow não incorpora segredos no código.

**Importante:** GitHub Actions só permite executar `workflow_dispatch` pela interface quando o arquivo workflow também está presente no branch padrão. Não afirme que releases foram publicadas antes de verificar o tag e os assets.

A partir da V0.3.2, o Windows consulta `GET /api/updates/windows`, verifica a versão instalada e abre apenas páginas HTTPS do GitHub do projeto. Não há execução de arquivos remotos nem atualização silenciosa.