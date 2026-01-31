# Stage 1: Build
# Using 'alpine' without a number ensures it uses the latest stable Alpine
FROM elixir:1.17-alpine AS builder

# Install build dependencies including git
RUN apk add --no-cache build-base git

WORKDIR /app
RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

COPY . .
RUN mix release

# Stage 2: Runtime
# Using the same 'alpine' base ensures OpenSSL versions match exactly
FROM alpine:latest AS runner

# Install runtime dependencies
RUN apk add --no-cache libstdc++ openssl ncurses-libs

WORKDIR /app

# Ensure this matches your app name from mix.exs
COPY --from=builder /app/_build/prod/rel/nexus_realtime_server ./

# Set the command to start your application
CMD ["bin/nexus_realtime_server", "start"]
