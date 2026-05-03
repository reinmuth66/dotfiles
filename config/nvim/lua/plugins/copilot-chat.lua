return {
  {
    "CopilotC-Nvim/CopilotChat.nvim",
    dependencies = {
      "zbirenbaum/copilot.lua",
      { "nvim-lua/plenary.nvim", branch = "master" },
    },
    build = "make tiktoken",
    opts = {
      model = "gpt-4o",
      language = "Japanese",
    },
    keys = {
      { "<leader>cc", "<cmd>CopilotChat<cr>", desc = "CopilotChat を開く" },
      { "<leader>ce", "<cmd>CopilotChatExplain<cr>", mode = { "n", "v" }, desc = "コードを説明" },
      { "<leader>cf", "<cmd>CopilotChatFix<cr>", mode = { "n", "v" }, desc = "コードを修正" },
      { "<leader>cr", "<cmd>CopilotChatReview<cr>", mode = { "n", "v" }, desc = "コードをレビュー" },
      { "<leader>ct", "<cmd>CopilotChatTests<cr>", mode = { "n", "v" }, desc = "テストを生成" },
    },
  },
}
