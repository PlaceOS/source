FROM crystallang/crystal:0.35.1-alpine

WORKDIR /app

COPY shard.yml /app
COPY shard.lock /app
RUN shards install --production

# Add source last for efficient caching
COPY src /app/src

# Build App
RUN crystal build --error-trace --release --debug -o source src/app.cr

# Run the app binding on port 3000
EXPOSE 3000
HEALTHCHECK CMD ["/app/source", "-c", "http://127.0.0.1:3000/api/source/v1/"]
CMD ["/app/source", "-b", "0.0.0.0", "-p", "3000"]
