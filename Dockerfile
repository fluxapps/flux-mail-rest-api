ARG FLUX_AUTOLOAD_API_IMAGE
ARG FLUX_MAIL_API_IMAGE
ARG FLUX_NAMESPACE_CHANGER_IMAGE=docker-registry.fluxpublisher.ch/flux-namespace-changer
ARG FLUX_REST_API_IMAGE

FROM $FLUX_AUTOLOAD_API_IMAGE:v2022-06-22-1 AS flux_autoload_api
FROM $FLUX_MAIL_API_IMAGE:v2022-07-05-1 AS flux_mail_api
FROM $FLUX_REST_API_IMAGE:v2022-06-29-2 AS flux_rest_api

FROM $FLUX_NAMESPACE_CHANGER_IMAGE:v2022-06-23-1 AS build_namespaces

COPY --from=flux_autoload_api /flux-autoload-api /code/flux-autoload-api
RUN change-namespace /code/flux-autoload-api FluxAutoloadApi FluxMailRestApi\\Libs\\FluxAutoloadApi

COPY --from=flux_mail_api /flux-mail-api /code/flux-mail-api
RUN change-namespace /code/flux-mail-api FluxMailApi FluxMailRestApi\\Libs\\FluxMailApi

COPY --from=flux_rest_api /flux-rest-api /code/flux-rest-api
RUN change-namespace /code/flux-rest-api FluxRestApi FluxMailRestApi\\Libs\\FluxRestApi

FROM alpine:latest AS build

COPY --from=build_namespaces /code/flux-autoload-api /build/flux-mail-rest-api/libs/flux-autoload-api
COPY --from=build_namespaces /code/flux-mail-api /build/flux-mail-rest-api/libs/flux-mail-api
COPY --from=build_namespaces /code/flux-rest-api /build/flux-mail-rest-api/libs/flux-rest-api
COPY . /build/flux-mail-rest-api

RUN (cd /build && tar -czf flux-mail-rest-api.tar.gz flux-mail-rest-api)

FROM php:8.1-cli-alpine

LABEL org.opencontainers.image.source="https://github.com/flux-caps/flux-mail-rest-api"
LABEL maintainer="fluxlabs <support@fluxlabs.ch> (https://fluxlabs.ch)"

RUN apk add --no-cache imap-dev libstdc++ && \
    apk add --no-cache --virtual .build-deps $PHPIZE_DEPS openssl-dev && \
    (mkdir -p /usr/src/php/ext/swoole && cd /usr/src/php/ext/swoole && wget -O - https://pecl.php.net/get/swoole | tar -xz --strip-components=1) && \
    docker-php-ext-configure imap --with-imap-ssl && \
    docker-php-ext-configure swoole --enable-openssl --enable-swoole-json && \
    docker-php-ext-install -j$(nproc) imap swoole && \
    docker-php-source delete && \
    apk del .build-deps

USER www-data:www-data

EXPOSE 9501

ENTRYPOINT ["/flux-mail-rest-api/bin/server.php"]

COPY --from=build /build /

ARG COMMIT_SHA
LABEL org.opencontainers.image.revision="$COMMIT_SHA"
