FROM rust:1-slim AS build
WORKDIR /app
COPY Cargo.toml Cargo.lock ./
COPY src ./src
RUN cargo build --release

FROM gcr.io/distroless/cc-debian12
COPY --from=build /app/target/release/ticket-alert /ticket-alert
ENV PORT=8080
CMD ["/ticket-alert"]
