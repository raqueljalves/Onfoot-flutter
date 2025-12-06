# Configuração rápida da extensão `openai.chatgpt`

Siga estes passos para configurar e usar a extensão `openai.chatgpt` no workspace:

- **Adicionar chave da API (opções):**
  - Recomendo colocar sua chave da OpenAI em `User` settings ou no `Workspace` settings.
  - Para usar o workspace, abra `C:/Users/Raquel/Documents/onfoot_app/.vscode/settings.json` e cole sua chave em `openai.chatgpt.apiKey` (substitua a string vazia).

- **Usar variável de ambiente (alternativa):**
  - Para sessão atual do PowerShell (temporário):

```powershell
$env:OPENAI_API_KEY = "sua_chave_aqui"
```

  - Para definir para o usuário (persistente):

```powershell
[System.Environment]::SetEnvironmentVariable("OPENAI_API_KEY","sua_chave_aqui","User")
```

  - Depois de definir a variável de ambiente, reinicie o VS Code e o terminal integrado.

- **Configurações recomendadas já no workspace:**
  - `openai.chatgpt.model` está definido como `gpt-4o-mini` por padrão no `settings.json` do workspace.
  - `openai.chatgpt.showWelcome` está definido como `false` para evitar telas iniciais repetidas.

- **Como verificar / usar a extensão:**
  - Abra a Paleta de Comandos (Ctrl+Shift+P) e digite `ChatGPT` ou `OpenAI` para ver os comandos disponíveis pela extensão.
  - Se a extensão oferecer um comando para inserir a chave da API, use-o em vez de editar o arquivo manualmente.

- **Segurança:**
  - Evite comitar sua chave para o repositório. Coloque a chave em `User` settings ou use variáveis de ambiente.

Se quiser, eu posso:

- Colocar a chave diretamente no `settings.json` (se você colar a chave aqui) — eu recomendaria não colar chaves em bate-papo público.
- Alternativamente, configurar um snippet de tarefas para validar que a extensão consegue acessar a API.
