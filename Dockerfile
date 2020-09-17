FROM crystallang/crystal:0.35.1-alpine
WORKDIR /app

# Add trusted CAs for communicating with external services
RUN apk update && apk add --no-cache ca-certificates tzdata && update-ca-certificates

# Set the commit through a build arg
ARG PLACE_COMMIT="DEV"

COPY shard.yml /app
COPY shard.lock /app
RUN shards install --production

# Add source last for efficient caching
COPY src /app/src

# Build application
RUN UNAME_AT_COMPILE_TIME=true \
    PLACE_COMMIT=$PLACE_COMMIT \
    crystal build /app/src/app.cr -o /app/source

# Extract dependencies
RUN ldd /app/source | tr -s '[:blank:]' '\n' | grep '^/' | \
    xargs -I % sh -c 'mkdir -p $(dirname deps%); cp % deps%;'

# Create a non-privileged user, defaults are appuser:10001
ARG IMAGE_UID="10001"
ENV UID=$IMAGE_UID
ENV USER=appuser

# See https://stackoverflow.com/a/55757473/12429735RUN
RUN adduser \
    --disabled-password \
    --gecos "" \
    --home "/nonexistent" \
    --shell "/sbin/nologin" \
    --no-create-home \
    --uid "${UID}" \
    "${USER}"

# Build a minimal docker image
FROM scratch
WORKDIR /
ENV PATH=$PATH:/
COPY --from=0 /app/deps /
COPY --from=0 /app/source /source

# These are required for communicating with external services
COPY --from=0 /etc/hosts /etc/hosts

# These provide certificate chain validation where communicating with external services over TLS
COPY --from=0 /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

# This is required for Timezone support
COPY --from=0 /usr/share/zoneinfo/ /usr/share/zoneinfo/

# Copy the user information over
COPY --from=0 /etc/passwd /etc/passwd
COPY --from=0 /etc/group /etc/group

# Use an unprivileged user.
USER appuser:appuser

# Run the app binding on port 3000
EXPOSE 3000
HEALTHCHECK CMD ["/source", "-c", "http://127.0.0.1:3000/api/source/v1/"]
CMD ["/source", "-b", "0.0.0.0", "-p", "3000"]
