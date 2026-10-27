# ACPYPE for Microsoft Discovery

Linux/AMD64 container based on the official
[ACPYPE Dockerfile](https://github.com/alanwilter/acpype/blob/2c17a4ed1c1ea4faf2ca553eeeea686071468cbc/Dockerfile).
It contains ACPYPE **2026.9.5**, Python 3.12, Open Babel, and the upstream
Linux AmberTools bundle, including the legacy CHARMM writer. It runs as UID
10001, with `/work` as the calculation directory. Commands are replaceable,
so Discovery can launch Bash scripts directly.

Source revision: `2c17a4ed1c1ea4faf2ca553eeeea686071468cbc`.
The Dockerfile checks the source archive's SHA-256; Python CLI dependencies
are pinned to upstream's lockfile and verified against wheel hashes.

## Build

From this directory in PowerShell, with Docker Desktop in Linux container mode:

```powershell
# Already downloaded in this workspace; run only when recreating the source checkout.
git clone https://github.com/alanwilter/acpype.git upstream

New-Item -ItemType Directory -Path .build -Force | Out-Null
git -c core.autocrlf=false -C upstream archive --format=tar.gz --output=../.build/acpype-source.tar.gz 2c17a4ed1c1ea4faf2ca553eeeea686071468cbc

docker build --platform linux/amd64 --progress=plain -t acpype-discovery:2026-10-07 -t acpype-discovery:latest .
```

The archive step preserves Linux executable permissions and library symlinks.
Disabling `core.autocrlf` prevents Git on Windows from rewriting the launcher's
Linux shebang. If `.build/acpype-source.tar.gz` already exists, just run the
Docker build command. The build intentionally excludes the macOS bundle.

## Run

```powershell
docker run --rm acpype-discovery:2026-10-07 acpype --version
docker run --rm acpype-discovery:2026-10-07 acpype --help

New-Item -ItemType Directory -Path input, output -Force | Out-Null
# Place ligand.mol2 in input, then run:
docker run --rm --init --network none --mount "type=bind,source=$($PWD.Path)/input,target=/app/inputs,readonly" --mount "type=bind,source=$($PWD.Path)/output,target=/work" acpype-discovery:2026-10-07 acpype -i /app/inputs/ligand.mol2 -b LIG -n 0 -c bcc -a gaff2
```

Set `-n` to the molecule's actual net charge. Outputs are created in
`output/LIG.acpype/`. ACPYPE also accepts PDB/MDL/MOL inputs and SMILES strings.
For existing AMBER files:

```powershell
docker run --rm --init --network none --mount "type=bind,source=$($PWD.Path)/input,target=/app/inputs,readonly" --mount "type=bind,source=$($PWD.Path)/output,target=/work" acpype-discovery:2026-10-07 acpype -p /app/inputs/system.prmtop -x /app/inputs/system.inpcrd -b SYSTEM
```

When mounting directories from a Linux host, ensure the output directory is
writable by UID 10001 or use `--user "$(id -u):$(id -g)"`. No GPU is required.
`OMP_NUM_THREADS` defaults to 1; choose thread counts within allocated CPUs.

## Verify

```powershell
New-Item -ItemType Directory -Path test-output -Force | Out-Null
docker run --rm --init --network none --mount "type=bind,source=$($PWD.Path)/tests,target=/tests,readonly" --mount "type=bind,source=$($PWD.Path)/test-output,target=/work" acpype-discovery:2026-10-07 /bin/bash /tests/discovery-smoke-test.sh
```

The smoke test checks the version, Open Babel bindings, all 14 bundled
executables, AM1-BCC/GAFF2 topology generation for ethanol, AMBER/GROMACS/CHARMM
output files, and conversion back from AMBER to GROMACS. Each run creates a
fresh `test-output/acpype-smoke.*` directory so cached calculations cannot
satisfy the test. It runs without network access. Build and test logs are
saved in `.build/`.

The full upstream suite also passed in this container runtime: **154 passed,
6 skipped, 93.16% coverage**. The six skipped integration cases require a
separate GROMACS installation. The measured archived application source was
compared with the installed application and matched before the test run.
See `.build/upstream-tests-source.log` for the full result.

## Publish to Azure Container Registry

Use the ACR associated with your Microsoft Discovery workspace. These commands
publish the already-built image; they do not create Azure resources:

```powershell
$registryName = ''
az login
az acr login --name $registryName
$registryLoginServer = az acr show --name $registryName --query loginServer -o tsv
if ($LASTEXITCODE -ne 0) { throw 'Could not determine the registry login server.' }
$publishedImage = "${registryLoginServer}/acpype-discovery:2026-10-07"
docker tag acpype-discovery:2026-10-07 $publishedImage
docker push $publishedImage
az acr repository show --name $registryName --image acpype-discovery:2026-10-07
```

Your account needs push permission. The Discovery workspace identity needs
permission to pull the image. See Microsoft's
[ACR publishing guide](https://learn.microsoft.com/en-us/azure/microsoft-discovery/how-to-publish-tool-to-acr).

## Microsoft Discovery definition

`acpype-tool.yaml` and the equivalent `acpype-tool.json` follow the supplied ASE
PSC definition with a **Python** code environment. Mount inputs at `/app/inputs`.
Set `outputMounts` to `["/work"]`. Generated Python scripts execute directly in
`/work`, which is writable by the image's non-root user. stdout and stderr are
captured in `/work/logs.out`, alongside ACPYPE's topology folders. The command
uses only the runner-supplied `scriptName` template. The launcher preserves the
script's exit status.
Use `subprocess.run([...], check=True)` when invoking ACPYPE from Python.

The public descriptors leave the ACR image reference blank. Add the private
image reference before registration. The resource settings preserve the current
JSON's D4s_v6 worker configuration; limits for particular molecules still need
workload benchmarking.
Register the JSON file through Discovery Studio or the Azure portal, following
Microsoft's [tool definition guide](https://learn.microsoft.com/en-us/azure/microsoft-discovery/how-to-create-tool-definition)
and [deployment guide](https://learn.microsoft.com/en-us/azure/microsoft-discovery/how-to-deploy-tool-to-discovery).
The included descriptor has been validated locally; Azure registration is a
separate step after the image is published.

`acpype-agent-instructions.txt` contains the updated agent prompt. Replace the
agent's earlier `/app/outputs` guidance with this prompt, save the corrected
tool definition as a new definition-content version, and retry with
`outputMounts: ["/work"]`. Saved retry scripts that change directory to
`/app/outputs` must be regenerated or changed to use `/work`.

Regression check for the reported empty-directory failure:

```powershell
python tests/test_discovery_launcher.py
```

This reproduces the code-environment call with only `scriptName` substituted.
It verifies a fresh ethane calculation, output logging, a script path containing
spaces, and propagation of a failing script's exit code, using the existing image.

## Image archive

The built image is also saved as `.build/acpype-discovery-2026-10-07.tar`.
To load it on another machine running Linux containers:

```powershell
docker load --input .build/acpype-discovery-2026-10-07.tar
```

To recreate the archive:

```powershell
docker save --output .build/acpype-discovery-2026-10-07.tar acpype-discovery:2026-10-07 acpype-discovery:latest
```

ACPYPE is GPL-3.0-or-later; the container retains its license and the bundled
AmberTools license files. Use generated topologies with compatible force fields.
