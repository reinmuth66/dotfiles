return {
  {
    "zbirenbaum/copilot.lua",
    cmd = "Copilot",
    build = ":Copilot auth",
    event = "InsertEnter",
    opts = {
      suggestion = {
        enabled = true,
        auto_trigger = true,
        keymap = {
          accept = "<Tab>",
          dismiss = "<C-]>",
          next = "<M-]>",
          prev = "<M-[>",
        },
      },
      panel = { enabled = false },
    },
  },
}
