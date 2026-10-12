# GitHub Actions — falha antes de iniciar os jobs (12/10/2026)

## Evidências observadas no repositório privado

- Runs recentes, como [38283435396](https://github.com/Night0231-creator/discord2/actions/runs/38283435396) (API), [38283435385](https://github.com/Night0231-creator/discord2/actions/runs/38283435385) (Flutter) e [38283435324](https://github.com/Night0231-creator/discord2/actions/runs/38283435324) (builds), falharam de imediato.
- Os jobs ficaram com `steps: null` (nenhuma etapa iniciou). Os endpoints de logs responderam 404 / `BlobNotFound`. Reexecutar os jobs reproduziu o mesmo comportamento.
- Antes dessa anomalia, os testes no GitHub Actions haviam passado: [API SQLite/PostgreSQL](https://github.com/Night0231-creator/discord2/actions/runs/38282919919), [Flutter](https://github.com/Night0231-creator/discord2/actions/runs/38282919795), [saúde da API hospedada](https://github.com/Night0231-creator/discord2/actions/runs/38282919789).
- O GitHub registrou um incidente no mesmo dia, afetando Actions, filas de execução e Checks: https://www.githubstatus.com/. Não foi possível confirmar se o incidente é a causa exclusiva desta conta.
- **Não** atribuir falhas com zero etapas à sintaxe do workflow ou ao backend sem prova. Também é possível restrição de minutos, gastos, pagamentos ou configuração da conta.

## Conferência necessária pelo proprietário da conta

1. Abra https://github.com/settings/billing — **Billing & Licensing → Usage**. Filtre por **Actions**. Confira se o limite gratuito/mensal, o orçamento ou os gastos impediram novas execuções. Não habilite cobranças sem decisão explícita.
2. Abra https://github.com/Night0231-creator/discord2/settings/actions — confirme que Actions está habilitado para o repositório privado, que os workflows e runners GitHub-hosted são permitidos e que nenhuma política está bloqueando o job.
3. Abra um dos runs com falha no navegador. Confira **a mensagem no topo da execução** — principalmente falha de faturamento, minutos esgotados, runner não atribuído ou falha interna de GitHub. Se existir um banner de erro, compartilhe apenas a mensagem (sem tokens, dados pessoais nem segredos).
4. Consulte https://www.githubstatus.com/ . Quando estiver estável, reexecute **primeiro** o workflow simples **Veylor hosted Postgres health**; se ele passar, reexecute os testes API, Flutter e, por último, os três builds.
5. Só publique beta quando **todos os jobs do último commit** tiverem resultado `success`; links de downloads antigos não provam o estado do novo commit. Não altere Render, banco ou instale builds com CI incompleto.

## Alternativa gratuita sem runners GitHub

Com o repositório clonado no seu Windows 10/11, execute o script local `tools/build-veylor-windows.ps1` (leia-o antes). Necessário: Node.js 22+, Flutter SDK estável, Visual Studio com Desktop development with C++, Inno Setup 6. Para executar na pasta raiz:

```powershell
powershell -File .\tools\build-veylor-windows.ps1
```

O script executa testes Node/SQLite locais, análise e testes Flutter, compila Windows, cria ZIP e instalador Inno Setup e salva SHA256 em `dist/`. **Não acessa credenciais de produção nem o banco remoto.** Se não houver dependências, interrompe sem gerar instalador não validado. O script é um fallback preparado; ainda precisa ser executado no Windows equipado com o ambiente de compilação.

A compilação Android requer Flutter/Android SDK/JDK e uma assinatura estável específica, que são separados deste fallback Windows. Não tente desligar Windows Defender/SmartScreen para instalar o aplicativo.

## Situação do projeto

Código da V0.3.3: `feature/veylor-v0.3.3-stability`, [PR #5](https://github.com/Night0231-creator/discord2/pull/5), mantido **draft**. PostgreSQL do Veylor inalterado. Nenhum instalador V0.3.3 deve ser anunciado como aprovado até testes e builds completos.
