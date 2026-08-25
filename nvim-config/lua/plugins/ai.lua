-- ~/.config/nvim/lua/plugins/ai.lua
-- AI integration with explicit autonomy levels:
--
--   T0     copilot.lua FIM/NES: predict what is being typed.
--   T0.5   CodeCompanion + Copilot: transform the selected code inline.
--   T1/T2  claudecode.nvim: propose a bounded change in a native diff.
--   T3     CLI agents in isolated worktrees: investigate larger tasks.
--
-- The proposal lane is intentionally separate from the full-agent tmux
-- windows. See AI_ASSISTED_CODING_WORKFLOW.md for the safety contract.

return {
  ---------------------------------------------------------------------------
  -- T0 — Copilot FIM + next-edit suggestions
  ---------------------------------------------------------------------------
  {
    "zbirenbaum/copilot.lua",
    -- NES is a thin shim over copilot-lsp. Without this dependency,
    -- nes.enabled is silently downgraded to false during validation.
    dependencies = {
      {
        "copilotlsp-nvim/copilot-lsp",
        init = function()
          vim.g.copilot_nes_debounce = 500
        end,
      },
    },
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
      -- Insert-mode and normal-mode <Tab> do not collide. copilot.lua passes
      -- the native key through when no suggestion is pending.
      nes = {
        enabled = true,
        auto_trigger = true,
        keymap = {
          accept_and_goto = "<Tab>",
          accept = false,
          dismiss = "<Esc>",
        },
      },
      panel = { enabled = false },
      filetypes = {
        markdown = true,
        tex = true,
        python = true,
        lua = true,
        ["*"] = true,
      },
    },
  },

  ---------------------------------------------------------------------------
  -- T0.5 — Fast, selection-scoped CodeCompanion edit via Copilot HTTP
  ---------------------------------------------------------------------------
  {
    "olimorris/codecompanion.nvim",

    -- lazy-lock.json is machine-local. Pin the schema used by this config so
    -- "interactions.inline" and its diff keymaps cannot drift silently.
    version = "v19.22.0",

    cmd = "CodeCompanion",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
    },

    keys = {
      {
        "<leader>ai",
        ":CodeCompanion<CR>",
        desc = "AI inline edit (Copilot)",
        mode = "x",
      },
    },

    opts = {
      interactions = {
        inline = {
          -- Inline accepts HTTP adapters only. Pin an explicit model: "auto"
          -- deletes the model field from the request (copilot/init.lua:193) so
          -- GitHub picks its own default, which caps prompts at 12288 tokens,
          -- and the "auto" entry carries no `endpoint`, so requests also fall
          -- back to /chat/completions instead of /responses.
          adapter = {
            name = "copilot",
            -- 328k context, /responses, and the only policy=enabled model in
            -- the 5.6 family on this seat. Recheck with :CodeCompanionModels
            -- if the seat changes -- policy state is per-organisation.
            model = "gpt-5.6-luna",
          },
          keymaps = {
            accept_change = {
              modes = { n = "ga" },
              description = "Accept the inline edit",
            },
            reject_change = {
              modes = { n = "gr" },
              opts = { nowait = true },
              description = "Reject the inline edit",
            },
          },
        },
      },
      display = {
        inline = {
          layout = "vertical",
        },
      },
    },
  },

  ---------------------------------------------------------------------------
  -- T1/T2 — Claude Code proposals in Neovim
  ---------------------------------------------------------------------------
  {
    "coder/claudecode.nvim",

    -- Pinned because lazy-lock.json is machine-local and the proposal policy
    -- below depends on the diff lifecycle and internal accept API at this SHA.
    -- Bump only after rerunning the V0 freshness and lifecycle tests.
    commit = "2390c6e45c4789072c293ac69de051d169668b29",

    cmd = {
      "ClaudeCode",
      "ClaudeCodeFocus",
      "ClaudeCodeSelectModel",
      "ClaudeCodeAdd",
      "ClaudeCodeSend",
      "ClaudeCodeSendText",
      "ClaudeCodeTreeAdd",
      "ClaudeCodeStatus",
      "ClaudeCodeStart",
      "ClaudeCodeStop",
      "ClaudeCodeOpen",
      "ClaudeCodeClose",
      "ClaudeCodeDiffAccept",
      "ClaudeCodeDiffDeny",
      "ClaudeCodeCloseAllDiffs",
      "ClaudeCodeProposalStatus",
    },

    -- stylua: ignore
    keys = {
      { "<leader>a",  "",                              desc = "+ai", mode = { "n", "x" } },
      { "<leader>ac", "<cmd>ClaudeCode<CR>",           desc = "Toggle Claude", mode = { "n", "x" } },
      { "<leader>af", "<cmd>ClaudeCodeFocus<CR>",      desc = "Focus Claude", mode = { "n", "x" } },
      { "<leader>ab", "<cmd>ClaudeCodeAdd %<CR>",      desc = "Add current buffer" },
      { "<leader>as", "<cmd>ClaudeCodeSend<CR>",       desc = "Send selection to Claude", mode = "x" },
      { "<leader>am", "<cmd>ClaudeCodeSelectModel<CR>", desc = "Select Claude model" },
    },

    opts = {
      auto_start = true,
      focus_after_send = false,
      track_selection = true,
      terminal = {
        -- Keep V0 deterministic and independent of optional terminal plugins.
        provider = "native",
        split_side = "right",
        split_width_percentage = 0.30,
        git_repo_cwd = true,
        auto_close = true,
      },
      diff_opts = {
        layout = "vertical",
        open_in_new_tab = false,
        keep_terminal_focus = false,
        on_new_file_reject = "close_window",
        auto_resize_terminal = true,
      },
    },

    config = function(_, opts)
      require("claudecode").setup(opts)
      require("config.claude_proposals").setup()
    end,
  },
}
