{
  den,
  pkgs,
  lib,
  ...
}:
let
  gitAliases = {
    g = "git";

    gst = "git status";
    gss = "git status -s";
    gsb = "git status -sb";

    ga = "git add";
    gaa = "git add --all";
    gau = "git add --update";
    gapa = "git add --patch";
    gap = "git apply";

    gb = "git branch -vv";
    gba = "git branch -a -v";
    gbd = "git branch -d";
    gbD = "git branch -D";
    gbl = "git blame -b -w";

    gc = "git commit -v";
    "gc!" = "git commit -v --amend";
    gca = "git commit -v -a";
    gcm = "git commit -m";
    gcam = "git commit -a -m";
    gcfx = "git commit --fixup";

    gcf = "git config --list";
    gcl = "git clone";

    gco = "git checkout";
    gcb = "git checkout -b";
    gsw = "git switch";
    gswc = "git switch --create";

    gd = "git diff";
    gdca = "git diff --cached";
    gds = "git diff --stat";
    gdsc = "git diff --stat --cached";
    gdt = "git diff-tree --no-commit-id --name-only -r";
    gdto = "git difftool";

    gf = "git fetch";
    gfa = "git fetch --all --prune";
    gfo = "git fetch origin";

    gl = "git pull";
    gll = "git pull origin";
    glr = "git pull --rebase";
    gup = "git pull --rebase";

    gp = "git push";
    "gp!" = "git push --force-with-lease";
    gpo = "git push origin";
    "gpo!" = "git push --force-with-lease origin";
    gpv = "git push --no-verify";

    glg = "git log --stat";
    glgg = "git log --graph";
    glgga = "git log --graph --decorate --all";
    glo = "git log --oneline --decorate --color";
    glog = "git log --oneline --decorate --color --graph";
    gloga = "git log --oneline --decorate --color --graph --all";

    gm = "git merge";
    gma = "git merge --abort";
    gmt = "git mergetool --no-prompt";

    grb = "git rebase";
    grba = "git rebase --abort";
    grbc = "git rebase --continue";
    grbi = "git rebase --interactive";
    grbs = "git rebase --skip";

    grh = "git reset";
    grhh = "git reset --hard";
    grhpa = "git reset --patch";

    grs = "git restore";
    grss = "git restore --source";
    grst = "git restore --staged";

    grm = "git rm";
    grmc = "git rm --cached";

    grev = "git revert";

    ggrep = "git grep";
    grl = "git rev-list";

    gr = "git remote -vv";
    grv = "git remote -v";
    gra = "git remote add";
    grmv = "git remote rename";
    grrm = "git remote remove";
    grpo = "git remote prune origin";
    grset = "git remote set-url";

    gsh = "git show";

    gsta = "git stash";
    gstp = "git stash pop";
    gstd = "git stash drop";
    gstl = "git stash list";
    gsts = "git stash show --text";
  };
in
{
  den.aspects.shell = {
    homeManager =
      {
        osConfig,
        pkgs,
        lib,
        ...
      }:
      {
        programs.btop.enable = true;

        programs.devenv.enable = true;

        programs.direnv = {
          enable = true;
          nix-direnv.enable = true;
          silent = true;
        };

        programs.bash = {
          enable = true;
          initExtra = ''
            if [ -z "$TMUX" ] && [ -n "$SSH_TTY" ]; then
              tmux new-session -A -s ssh
            fi

            set -o vi

            if command -v kitty >/dev/null 2>&1; then
              alias ssh="kitten ssh"
            fi
          '';
        };

        home.shellAliases = {
          vo = "cd ~/Documents/obsidian/ && $EDITOR .";

          vn = "cd ${osConfig.programs.nh.flake}; $EDITOR flake.nix";

          nrs = "nh os switch";
          nrb = "nh os boot";
          nrt = "nh os test";

          nrsu = "${lib.getExe pkgs.openssh} -t -i /home/repparw/.ssh/id_ed25519 -o BatchMode=yes -o IdentitiesOnly=yes root@${osConfig.modules.fleet-update.controllerHost} /run/current-system/sw/bin/fleet-update deploy --host alpha --force --wait-lock 10800 --state /var/lib/auto-update";
          nrbu = "nrb";

          ln = "ln -i";
          mv = "mv -i";

          rg = "rga";
          rt = "trash put";

          chown = "chown --preserve-root";
          chmod = "chmod --preserve-root";
          chgrp = "chgrp --preserve-root";
          top = "btop";
        }
        // gitAliases
        // (with pkgs; {
          diff = "${lib.getExe colordiff}";
          cat = "${lib.getExe bat}";
          df = "${lib.getExe duf} -hide-mp /home/containers/\\* -only local";
          du = "${lib.getExe dust} -x";

          rpi = "${lib.getExe' mosh "mosh"} -P 60001 pi";
          pc = "${lib.getExe' mosh "mosh"} -P 60000 alpha";
          eps = "${lib.getExe' mosh "mosh"} -P 60002 epsilon";

          ns = "${lib.getExe nix-search-tv} print | fzf --preview '${lib.getExe nix-search-tv} preview {}' --scheme history";
        });
      };
  };
}
