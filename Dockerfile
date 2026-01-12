# Build stage
FROM swift:6.0-jammy AS build

# Install system dependencies
RUN apt-get update && apt-get install -y \
    libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /build

# Copy entire project
COPY . .

# Build the server in release mode
RUN swift build -c release --product MonadServer

# Run stage
FROM swift:6.0-jammy-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    libsqlite3-0 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user
RUN useradd --user-group --create-home --system monad

# Set working directory
WORKDIR /app

# Copy the built executable from the build stage
COPY --from=build /build/.build/release/MonadServer .

# Ensure the executable is owned by the monad user
RUN chown monad:monad MonadServer

# Set the user
USER monad

# Expose gRPC port
EXPOSE 50051

# Run the server
CMD ["./MonadServer"]
