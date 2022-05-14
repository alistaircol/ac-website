FROM caddy:2-alpine
WORKDIR /usr/share/caddy/
COPY ./public /usr/share/caddy/
EXPOSE 80
