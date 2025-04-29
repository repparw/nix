_: {
  home.file.".config/tridactyl/tridactylrc".text = ''
      " General Settings
    set update.lastchecktime 1729971571332
    set update.nag true
    set update.nagwait 7
    set update.lastnaggedversion 1.14.0
    set update.checkintervalsecs 86400
    set configversion 2.0
    set newtab about:blank
    set modeindicatormodes.ignore false
    set modeindicatormodes.normal true
    set modeindicatormodes.insert true
    set modeindicatormodes.input true
    set modeindicatormodes.ex true
    set modeindicatormodes.hint true
    set modeindicatormodes.visual true
    set theme midnight
    set editorcmd ghostty nvim
    set smoothscroll true

    " Binds
    bind , hint -W mpvsafe
    bind gno tabopen https://bindingofisaacrebirth.fandom.com/wiki/Chaos_Card
    bind goo open https://bindingofisaacrebirth.fandom.com/wiki/Chaos_Card
    bind gwo winopen https://bindingofisaacrebirth.fandom.com/wiki/Chaos_Card
    bind gne tabopen https://web.whatsapp.com/
    bind goe open https://web.whatsapp.com/
    bind gwe winopen https://web.whatsapp.com/
    bind gnE tabopen https://dash.cloudflare.com/237bb2f57e9ad90ee4545948d7466790/repparw.com.ar/dns/records
    bind goE open https://dash.cloudflare.com/237bb2f57e9ad90ee4545948d7466790/repparw.com.ar/dns/records
    bind gwE winopen https://dash.cloudflare.com/237bb2f57e9ad90ee4545948d7466790/repparw.com.ar/dns/records
    bind ;x hint -F e => { const pos = tri.dom.getAbsoluteCentre(e); tri.excmds.exclaim_quiet("xdotool mousemove --sync " + window.devicePixelRatio * pos.x + " " + window.devicePixelRatio * pos.y + "; xdotool click 1")}
    bind ;X hint -F e => { const pos = tri.dom.getAbsoluteCentre(e); tri.excmds.exclaim_quiet("xdotool mousemove --sync " + window.devicePixelRatio * pos.x + " " + window.devicePixelRatio * pos.y + "; xdotool keydown ctrl+shift; xdotool click 1; xdotool keyup ctrl+shift")}
    unbind <F1>
    bind yy composite urlmodify_js -t www.youtube.com/watch?v= youtu.be/ | clipboard yank
    bind G scrollto 100
    bind gg scrollto 0
    bind J tabnext
    bind K tabprev

    bind e reader

    bindurl ^https://web.whatsapp.com e echo "e in wsp"

    " Subconfig Settings
    seturl youtube.com modeindicatormodes.normal false
    seturl www.google.com followpagepatterns.next Next
    seturl www.google.com followpagepatterns.prev Previous
    seturl https://jellyfin.repparw.com.ar/web/#/video modeindicatormodes.normal false

    " Autocmds
    autocmd DocStart 127.0.0.1:8096 mode ignore
    autocmd DocStart https://repparw.me mode ignore
    autocmd DocStart tradingview.com mode ignore
    autocmd DocStart inoreader.com mode ignore
    autocmd DocStart tldraw.com mode ignore
    autocmd DocStart config.qmk.fm mode ignore
    autocmd DocLoad ^https://github.com/tridactyl/tridactyl/issues/new$ issue
    autocmd TriStart .* source_quiet
    autocmd BeforeRequest undefined

    " For syntax highlighting see https://github.com/tridactyl/vim-tridactyl
    " vim: set filetype=tridactyl
  '';
}
