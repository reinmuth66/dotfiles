require("git"):setup({
	-- Order of status signs showing in the linemode
	order = 1500,
})

require("eza-preview"):setup({
	-- Set the tree preview to be default (default: true)
	default_tree = true,

	-- Directory depth level for tree preview (default: 3)
	level = 3,

	-- Show file icons
	icons = true,

	-- Follow symlinks when previewing directories (default: true)
	follow_symlinks = true,

	-- Show target file info instead of symlink info (default: false)
	dereference = false,

	-- Show hidden files (default: true)
	all = true,

	-- Ignore files matching patterns (default: {})
	-- ignore_glob = "*.log"
	-- ignore_glob = { "*.tmp", "node_modules", ".git", ".DS_Store" }
	-- SEE: https://www.linuxjournal.com/content/pattern-matching-bash to learn about glob patterns
	ignore_glob = {},

	-- Ignore files mentioned in '.gitignore'  (default: true)
	git_ignore = true,

	-- Show git status (default: false)
	git_status = false,
})
