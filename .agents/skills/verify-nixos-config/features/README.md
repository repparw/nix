# Feature map — verify-nixos-config

User-facing "features" of this flake, from the user's point of view: what they
get from it, and what observable state proves each works. Drive one feature
per verification run; the map exists so later runs cover the rest.

| Feature | Proves | Cost |
|---|---|---|
| [flake-eval](flake-eval.md) | the checkout evaluates and module options hold the intended values | seconds |
| [home-manager-files](home-manager-files.md) | generated dotfiles (opencode.json etc.) contain what the modules say | ~1 min |
| [system-build](system-build.md) | the full system closure builds — switch will not fail midway | minutes |
| [closure-diff](closure-diff.md) | exactly what a switch would change on this machine | minutes |

Precedence: eval < generated-files < build. A change is proven when the
cheapest feature that observes it directly passes, and the map's stronger
features are noted if they were skipped.
