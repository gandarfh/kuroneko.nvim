# kuroneko.nvim

As reuniões do [Kuroneko](https://github.com/gandarfh/kuroneko) no Neovim: ler a transcrição, ouvir, dizer quem falou, anotar, guardar links, marcar pendências como feitas e resumir com o Claude.

O plugin fala só com o comando `kuroneko`, que vem com o app e responde em JSON; nunca abre o banco direto.

## Requisitos

- Neovim 0.10 ou mais novo.
- O app Kuroneko instalado (traz o comando `kuroneko`):

  ```sh
  curl -fsSL https://github.com/gandarfh/kuroneko/releases/latest/download/install.sh | sh
  ```

- Opcional: [Telescope](https://github.com/nvim-telescope/telescope.nvim), para escolher reuniões com a transcrição na prévia. Sem ele, usa `vim.ui.select`.

## Instalação

Com [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "gandarfh/kuroneko.nvim",
  cmd = "Kuroneko",
  opts = {},
}
```

## Comandos

| Comando | O que faz |
| --- | --- |
| `:Kuroneko` | escolher uma reunião (com notas, resumo e pendências abertas de cada uma) |
| `:Kuroneko open <id>` | abrir a reunião |
| `:Kuroneko search [texto]` | buscar em falas e notas de todas as reuniões |
| `:Kuroneko tasks` | pendências abertas de todas as reuniões |
| `:Kuroneko summarize` | gerar com o Claude o resumo da reunião aberta |
| `:Kuroneko stop` | parar o áudio |

## Na reunião

`kuroneko://<id>` mostra o título, a data e quem falou; os links da reunião (🔗, um por linha, com o rótulo); o resumo em Markdown, com as decisões e as pendências; e a transcrição, com as notas (📝), os prints de cada nota (📎) e o que estava sendo dito naquele momento (↳). Enquanto a reunião está sendo gravada, o buffer se atualiza sozinho.

| Tecla | O que faz |
| --- | --- |
| `<CR>` | tocar daqui (na nota: o assunto; no resumo: o `[mm:ss]`); num link ou print: abrir |
| `x` | parar |
| `r` | dizer quem é a voz da fala |
| `a` | nova nota neste momento (ou onde o áudio está) |
| `D` | apagar a nota ou o link |
| `gl` | guardar um link da reunião: pede a URL (sugere a que está copiada) e um título opcional |
| `c` | marcar a pendência como feita, ou reabrir: uma linha das Pendências do resumo ou uma nota `#acao` |
| `S` | gerar o resumo com o Claude |
| `gS` | editar o resumo (`:w` salva) |
| `]n` / `[n` | próxima / anterior nota |
| `R` | recarregar |
| `q` | fechar |
| `g?` | ajuda |

## Pendências

`:Kuroneko tasks` abre `kuroneko://tasks`: as pendências abertas de todas as reuniões, sob a reunião de onde vieram (título e data), cada uma com o dono e o momento da gravação. Uma pendência é uma linha da seção Pendências do resumo ou uma nota com `#acao`. A que for marcada como feita continua na lista, com `[x]`, até recarregar.

| Tecla | O que faz |
| --- | --- |
| `<CR>` | abrir a reunião no momento da pendência (no título: abrir a reunião) |
| `c` | marcar como feita, ou reabrir |
| `p` | tocar a reunião a partir desse momento |
| `x` | parar |
| `R` | recarregar (as feitas saem da lista) |
| `q` | fechar |
| `g?` | ajuda |

## Configuração

Os valores abaixo são os padrões, exceto as teclas de exemplo:

```lua
require("kuroneko").setup({
  -- O comando kuroneko (instalado com o app).
  cmd = "kuroneko",
  -- Teclas na reunião; false deixa a ação sem tecla.
  keys = { link = "<leader>kl", toggle_task = "<leader>kc" },
  -- Teclas na lista de pendências, do mesmo jeito.
  tasks_keys = { play = "<leader>kp" },
  -- Opções dos pickers do Telescope, por exemplo require("telescope.themes").get_dropdown().
  telescope = {},
})
```

Nomes das ações em `keys`: `play`, `stop`, `rename`, `note`, `delete_note`, `link`, `toggle_task`, `summarize`, `edit_summary`, `next_note`, `prev_note`, `reload`, `close`, `help`.

Em `tasks_keys`: `open`, `toggle_task`, `play`, `stop`, `reload`, `close`, `help`.

Cores (todas com `default = true`, então o colorscheme pode trocar): `KuronekoSpeaker1`…`KuronekoSpeaker8` (vozes), `KuronekoMe` (você), `KuronekoTime`, `KuronekoNote`, `KuronekoContext`, `KuronekoPlaying` (o trecho tocando), `KuronekoLink` (links e prints) e `KuronekoDone` (pendências feitas).

## Testes

```sh
nvim --headless --clean -c "luafile tests/run.lua"
```

Não precisam do app: o comando `kuroneko` é trocado por um falso que responde com os JSON de `tests/fixtures`, e prompts, navegador e áudio são simulados. Sai com código 1 se algum teste falhar.
