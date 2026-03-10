FROM alpine:latest AS zig
RUN apk add --no-cache xz curl
ARG ZIG_ARCH=aarch64
RUN curl -L https://ziglang.org/builds/zig-${ZIG_ARCH}-linux-0.16.0-dev.2722+f16eb18ce.tar.xz | tar -xJ -C /opt
ENV PATH="/opt/zig-${ZIG_ARCH}-linux-0.16.0-dev.2722+f16eb18ce:$PATH"

WORKDIR /src
COPY build.zig build.zig.zon direct.zig ./
RUN zig build
RUN zig build run-no-libc 2>&1; echo "exit: $?"

FROM alpine:latest
COPY --from=zig /src/zig-out/bin/repro-libc /repro-libc
COPY --from=zig /src/zig-out/bin/repro-no-libc /repro-no-libc
CMD ["sh", "-c", "echo '--- no-libc ---' && /repro-no-libc; echo \"exit: $?\" && echo '--- libc ---' && /repro-libc; echo \"exit: $?\""]
