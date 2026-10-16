# CIDR Atlas security policy

Author: Sergio Farfan <sergio.farfan@gmail.com>

## How CIDR Atlas handles data

CIDR Atlas is local-first. The macOS app and the `cidrctl` CLI keep the address
inventory and its history in one SQLite database on your Mac
(`~/Library/Application Support/cidr_atlas/inventory.sqlite` unless you choose
another path with `--db`). There is no CIDR Atlas service, account or telemetry,
and nothing is uploaded. Imports and exports read and write only the files you
select.

OCI access is optional and happens only when you start discovery, in the app or
with `cidrctl discover oci`:

- Discovery runs your existing OCI CLI installation with the profile, region and
  compartment scope you choose. CIDR Atlas does not hold OCI credentials of its
  own, and it does not install or configure the OCI CLI.
- Requests are read-only list and get calls. CIDR Atlas never creates, changes or
  deletes OCI resources.
- The OCI CLI is started directly with an argument list (no shell), an empty rc
  file and a reduced environment. From the OCI configuration file CIDR Atlas
  keeps only allowlisted profile metadata (profile names, tenancy, region and
  whether a session token is configured). It never opens API key, security token
  or other key files; the OCI CLI uses them on its own.
- Results stay in memory as a preview. Nothing is written to the local inventory
  until you apply the preview.

## Supported versions

Security fixes are made for the latest release only. Upgrade to the latest
release before reporting, where possible.

## Reporting a vulnerability

The repository is private, so GitHub private vulnerability reporting is not
available. Email sergio.farfan@gmail.com directly with **CIDR Atlas security**
in the subject. Include the version (`cidrctl --version` or the app header), the
macOS version, and the steps to reproduce with fictional data.

Do not post vulnerability details in issues, pull requests or discussions, and do
not include real tenancy data, OCIDs, OCI CLI configuration, keys, tokens or
customer metadata in any report. Reports are read by the maintainer and
acknowledged as quickly as possible.
