FROM rust:1.94.0-bookworm@sha256:365468470075493dc4583f47387001854321c5a8583ea9604b297e67f01c5a4f
RUN apt-get update && apt-get install -y --no-install-recommends clang libclang-dev libssl-dev pkg-config python3 && rm -rf /var/lib/apt/lists/*
RUN useradd --create-home --uid 1000 runner && mkdir -p /work /cargo /target && chown -R runner:runner /work /cargo /target
ENV CARGO_HOME=/cargo CARGO_TARGET_DIR=/target
USER runner
WORKDIR /work/Native/GreenBubbles
