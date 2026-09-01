# Appliance asset provenance

The appliance seed was copied from `ec2trib` on 2026-09-01.

## QEMU

- source checkout: `/tink/builds/qemu-sun4v-879fee-tribblix`
- exact commit: `049affb20df67162cf58deeaf74d5ad4b83cbdc3`
- source archive SHA-256:
  `4990dafc5ca24bb73837d5d5652aa8bf16bd6df5e9db54b873cfcc59d0fa9c95`
- the container build compiled `hw/sparc64/niagara.c` and rejected binaries
  that did not advertise the `niagara` machine

## Root disk

- source dataset: `tink/qemu-sun4v-illumos-ci/woodpecker-9`
- held source snapshot:
  `release-cleanup-pre-reboot-20260830T100458Z`
- source snapshot GUID: `964087624899128213`
- hold: `release-candidate-pre-reboot`
- source file:
  `baselines/unit104-login-proven-20260826T210446Z.raw`
- destination file: `assets/root-unit104.raw`
- logical size: 64,424,509,440 bytes
- destination SHA-256:
  `3e776dd672e03a0c253c92db755bb357bf012eb9077b230006b6787baa646e44`

The root was transferred through a GNU sparse archive over authenticated SSH.
The functional acceptance gate is an x86-64 container boot to
`oi-basecamp console login:` using the proven OpenBoot command.
