FROM ubuntu:24.04

RUN apt-get update && \
    apt-get install ca-certificates curl bind9-utils dnsutils procps -y && \
    curl -LO https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb && \
    apt-get install ./cloudflared-linux-amd64.deb && \
    cloudflared -v

EXPOSE 5053

ENTRYPOINT [ "cloudflared" ]
CMD [ "proxy-dns", \
      "--address", "0.0.0.0", \
      "--port", "5053", \
      "--metrics", "0.0.0.0:39055", \
      "--upstream", "https://1.1.1.1/dns-query", \
      "--upstream","https://1.0.0.1/dns-query" ]