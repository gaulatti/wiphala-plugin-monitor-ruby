# syntax=docker/dockerfile:1
# check=error=true

# Use a minimal Ruby base image
ARG RUBY_VERSION=3.2.2
FROM ruby:$RUBY_VERSION-slim AS base

# Set working directory
WORKDIR /app

# Install required system dependencies
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment
ENV BUNDLE_PATH="/usr/local/bundle"

# Separate build stage to optimize final image size
FROM base AS build

# Install build tools for gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

# Copy application source
COPY . .

# Final image
FROM base

# Copy built gems and application files
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /app /app

# Create and switch to a non-root user for security
RUN groupadd --system --gid 1000 appuser && \
    useradd appuser --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R appuser:appuser /app
USER 1000:1000

# Expose the gRPC port
EXPOSE 50052

# Run the gRPC worker
CMD ["./bin/worker"]