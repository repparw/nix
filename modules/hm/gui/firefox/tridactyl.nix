{ osConfig, ... }:
{
  # leaving as home.file instead of extensions.settings, to not overwrite temporary settings (quickmarks, marks, binds from cmdline)
  home.file.".config/tridactyl/tridactylrc".text = ''
    " General Settings
    set configversion 2.0
    set newtab about:blank
    set markjumpnoisy false
    set modeindicatormodes.ignore false
    set theme midnight
    set editorcmd foot nvim
    set smoothscroll true

    " Binds
    bind , hint -W mpvsafe
    bind ;c hint -c [class*="expand"],[class*="togg"],[class="comment_folder"]

    unbind <F1>
    unbind <C-e>

    bind gd tabdetach

    bind yy clipboard yankshort

    bind J tabnext
    bind K tabprev

    bind gr reader

    " Subconfig binds
    bindurl .*.youtube.com yy composite urlmodify_js -Q list | urlmodify_js -ru .*\.youtube\.com/watch\?v= https://youtu.be/ | clipboard yank
    bindurl www.youtube.com gm urlmodify -t www music

    bindurl ^moz-extension:\/\/1310b077-591a-4d70-aebf-a058924c50ec\/static\/reader\.html yy clipboard yankcanon

    unbindurl x.com e
    unbindurl x.com j
    unbindurl x.com k

    " Subconfig Settings
    seturl youtube.com modeindicator false
    seturl jellyfin.${osConfig.modules.services.domain} modeindicator false

    autocmd DocStart tradingview.com mode ignore
  '';
}
