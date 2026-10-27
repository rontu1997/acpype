# syntax=docker/dockerfile:1
# Source archive: git -c core.autocrlf=false -C upstream archive --format=tar.gz --output=../.build/acpype-source.tar.gz 2c17a4ed1c1ea4faf2ca553eeeea686071468cbc
FROM ubuntu:24.04 AS source

COPY .build/acpype-source.tar.gz /tmp/acpype-source.tar.gz
RUN echo 'e5f038178a72eea644d5ff28f493340fd1dd6a7834200440706d12f516cace5c  /tmp/acpype-source.tar.gz' | sha256sum --check - \
    && mkdir /src \
    && tar -xzf /tmp/acpype-source.tar.gz -C /src \
    && rm -rf /src/src/acpype/amber_macos

FROM ubuntu:24.04 AS runtime

ARG TARGETARCH
ARG DEBIAN_FRONTEND=noninteractive
LABEL org.opencontainers.image.title="ACPYPE for Microsoft Discovery" \
      org.opencontainers.image.version="2026.9.5" \
      org.opencontainers.image.source="https://github.com/alanwilter/acpype" \
      org.opencontainers.image.revision="2c17a4ed1c1ea4faf2ca553eeeea686071468cbc" \
      org.opencontainers.image.licenses="GPL-3.0-or-later" \
      org.opencontainers.image.description="ACPYPE with bundled Linux AmberTools and Open Babel; CPU execution for Microsoft Discovery"

# The vendored AmberTools executables support Linux x86_64.
RUN test "${TARGETARCH}" = amd64 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates python3 python3-venv openbabel python3-openbabel \
        libgfortran5 libstdc++6 libgomp1 libblas3 liblapack3 libcurl4 \
    && rm -rf /var/lib/apt/lists/*

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    VIRTUAL_ENV=/opt/venv \
    PYTHONPATH=/opt/acpype \
    AMBERHOME=/opt/acpype/acpype/amber_linux \
    LD_LIBRARY_PATH=/opt/acpype/acpype/amber_linux/lib \
    OMP_NUM_THREADS=1
ENV PATH="/opt/venv/bin:/opt/acpype/acpype/amber_linux/bin:${PATH}"

# Keep Ubuntu's Open Babel Python bindings visible inside the virtual environment.
COPY requirements-cli.txt /tmp/requirements-cli.txt
RUN python3 -m venv --system-site-packages "${VIRTUAL_ENV}" \
    && pip install --no-cache-dir --require-hashes --only-binary=:all: -r /tmp/requirements-cli.txt \
    && rm /tmp/requirements-cli.txt

COPY --from=source /src/src/acpype /opt/acpype/acpype
COPY --from=source /src/run_acpype.py /opt/acpype/run_acpype.py
COPY --from=source /src/LICENSE /opt/acpype/LICENSE
COPY --from=source /src/scripts/check_amber_bundle.py /opt/acpype/check_amber_bundle.py

RUN chmod -R a+rX /opt/acpype \
    && chmod 755 /opt/acpype/run_acpype.py \
    && ln -s /opt/acpype/run_acpype.py /usr/local/bin/acpype \
    && useradd --create-home --uid 10001 --shell /bin/bash acpype \
    && mkdir -p /work /app/inputs \
    && chown acpype:acpype /work \
    && python3 -c "import acpype; from openbabel import openbabel; assert acpype.__version__ == '2026.9.5'; print(openbabel.OBReleaseVersion())"

USER acpype
WORKDIR /work

# Discovery supplies complete commands, so keep the image's command replaceable.
CMD ["acpype", "--help"]
