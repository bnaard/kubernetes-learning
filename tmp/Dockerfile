FROM alpine AS cmatrixbuilder

WORKDIR cmatrix

RUN apk update && \
    apk add git autoconf automake alpine-sdk ncurses-dev ncurses-static && \
    git clone https://github.com/spurin/cmatrix.git . &&\
    autoreconf -i && \
    mkdir -p /usr/lib/kbd/consolefonts /usr/share/consolefonts && \
   ./configure LDFLAGS="-static" && \
   make

FROM alpine

LABEL org.opencontainers.image.authors="Bnaard"

RUN apk update && \
    apk add ncurses-terminfo-base && \
    adduser -g "Thomas Anderson" -s /usr/sbin/nologin -D -H thomas

COPY  --from=cmatrixbuilder /cmatrix/cmatrix /cmatrix
USER thomas
ENTRYPOINT ["./cmatrix"]
CMD ["-b"]

