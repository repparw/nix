local options = {
  splitright = true,
  splitbelow = true,
  termguicolors = true,
  ignorecase = true,
  smartcase = true,
  tabstop = 4,
  shiftwidth = 2,
  number = true,
  relativenumber = true,
  list = true,
  listchars = { eol = '↲',
				tab = '» ',
				trail = '·',
				extends = '<',
				precedes = '>',
				conceal = '┊',
				nbsp = '␣',
        },
  scrolloff = 10,
  inccommand = 'split',
  background = 'dark',
  showmode = false,
  mouse = 'a',
  updatetime = 250,
  timeoutlen = 300,
  cursorline = true,
}

for k,v in pairs(options) do
  vim.opt[k] = v
end
