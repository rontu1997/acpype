#!/usr/bin/env bash
set -euo pipefail

cd /work
test -w /work
# ACPYPE reuses cached calculations. Give each run fresh inputs and outputs.
smoke_work=$(mktemp -d /work/acpype-smoke.XXXXXX)
cd "$smoke_work"
test "$(id -u)" != 0
acpype --version | grep -F 'v. 2026.9.5'
python3 -c 'from openbabel import openbabel; print("Open Babel:", openbabel.OBReleaseVersion())'
python3 /opt/acpype/check_amber_bundle.py "$AMBERHOME"

# This input exercises Open Babel, antechamber, AM1-BCC/sqm, parmchk2, tleap,
# and ACPYPE's topology writers with no downloads at runtime.
acpype -i CCO -b ETH -n 0 -c bcc -a gaff2
test -s ETH.acpype/ETH_AC.prmtop
test -s ETH.acpype/ETH_AC.inpcrd
test -s ETH.acpype/ETH_GMX.itp
test -s ETH.acpype/ETH_GMX.top
test -s ETH.acpype/ETH_GMX.gro
test -s ETH.acpype/ETH_CHARMM.rtf
test -s ETH.acpype/ETH_CHARMM.prm

# Exercise the second supported workflow against the topology just generated.
acpype -p "$smoke_work/ETH.acpype/ETH_AC.prmtop" -x "$smoke_work/ETH.acpype/ETH_AC.inpcrd" -b CONVERTED
test -s CONVERTED.amb2gmx/CONVERTED_GMX.top
test -s CONVERTED.amb2gmx/CONVERTED_GMX.gro

printf 'ACPYPE Discovery smoke test passed; results: %s\n' "$smoke_work"
