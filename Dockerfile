FROM elixir:1.18-otp-27-alpine AS builder

RUN apk add --no-cache build-base git

WORKDIR /app

COPY mix.exs mix.lock* ./
RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get && \
    mix deps.compile

COPY lib/ ./lib/
COPY config/ ./config/
COPY priv/ ./priv/

RUN mix compile

# --- Runtime ---
FROM elixir:1.18-otp-27-alpine

RUN apk add --no-cache python3 bash tini

WORKDIR /app

COPY --from=builder /app/_build /app/_build
COPY --from=builder /app/deps /app/deps
COPY --from=builder /app/mix.exs /app/
COPY --from=builder /app/mix.lock /app/
COPY --from=builder /app/config /app/config
COPY --from=builder /app/lib /app/lib
COPY --from=builder /app/priv /app/priv
COPY --from=builder /root/.mix /root/.mix

ENV TERM=xterm

ENTRYPOINT ["tini", "--"]
CMD ["mix", "run", "--no-halt"]
