FROM golang:1.24.5-bookworm

WORKDIR /workspace

ENV ARKSCALE_OHOS_NATIVE=/opt/ohos-sdk/linux/native
ENV ARKSCALE_GO_BOOTSTRAP=/usr/local/go

CMD ["./scripts/p0-container.sh"]
