FROM ubuntu:22.04

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
      libacl1-dev \
      libssl-dev \
      liblz4-dev \
      libzstd-dev \
      libxxhash-dev \
      build-essential \
      curl \
      pkg-config \
      pipx \
      python3-dev \
      python3-pkgconfig \
      vim \
      ssh \
    && rm -rf /var/lib/apt/lists/*

RUN pipx install borgbackup

RUN pipx install borgmatic

# Install kubectl for initContainer
RUN \
  curl -L -o /usr/local/bin/kubectl \
  "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
  && chmod +x /usr/local/bin/kubectl

ENV PATH="/root/.local/bin:/usr/local/bin/:${PATH}"

ENTRYPOINT [ "borg" ]
