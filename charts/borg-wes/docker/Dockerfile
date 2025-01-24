FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
      borgbackup \
      pipx \
      vim \
      ssh \
    && rm -rf /var/lib/apt/lists/*

RUN pipx install borgmatic

ENV PATH="/root/.local/bin:${PATH}"

ENTRYPOINT [ "borg" ]
