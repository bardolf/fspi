return {
  "saghen/blink.cmp",

  -- Use the opts function to ensure your settings override the LazyVim defaults
  opts = function(_, opts)
    -- This sets the global options for blink.cmp
    opts = vim.tbl_deep_extend("force", opts, {

      -- *** 1. STOP AUTO-POPUP COMPLETELY ***
      completion = {
        show_on_keyword = false,
        show_on_trigger_character = false,
      },

      -- *** 2. CONFIGURE KEYMAPS ***
      keymap = {
        preset = "default",

        -- Use <Tab> to accept the selected suggestion when the menu is visible.
        -- We explicitly map it here to ensure it overrides any other default.
        ["<Tab>"] = { "accept" },

        -- Hitting Enter (<CR>) must *not* accept, it should just create a new line.
        ["<CR>"] = { "fallback" },

        -- Explicitly show the menu only when <C-Space> is pressed
        ["<C-Space>"] = { "show" },

        -- Optional: Use <S-Tab> to select the previous item
        ["<S-Tab>"] = { "select_prev" },

        -- Select the next item in the menu
        ["<Down>"] = { "select_next" },
        ["<C-n>"] = { "select_next" },

        -- Select the previous item in the menu
        ["<Up>"] = { "select_prev" },
        ["<C-p>"] = { "select_prev" },
      },
    })

    return opts
  end,
}
