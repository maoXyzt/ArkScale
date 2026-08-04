FROM golang:1.24.5-bookworm@sha256:9aba206b3974f93f7056304c991c9cc1f843c939159d9305571ab9766c9ccdf6

WORKDIR /workspace

ENV ARKSCALE_OHOS_NATIVE=/opt/ohos-sdk/linux/native
ENV ARKSCALE_GO_BOOTSTRAP=/usr/local/go

CMD ["./scripts/p0-container.sh"]
