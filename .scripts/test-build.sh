#!/usr/bin/env bash
tmpdir=$(mktemp -d)
# 0: exit shell
# 2: Interrupt
# 3: Quit
# 15: Terminate
trap "rm -f $tmpdir" 0 2 3 15

git clone git@github.com:alistaircol/ac-netlify.git $tmpdir

docker run --rm --interactive --tty --user=$(id -u) --volume="$tmpdir:/src" klakegg/hugo:0.75.1-ext --baseUrl=http://localhost:9999

cat <<EOF > "$tmpdir/Dockerfile"
FROM caddy:2-alpine
WORKDIR /usr/share/caddy/
COPY ./public /usr/share/caddy/
EXPOSE 80
EOF

docker build --force-rm --tag=alistaircol/ac93 "$tmpdir"
open "http://localhost:9999"

docker run --rm -p 9999:80 alistaircol/ac93:latest
