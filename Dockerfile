FROM crystallang/crystal:0.35.1-alpine

WORKDIR /app

COPY shard.yml /app
COPY shard.lock /app
RUN shards install --production

# Add source last for efficient caching
COPY src /app/src

# Build App
RUN crystal build --error-trace --release --debug -o bin/mqtt src/app.cr

# Run the app binding on port 3000
EXPOSE 3000
HEALTHCHECK CMD ["/app/bin/mqtt", "-c", "http://127.0.0.1:3000/api/mqtt/v1/"]
CMD ["/app/bin/mqtt", "-b", "0.0.0.0", "-p", "3000"]
