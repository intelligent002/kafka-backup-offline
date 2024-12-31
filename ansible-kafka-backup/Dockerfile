FROM alpine/ansible:latest
# add archivators
RUN apk update && apk add --no-cache tar xz unzip gzip zstd && rm -rf /var/cache/apk/* /tmp/*