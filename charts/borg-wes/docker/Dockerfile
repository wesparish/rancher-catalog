FROM ubuntu:22.04

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
      libacl1-dev \
      libssl-dev \
      liblz4-dev \
      libzstd-dev \
      libxxhash-dev \
      build-essential \
      pkg-config \
      pipx \
      python3-dev \
      python3-pkgconfig \
      vim \
      ssh \
    && rm -rf /var/lib/apt/lists/*

RUN pipx install borgbackup

RUN pipx install borgmatic

ENV PATH="/root/.local/bin:${PATH}"

ENTRYPOINT [ "borg" ]
