# nix-wire

> [!WARNING]
> - This is currently in a pre-baked state.
> - I have tested this for my darwin machine, but haven't yet tested on a linux machine. (TO be done in upcoming days)
> - I am using it here: [ndots@nwire](https://github.com/niksingh710/ndots/tree/nwire)
> - Also you can check the example dir for structure.

> [!NOTE]
> For testers, Currenlty testing implementation is not that clean.
> But cd in the `example` dir and `nix repl` to investigate the changes.


**nix-wire** is a lightweight utility for structuring and wiring Nix flakes.
It automatically discovers and assembles configurations for:

* **NixOS hosts** (`hosts/nixos/…`)
* **Darwin hosts** (`hosts/darwin/…`)
* **Home Manager users** (`hosts/home/…`)
* **Packages** (`packages/…`)
* **DevShells** (`devshells/…`)

Instead of manually importing every `.nix` file, nix-wire walks your project directories and generates the right attributes for your `flake.nix`.

---

## Example directory structure

```text
.
├── hosts
│   ├── home
│   │   └── alice.nix
│   ├── nixos
│   │   ├── workstation
│   │   │   ├── users
│   │   │   │   └── bob.nix
│   │   │   └── default.nix
│   │   └── laptop.nix
│   └── darwin
│       ├── macbook
│       │   ├── users
│       │   │   ├── carol
│       │   │   │   └── default.nix
│       │   │   └── dave.nix
│       │   └── default.nix
│       └── office-mac.nix
├── devshells
│   └── default.nix
├── packages
│   ├── foo
│   │   └── default.nix
│   └── bar.nix
├── flake.lock
└── flake.nix
```

### Notes

* `hosts/nixos/<hostname>/default.nix` → NixOS configuration for that host
* `hosts/darwin/<hostname>/default.nix` → Darwin configuration for that host
* `hosts/home/<username>.nix` → Home Manager configuration for a standalone user
* `hosts/nixos/<hostname>/users/<username>.nix` → attach users to a specific host
* `packages/<name>.nix` or `packages/<name>/default.nix` → reusable packages
* `devshells/default.nix` → development shells

👉 All these directories (`hosts`, `packages`, `devshells`) are **optional**.
Your `mkFlake` setup decides which ones to opt into.

---

## Acknowledgements

We're aware of similar projects like [blueprint](https://github.com/numtide/blueprint) and many others in the Nix ecosystem. **nix-wire** intentionally keeps things bare minimum to focus solely on wiring flake configurations without additional complexity.

This project is currently in a pre-baked state. Proper acknowledgements, documentation, and feature comparisons will be added as the project matures.

---

## TODOs

* [ ] Better template / test structure
* [ ] Add CI with checks (formatting, evaluation, etc.)
* [ ] Integrate `nix flake check` *(recommended, ensures configs evaluate properly; may require minimal test modules)*
* [ ] GitBook docs
