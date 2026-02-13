-- ~/.config/nvim/lua/plugins/ai.lua
-- AI integration: avante.nvim (Cursor-like) + GitHub Copilot (inline completions)

return {
  ---------------------------------------------------------------------------
  -- avante.nvim — Cursor-like AI agent inside Neovim
  ---------------------------------------------------------------------------
  {
    "yetone/avante.nvim",
    event = "VeryLazy",
    lazy = false,
    version = false,
    build = "make",
    opts = {
      -- Default provider: Claude (set ANTHROPIC_API_KEY in your shell)
      provider = "claude",
      providers = {
        claude = {
          endpoint = "https://api.anthropic.com",
          model = "claude-sonnet-4-20250514",
          auth_type = "max", -- use Claude subscription login (Pro/Max), not API-key billing
          api_key_name = "ANTHROPIC_API_KEY", -- optional fallback if auth_type is switched back to "api"
          timeout = 30000,
          extra_request_body = {
            temperature = 0.7,
            max_tokens = 20480,
          },
        },
        -- Uncomment to add OpenAI as alternative (switch with :AvanteSwitchProvider)
        -- openai = {
        --   endpoint = "https://api.openai.com/v1",
        --   model = "gpt-4o",
        --   api_key_name = "OPENAI_API_KEY",
        --   timeout = 30000,
        -- },
      },
      -- Appearance
      windows = {
        width = 40,          -- sidebar width (%)
        sidebar_header = {
          align = "center",
          rounded = true,
        },
      },
      -- Keymaps (these are the defaults, listed for reference)
      mappings = {
        ask = "<leader>aa",
        edit = "<leader>ae",
        refresh = "<leader>ar",
        toggle = {
          default = "<leader>at",
          debug = "<leader>ad",
          hint = "<leader>ah",
          suggestion = "<leader>as",
        },
      },
    },
    dependencies = {
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      "nvim-telescope/telescope.nvim",
      "saghen/blink.compat",
      "nvim-tree/nvim-web-devicons",
      -- Optional: render markdown in avante's chat window
      {
        "MeanderingProgrammer/render-markdown.nvim",
        opts = {
          file_types = { "markdown", "Avante" },
        },
        ft = { "markdown", "Avante" },
      },
    },
  },
  {
    "saghen/blink.cmp",
    optional = true,
    opts = function(_, opts)
      opts.sources = opts.sources or {}
      opts.sources.compat = opts.sources.compat or {}

      for _, source in ipairs({ "avante_commands", "avante_mentions", "avante_files", "avante_shortcuts" }) do
        if not vim.tbl_contains(opts.sources.compat, source) then
          table.insert(opts.sources.compat, source)
        end
      end

      opts.sources.providers = opts.sources.providers or {}
      opts.sources.providers.avante_commands = {
        name = "avante_commands",
        module = "blink.compat.source",
        score_offset = 90,
        opts = {},
      }
      opts.sources.providers.avante_files = {
        name = "avante_files",
        module = "blink.compat.source",
        score_offset = 100,
        opts = {},
      }
      opts.sources.providers.avante_mentions = {
        name = "avante_mentions",
        module = "blink.compat.source",
        score_offset = 1000,
        opts = {},
      }
      opts.sources.providers.avante_shortcuts = {
        name = "avante_shortcuts",
        module = "blink.compat.source",
        score_offset = 1000,
        opts = {},
      }
    end,
  },

  ---------------------------------------------------------------------------
  -- GitHub Copilot — inline ghost-text completions
  ---------------------------------------------------------------------------
  {
    "zbirenbaum/copilot.lua",
    cmd = "Copilot",
    event = "InsertEnter",
    opts = {
      suggestion = {
        enabled = true,
        auto_trigger = true,
        debounce = 75,
        keymap = {
          accept = "<Tab>",
          accept_word = "<C-Right>",
          accept_line = "<C-Down>",
          next = "<M-]>",
          prev = "<M-[>",
          dismiss = "<C-]>",
        },
      },
      panel = { enabled = false },     -- we use avante for chat, not copilot panel
      filetypes = {
        markdown = true,
        tex = true,
        python = true,
        lua = true,
        ["*"] = true,                  -- enable for all filetypes
      },
    },
  },

  ---------------------------------------------------------------------------
  -- CopilotChat — chat interface (lighter alternative to avante for quick Q&A)
  ---------------------------------------------------------------------------
  {
    "CopilotC-Nvim/CopilotChat.nvim",
    dependencies = {
      "zbirenbaum/copilot.lua",
      "nvim-lua/plenary.nvim",
    },
    cmd = {
      "CopilotChat",
      "CopilotChatExplain",
      "CopilotChatFix",
      "CopilotChatOptimize",
      "CopilotChatTests",
      "CopilotChatDocs",
    },
    opts = {
      model = "claude-3.5-sonnet",    -- use Claude via Copilot if available
      window = {
        layout = "vertical",
        width = 0.4,
      },
    },
    keys = {
      { "<leader>ac", "<cmd>CopilotChat<CR>", desc = "Copilot Chat" },
      { "<leader>ax", "<cmd>CopilotChatExplain<CR>", desc = "Copilot Explain", mode = { "n", "v" } },
      { "<leader>af", "<cmd>CopilotChatFix<CR>", desc = "Copilot Fix", mode = { "n", "v" } },
    },
  },
}
