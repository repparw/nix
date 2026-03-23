# AGENTS.md

This repository follows the upstream `vic/den` default-template structure
and usage model.

The key idea is:

- declare hosts and users centrally in `modules/hosts.nix`
- let Den create the parametric host/user aspects from those declarations
- keep cross-cutting configuration in `den.aspects.*`
- keep repo-wide defaults in `modules/defaults.nix` via `den.default`
- route host/user mutual providers through `den.ctx.user.includes`
- use `includes` to compose aspects

Common patterns in this repo after the dendritic refactor:

- repo-wide base behavior comes from `den.default.includes`
- concern-specific flake inputs live next to the aspect or module that uses them
- host aspects stay focused on machine-specific hardware, filesystems, and flags
- user aspects stay focused on shared user composition and user-owned crossovers

## Upstream-oriented layout

### `flake.nix`

Responsibilities:

- bootstrap `flake-parts`
- import the local module tree with `import-tree`

It should not be the main place for host declarations or day-to-day aspect
configuration.

### `modules/dendritic.nix`

This is the upstream-style core flake wiring file.

It imports the dendritic modules from:

- `flake-file`
- `den`

and keeps the base dendritic wiring out of `flake.nix`.

Use this file for repo-global flake wiring, such as:

- importing upstream dendritic flake modules
- declaring base inputs like `nixpkgs`, `den`, `flake-file`, `import-tree`

Do not treat `modules/dendritic.nix` as the required home for every
`flake-file.inputs.*` declaration.

In this repo, concern-specific flake inputs should be declared next to the
module or aspect that owns them. For example:

- `repparw.nix` owns the `home-manager` input it imports
- `nix-index.nix` owns the `nix-index-database` input it imports
- `nixvim.nix` owns the `nixvim-config` input it overlays

### `modules/defaults.nix`

Use `den.default` for repo-wide defaults that should apply everywhere unless
overridden.

In this repo, `modules/defaults.nix` also carries repo-wide shared includes
through `den.default.includes`, in addition to shared state versions.

Today that includes the baseline aspects that should apply on every host:

- `nix-index`
- `nixvim`
- `nixpkgs`
- `nix`
- `system`

This is upstream-preferred over repeating the same values in every host or
user aspect, or wiring host/user mutual routing ad hoc.

### `modules/vm.nix`

This is the template-style place for VM launchers.

In this repo it defines `perSystem.packages.vmAlpha` /
`perSystem.packages.vmBeta` and matching apps, using the built
`nixosConfigurations.<host>.config.system.build.vm` outputs.

This keeps VM execution out of `flake.nix` and out of the
`virtualisation` aspect.

### `modules/hosts/<host>.nix`

Host aspects configure host-specific behavior for Den-created host aspects.

Examples:

- `modules/hosts/alpha.nix`
- `modules/hosts/beta.nix`

These files should contain:

- `includes` for shared aspects/providers
- host-specific `nixos` configuration
- optionally host-specific `homeManager` configuration

In this repo, host aspects usually include a small shared host stack such as:

- `den.provides.hostname`
- `den.aspects.cli`
- `den.aspects.networking`
- `den.aspects.overlays`
- `den.aspects.secrets`
- `den.aspects.style`

These files are the right place for:

- boot and initrd
- filesystems and swap
- hardware quirks
- host-local services
- feature flags such as `modules.gaming.enable = true;`
- host-to-user mutual providers like `provides.repparw = { ... };`

### `modules/aspects/<user>.nix`

User aspects configure Den-created user aspects.

In this repo, `modules/aspects/repparw.nix` is the shared user composition
layer. It includes:

- `den.provides.define-user`
- `den.provides.primary-user`
- reusable CLI/GUI aspects

It also owns:

- shared user composition and user-local settings
- the `home-manager` NixOS module import and bridge settings

Identity fields such as:

- `users.users.repparw`
- `home.username`
- `home.homeDirectory`

are provided in this repo through `den.provides.define-user`, which is
included from the user aspect.

It may also provide host-facing config through:

- `provides.to-hosts`
Or:
    - `provides.alpha`
    - `provides.beta`

### `modules/aspects/cli/*.nix` and `modules/aspects/gui/*.nix`

Keep reusable user-facing features here.

Examples:

- `shell`, `tmux`, `git`, `ssh`
- `browser`, `mpv`, `spotify`, `obs`

These should generally be small composable aspects that are included from the
user aspect, not from `flake.nix`.

## Proper Den usage in this repo

### 1. Declare inventory first

When adding a host or user:

1. edit `modules/hosts.nix`
2. declare the host/user under `den.hosts`
3. let Den synthesize the corresponding host/user aspects

Do not scatter `den.hosts.*` declarations across unrelated aspect files.

### 2. Configure the generated host/user aspects

Once a host or user is declared, configure it through:

- `den.aspects.<host>`
- `den.aspects.<user>`

That means:

- `den.aspects.alpha` configures the `alpha` host
- `den.aspects.beta` configures the `beta` host
- `den.aspects.repparw` configures the `repparw` user

### 3. Put shared defaults in `den.default`

Use `den.default` for:

- shared `stateVersion`
- repo-wide baseline options
- repo-wide shared `includes`
- truly global defaults that should apply across contexts

Do not repeat identical values in every host/user aspect when a default is
semantically correct.

### 4. Use mutual providers for host/user crossovers

Follow the upstream pattern for cross-context config:

- `${user}.provides.${host}` for config that conceptually belongs to the
  user but must land on the host NixOS side
- `${host}.provides.${user}` for config that conceptually belongs to the
  host but must land on the user's Home Manager side

In this repo:

- `repparw.provides.alpha` and `repparw.provides.beta` provide `gui`
  to the host side
- `beta.provides.repparw` provides laptop-specific Home Manager additions
  such as `kanshi` and `brightnessctl`

### 5. Use `includes` for aspect composition

Use:

- `den.aspects.foo`
- `den.provides.primary-user`
- `den.aspects.bar.provides.baz`

inside `includes`.

Do not wire local aspects together with raw file imports.

### 6. Use `imports` only for real module imports

Use `imports` inside `nixos` or `homeManager` modules for things like:

- `inputs.home-manager.nixosModules.home-manager`
- `inputs.stylix.nixosModules.stylix`
- `(modulesPath + "/installer/scan/not-detected.nix")`

That is module-system composition, not Den aspect composition.

### 7. Co-locate flake inputs with their owning concern

Declare `flake-file.inputs.*` in the module or aspect that actually uses the
input when that dependency is concern-specific.

Examples in this repo:

- `style.nix` declares `flake-file.inputs.stylix`
- `secrets.nix` declares `flake-file.inputs.sops-nix`

Prefer this over centralizing every input in `modules/dendritic.nix`.
Keep `modules/dendritic.nix` for base repo wiring and universally shared
inputs.

### 8. Prefer named composition aspects for shared stacks

If several aspects naturally form one reusable stack, expose a named
composition aspect instead of repeating the full list everywhere.

In this repo:

- `den.aspects.cli` is the composed system CLI baseline
- `den.aspects.gui` is the composed GUI/session stack

Prefer these names over legacy placeholders such as `cli-core` or `gui-core`.

## Recommended workflow for common changes

### Add a reusable system feature

1. Create `modules/aspects/<feature>.nix`.
2. Define `den.aspects.<feature>`.
3. Enable it from host aspects through `includes` and host config.

## Guardrails

- Prefer one aspect per file.
- Keep aspect names aligned with the concern they represent.
- Keep host declarations centralized in `modules/hosts.nix`.
- Keep global defaults in `den.default`.
- Keep concern-local flake inputs next to the concern that uses them.
- Keep host specifics in host aspects.
- Keep user specifics in user aspects.
- Keep reusable features in dedicated feature aspects.
- Use `lib.mkIf` and `lib.mkMerge` for conditional config.
- Do not put plaintext secrets in the repo; use `sops-nix`.

## Validation

Useful checks after structural Den changes:

```bash
nix fmt
nix eval .#nixosConfigurations.alpha.config.system.build.toplevel.outPath
nix eval .#nixosConfigurations.beta.config.system.build.toplevel.outPath
```
