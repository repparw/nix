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

## Upstream-oriented layout

### `flake.nix`

Responsibilities:

- bootstrap `flake-parts`
- import the local module tree with `import-tree`

It should not be the main place for host declarations or day-to-day aspect
configuration.

### `modules/dendritic.nix`

This is the upstream-style flake wiring file.

It imports the dendritic modules from:

- `flake-file`
- `den`

and keeps flake-file metadata close to the module tree instead of embedding
all flake wiring logic in `flake.nix`.

### `modules/hosts.nix`

This is the canonical place for Den inventory:

- `den.hosts.<system>.<host>.users.<user> = { };`
- `den.schema.user.classes = [ "homeManager" ];`

In this repo:

```nix
{ lib, ... }:
{
  den.schema.user.classes = lib.mkDefault [ "homeManager" ];

  den.hosts.x86_64-linux = {
    alpha.users.repparw = { };
    beta.users.repparw = { };
  };
}
```

If you add a new machine or a new user, start here.

### `modules/defaults.nix`

Use `den.default` for repo-wide defaults that should apply everywhere unless
overridden, and `den.ctx.user.includes` for upstream mutual host/user
routing.

In this repo, `modules/defaults.nix` also enables Den's upstream
mutual-provider through `den.ctx.user.includes`, matching the upstream
pattern.

`den.default` is therefore the place for:

- shared `stateVersion`
- repo-wide baseline defaults

Example:

```nix
{
  den.ctx.user.includes = [ den._."mutual-provider" ];
  den.default.nixos.system.stateVersion = "25.11";
  den.default.homeManager.home.stateVersion = "25.11";
}
```

This is upstream-preferred over repeating the same values in every host or
user aspect, or wiring host/user mutual routing ad hoc.

### `modules/vm.nix`

This is the template-style place for VM launchers.

In this repo it defines `perSystem.packages.vmAlpha` /
`perSystem.packages.vmBeta` and matching apps, using the built
`nixosConfigurations.<host>.config.system.build.vm` outputs.

This keeps VM execution out of `flake.nix` and out of the
`virtualisation` aspect.

### `modules/aspects/<host>.nix`

Host aspects configure host-specific behavior for Den-created host aspects.

Examples:

- `modules/aspects/alpha.nix`
- `modules/aspects/beta.nix`

These files should contain:

- `includes` for shared aspects/providers
- host-specific `nixos` configuration
- optionally host-specific `homeManager` configuration

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

- `users.users.repparw` in `nixos`
- `home.username` and `home.homeDirectory` in `homeManager`

It may also provide host-facing config through:

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

## Recommended workflow for common changes

### Add a new host

1. Declare it in `modules/hosts.nix`.
2. Create `modules/aspects/<host>.nix`.
3. Define `den.aspects.<host>`.
4. Add shared dependencies in `includes`.
5. Put machine-specific settings in that host aspect.

### Add a new user

1. Declare the user under the relevant host in `modules/hosts.nix`.
2. Create or extend `modules/aspects/<user>.nix`.
3. Define `den.aspects.<user>`.
4. Include `den.provides.define-user` and
   `den.provides.primary-user` if this is the main login user.

### Add a reusable system feature

1. Create `modules/aspects/<feature>.nix`.
2. Define `den.aspects.<feature>`.
3. Add `options.modules.<feature>.*` if it exposes toggles.
4. Enable it from host aspects through `includes` and host config.

### Add a reusable Home Manager feature

1. Create `modules/aspects/cli/<feature>.nix` or
   `modules/aspects/gui/<feature>.nix`.
2. Define `den.aspects.<feature>`.
3. Keep the behavior in `homeManager = { ... }: { ... };`
4. Include it from the user aspect if it is shared across machines.

## Guardrails

- Prefer one aspect per file.
- Keep aspect names aligned with the concern they represent.
- Keep host declarations centralized in `modules/hosts.nix`.
- Keep global defaults in `den.default`.
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
