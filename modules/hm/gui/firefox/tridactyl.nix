_: {
  # leaving as home.file instead of extensions.settings, to not overwrite temporary settings (quickmarks, marks, binds from cmdline)
  home.file.".config/tridactyl/tridactylrc".text = ''
    " General Settings
    set configversion 2.0
    set newtab about:blank
    set markjumpnoisy false
    set modeindicatormodes.ignore false
    set modeindicatormodes.normal true
    set modeindicatormodes.insert true
    set modeindicatormodes.input true
    set modeindicatormodes.ex true
    set modeindicatormodes.hint true
    set modeindicatormodes.visual true
    set theme midnight
    set editorcmd kitty nvim
    set smoothscroll true

    " Binds
    bind gc tab pocketcasts.com/podcasts

    bind , hint -W mpvsafe
    bind ;c hint -c [class*="expand"],[class*="togg"],[class="comment_folder"]

    unbind <F1>
    unbind <C-e>

    bindurl .*.youtube.com yy composite urlmodify_js -Q list | urlmodify_js -ru .*\.youtube\.com/watch\?v= https://youtu.be/ | clipboard yank

    bindurl ^moz-extension:\/\/.*\/static\/reader\.html yy clipboard yankcanon

    bind G scrollto 100
    bind gg scrollto 0
    bind J tabnext
    bind K tabprev

    bind e reader

    bindurl ^https://web.whatsapp.com e echo "e in wsp"
    unbindurl ^https://web.whatsapp.com <A-k>

    unbindurl ^https://x.com j
    unbindurl ^https://x.com k

    " Subconfig Settings
    seturl youtube.com modeindicatormodes.normal false
    seturl https://jellyfin.repparw.me/ modeindicatormodes.normal false

    " Autocmds
    autocmd DocStart tradingview.com mode ignore
    autocmd DocStart tldraw.com mode ignore
    autocmd DocStart config.qmk.fm mode ignore
    autocmd TriStart .* source_quiet
    autocmd BeforeRequest undefined
  '';
}
