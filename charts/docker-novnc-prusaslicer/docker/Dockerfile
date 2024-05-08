FROM theasp/novnc:latest

ENV PRUSASLICER_URL=https://github.com/prusa3d/PrusaSlicer/releases/download/version_2.7.4/PrusaSlicer-2.7.4+linux-x64-GTK3-202404050928.tar.bz2
# Install prusaslicer and dependencies
RUN apt-get update && \
    apt-get install -y \
        curl \
        libglu1-mesa \
        libgtk-3-0 \
        libegl1 \
        locales \
        procps \
        vim && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    curl -LO $PRUSASLICER_URL && \
    bunzip2 PrusaSlicer-*.tar.bz2 && \
    tar -xvf PrusaSlicer-*.tar && \
    rm -f PrusaSlicer-*.tar && \
    locale-gen && \
    dpkg-reconfigure locales

ENV SSL_CERT_FILE=/etc/ssl/certs/ \
    DISPLAY_WIDTH=1600 \
    DISPLAY_HEIGHT=900 \
    RUN_XTERM=no

COPY app /app
COPY os /

VOLUME [ "/root/.config" ]