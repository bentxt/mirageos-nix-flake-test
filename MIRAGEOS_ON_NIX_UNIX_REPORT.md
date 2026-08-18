# Running MirageOS on a Unix Host with Nix

**Status:** feasibility and requirements report  
**Date:** 2026-08-18  
**Scope:** Linux, macOS, FreeBSD, and related Unix hosts; Nix supplies the
build environment; MirageOS may run either as a normal host process or as a
standalone Solo5 unikernel.

## Executive summary

MirageOS can run on a Unix machine in two materially different ways:

1. The `unix` target produces a normal POSIX executable. On macOS the
   corresponding target is `macosx`. This is the lowest-friction development
   route. It needs an OCaml/opam toolchain but no hypervisor. It is not isolated
   from the host like a standalone unikernel.
2. A Solo5 target produces a standalone unikernel plus a small host-side
   launcher called a *tender*. The usual target is `hvt`, which uses KVM on
   Linux, vmm on FreeBSD/OpenBSD, or nvmm on DragonFly. Linux also has the `spt`
   target, which runs as a process confined by seccomp and does not require
   hardware virtualization.

Nix can reproducibly supply the host compiler, opam, Make, `pkg-config`, and
Solo5 system libraries. There are then two dependency-management models:

- **Nix shell plus opam:** Nix fixes the host tools; a project-local opam switch
  resolves MirageOS and application packages. This matches MirageOS's documented
  workflow, but the opam dependency graph is not automatically part of the Nix
  lock file.
- **Nix-native opam resolution:** `opam-nix`, optionally through the specialized
  Hillingar flake, translates the opam dependency graph into Nix derivations.
  This can produce target-specific Nix packages, but adds another integration
  layer and requires compatibility testing against the selected Mirage and opam
  repository revisions.

This directory now includes a working implementation of the first model: a
Nix-provided development shell, a small Mirage application, and a script that
creates an isolated opam switch, builds the `macosx` target, and runs it. The
observed result is recorded in section 8.

## 1. What “running on Unix” means

MirageOS is a library operating system. Application code, selected OS libraries,
and a target runtime are linked together. The target determines the resulting
artifact and how it starts.

| Target | Result | Host requirement | Isolation |
|---|---|---|---|
| `unix` | Normal Unix executable | Modern Unix, OCaml, opam | None beyond ordinary host process controls |
| `macosx` | Normal macOS executable | macOS, OCaml, opam | None beyond ordinary host process controls |
| `hvt` | Solo5 unikernel image, usually `NAME.hvt` | Hardware virtualization and `solo5-hvt` | Hardware-virtualized guest |
| `spt` | Solo5 image, usually `NAME.spt` | Linux and `solo5-spt` | Strict seccomp sandbox; still a host process |
| `virtio` | Multiboot/virtio image | A suitable hypervisor, commonly QEMU/KVM | Full virtual-machine boundary |
| `xen` | Xen PVHv2 guest | Xen 4.10 or later on a supported 64-bit host | Xen guest |

The MirageOS installation guide explicitly distinguishes normal Unix binaries
from standalone unikernels and lists the supported host families for each
backend. The current example repository lists `unix`, `macosx`, `hvt`, `spt`,
`virtio`, `xen`, and additional specialized targets.

For ordinary development and functional tests, `unix` uses the host kernel and
can use host sockets and files. It therefore answers “can this Mirage
application run on this Unix machine?” but does not demonstrate the isolation
or deployment model of a standalone unikernel.

## 2. Required software

### Common build layer

The practical baseline is:

- Nix with flakes enabled, if the project is exposed as a flake;
- opam 2.1 or later;
- OCaml 4.13 or later;
- Mirage CLI 4.8 or later for the current `mirage-skeleton` examples;
- a C toolchain, Make, Git, and `pkg-config`;
- Dune, normally selected through the opam dependency solve;
- project-specific native libraries reported by opam/depext.

Two upstream pages give slightly different minimum OCaml versions: the
MirageOS installation page says 4.12.1, while the current Mirage repository
says 4.13. Using 4.13 as the lower bound satisfies both current statements.
The selected application's opam constraints may require a later compiler.

A Mirage application normally contains at least:

- `config.ml`, which declares devices, packages, and the registered job;
- application modules, commonly including `unikernel.ml`;
- a Dune project and opam metadata, some of which `mirage configure` generates.

### Additional Solo5 build dependencies

When Solo5 itself is built on Linux, its documented native inputs are a C11
compiler, GNU Make, full system headers, `pkg-config`, and `libseccomp` 2.3.3 or
later. A package delivered through opam or Nix may already encode these inputs,
but the Nix expression still has to make every required native dependency
available.

Nixpkgs contains a Solo5 package definition and uses Solo5 as an example of the
distinction between build tools and linked libraries: `pkg-config` is a native
build input, whereas `libseccomp` is a linked build input.

## 3. Host requirements by execution mode

### Unix process target

No hypervisor or kernel module is required. The resulting program executes like
another native process. Runtime details depend on the devices selected in
`config.ml`:

- A socket network stack uses the host TCP/IP stack and ordinary host sockets.
- A direct network stack uses the Mirage TCP/IP stack and generally needs a TAP
  device plus host routing configuration.
- Ports below 1024, raw networking, TAP creation, and some device access may
  require elevated privileges or capabilities even though the executable itself
  is a normal process.
- Writable files cannot live in `/nix/store`; runtime state must be supplied as
  an external writable path or block device. Read-only data may instead be
  embedded in the build, depending on the application's Mirage devices.

### Solo5 `hvt` target

The supported production combinations documented by Solo5 are Linux/KVM on
`x86_64` and `aarch64`, and FreeBSD/vmm on `x86_64`. OpenBSD/vmm and
DragonFly/nvmm are listed as experimental combinations.

On Linux, the tender needs access to:

- `/dev/kvm` for hardware virtualization;
- `/dev/net/tun` when a network device is attached;
- a TAP interface for each attached Ethernet service;
- any files used as block devices.

`solo5-hvt` does not need to run as root when the invoking account has the
required device permissions. Linux installations commonly mediate KVM access
through a `kvm` group. Creating and configuring TAP devices is a separate
privileged host operation. FreeBSD and OpenBSD have different privilege rules,
as described in the Solo5 guide.

The host CPU architecture must match the unikernel image. Hardware
virtualization also has to be enabled in firmware and exposed by any outer VM
when nested virtualization is involved.

### Solo5 `spt` target

`spt` is Linux-only. MirageOS documents `x86_64` and `aarch64`; Solo5's current
target table also lists `ppc64le`. It uses a strict seccomp allow-list instead of
hardware virtualization, and `solo5-spt` itself requires no special privileges.
Network attachment through a host TAP device still has the host-side setup
requirements described above.

### `virtio` and Xen targets

The Solo5 documentation treats `virtio` as a compatibility target with limited
device support. It can run under QEMU/KVM or another compatible hypervisor and
can be wrapped in a disk image where required. Xen needs a Xen-capable host and
is operationally more invasive than `unix`, `hvt`, or `spt`.

## 4. Build and run flow

### Unix development executable

For a Mirage application directory containing `config.ml`, the current example
workflow is:

```sh
opam install mirage
mirage configure -t unix --net socket
make depend
make
./NAME
```

`NAME` is the name registered by the application configuration. `--net socket`
is only valid when the application's configuration exposes that choice. Mirage
configuration options are application-dependent, so `mirage configure --help`
inside that application is authoritative.

The generated Makefile is a convenience layer. The underlying modern build is
performed by Dune, and `dune build` can be used where the generated project
supports it.

### Hardware-isolated `hvt` image

The no-network case is:

```sh
mirage configure -t hvt
make depend
make
solo5-elftool query-manifest ./NAME.hvt
solo5-hvt -- ./NAME.hvt
```

The manifest query reveals the logical names of all network and block devices.
Solo5 requires every declared device to be attached. A networked launch has the
following shape:

```sh
solo5-hvt \
  --mem=64 \
  --net:LOGICAL_NAME=tap100 \
  -- ./NAME.hvt APPLICATION_ARGUMENTS
```

On Linux, an isolated TAP example from the Solo5 guide is:

```sh
ip tuntap add tap100 mode tap
ip addr add 10.0.0.1/24 dev tap100
ip link set dev tap100 up
```

Those three host-network commands require suitable network-administration
privileges. Internet access from the guest additionally requires host IP
forwarding and routing or NAT. The Mirage application receives its own address,
gateway, and other boot arguments according to its `config.ml`.

`spt` follows the same manifest and device-attachment model, with `solo5-spt`
and an `.spt` artifact in place of `solo5-hvt` and `.hvt`.

## 5. Nix integration

### Model A: Nix development shell, opam dependency solve

A minimal flake shape for the host tools is:

```nix
{
  description = "MirageOS development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";

  outputs = { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      devShells = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.mkShell {
            packages = with pkgs; [
              git
              gnumake
              opam
              pkg-config
            ];

            buildInputs = pkgs.lib.optionals pkgs.stdenv.isLinux [
              pkgs.libseccomp
            ];
          };
        });
    };
}
```

Inside this shell, a project-local compiler switch can be created and activated:

```sh
opam init --bare --yes
opam switch create . ocaml-base-compiler.4.14.2 --yes
eval "$(opam env --switch=. --set-switch)"
opam install mirage --yes
```

This example deliberately lets opam build the compiler instead of mixing an
arbitrary Nixpkgs OCaml package into the switch. The exact compiler version is a
project constraint, not a MirageOS-wide requirement.

This model separates reproducibility into two parts:

- `flake.lock` pins Nixpkgs and the native tool environment;
- the opam repository state and resolved OCaml package versions need their own
  pinning or lock mechanism if bit-for-bit repeatability is required.

It also means that `make depend` mutates the local opam switch. Such mutation is
suitable in `nix develop`, but not inside a pure `nix build` derivation.

### Model B: Nix-native Mirage build

[`opam-nix`](https://github.com/tweag/opam-nix) converts opam projects and their
dependencies into Nix derivations on Linux and macOS. Its documentation names
[`Hillingar`](https://github.com/RyanGibb/hillingar) as the MirageOS-specific
layer. Hillingar exposes target packages such as `unix`, `hvt`, and `spt` using
`mkUnikernelPackages`.

The Hillingar template's conceptual interface is:

```nix
packages = hillingar.lib.${system}.mkUnikernelPackages {
  unikernelName = "NAME";
  depexts = with pkgs; [ /* native libraries required by this app */ ];
  query = {
    ocaml-base-compiler = "*";
  };
  monorepoQuery = {
    ocaml-base-compiler = "*";
  };
} self;
```

The resulting target is built with a target-specific attribute such as:

```sh
nix build .#unix
nix build .#hvt
```

This route moves the opam solve and build into the Nix graph. It also relies on
Hillingar, `opam-nix`, opam-repository, and Mirage opam-overlay revisions
remaining mutually compatible. Hillingar currently has no published releases,
so a production flake would pin a reviewed commit rather than depend on a moving
branch.

## 6. The Nix build/runtime boundary

Building and running are separate concerns:

- `nix build` can produce a Unix executable or a Solo5 image without granting
  the build sandbox KVM or TAP access.
- Starting an `hvt` artifact happens outside the Nix build sandbox because it
  needs runtime host devices.
- A Unix artifact dynamically linked to Nix store paths needs its Nix closure on
  the destination host.
- An `.hvt` artifact contains the guest runtime, but the destination still needs
  a compatible `solo5-hvt` tender and architecture.
- Writable block images, keys, logs, and mutable data are runtime state and do
  not belong in the read-only Nix store.
- Secret material should be injected at runtime; embedding it in a Nix build can
  expose it through the store and build metadata.

Nix can package a tender and unikernel together and expose a runnable wrapper,
but permissions for `/dev/kvm`, `/dev/net/tun`, TAP devices, routing, and block
files remain properties of the host.

## 7. Minimal verification matrix

A build is technically demonstrated when the applicable checks below pass:

| Check | `unix` | `hvt`/`spt` |
|---|---:|---:|
| Flake evaluates and host shell opens | Required | Required |
| Mirage configures for the target | Required | Required |
| Dune/Make produces the expected artifact | Required | Required |
| Program starts and reaches its main job | Required | Required |
| Manifest lists the expected devices | N/A | Required |
| Tender starts without undeclared/unattached devices | N/A | Required |
| Network service is reachable through the intended path | If networked | If networked |
| Mutable storage survives a restart | If stateful | If stateful |
| Artifact works after copying the required Nix closure/tender | Deployment check | Deployment check |

Useful diagnostic commands include:

```sh
mirage --version
opam --version
ocamlc -version
mirage describe
solo5-elftool query-manifest ./NAME.hvt
```

## 8. Current workspace implementation and observed result

The implementation tested on 2026-08-18 consists of:

- `flake.nix`, with a development shell containing opam, Git, Make,
  `pkg-config`, and Nixpkgs `libev`;
- `flake.lock`, pinning Nixpkgs revision
  `33da5f36e599b50aa7dbbfacb718254423b18354`;
- `mirageapp/config.ml` and `mirageapp/unikernel.ml`, defining a four-iteration hello
  application;
- `run.sh`, which locates Nix even when the default Nix profile is absent from
  `PATH` and enters the flake development shell;
- `scripts/run-mirage-demo.sh`, which creates an isolated opam root, installs an
  OCaml 4.14.2 switch and Mirage 4.9–4.11, selects `macosx` on Darwin or `unix`
  elsewhere, builds, and executes the result.

The Nix input had to move from `nixos-unstable` to
`nixpkgs-26.05-darwin`: Nixpkgs 26.11 dropped `x86_64-darwin`, while 26.05 is
the final branch supporting this Intel Mac.

The successful build selected Mirage 4.11.2 and produced:

```text
mirageapp/dist/hello: Mach-O 64-bit executable x86_64
size: 3.2 MiB
```

The binary executed both inside and outside `nix develop` and emitted four
messages:

```text
[INFO] [application] hello from MirageOS on Nix
```

Its non-system dynamic dependency resolves to the pinned Nix store rather than
Homebrew:

```text
/nix/store/xm1z22j3fvki873fbsr1qxf1s95v5cpg-libev-4.33/lib/libev.4.dylib
```

An isolated `hvt` probe successfully ran `mirage configure -t hvt`, but its
dependency solve failed because `ocaml-solo5` and `solo5` have no macOS opam
implementation. The current host also has no KVM execution backend. Therefore,
the normal macOS process target is verified here; producing and executing an
`hvt` guest remains a Linux/BSD-host validation item.

## Sources

- [MirageOS installation and target requirements](https://mirage.io/docs/install)
- [MirageOS CLI repository and current baseline requirements](https://github.com/mirage/mirage)
- [Current MirageOS skeleton workflow and target commands](https://github.com/mirage/mirage-skeleton)
- [Solo5 build, target, device, and launch documentation](https://github.com/Solo5/solo5/blob/main/docs/building.md)
- [Nixpkgs standard environment and Solo5 dependency example](https://nixos.org/manual/nixpkgs/stable/)
- [opam-nix project documentation](https://github.com/tweag/opam-nix)
- [Hillingar MirageOS-on-Nix integration](https://github.com/RyanGibb/hillingar)
