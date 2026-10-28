# syntax=docker/dockerfile:1

# Версии утилит. Их поднимает Renovate (см. renovate.json), руками менять тоже можно.
# renovate: datasource=docker depName=ghcr.io/sharevb/it-tools
ARG IT_TOOLS_VERSION=2026.9.27
# renovate: datasource=docker depName=ghcr.io/gchq/cyberchef
ARG CYBERCHEF_VERSION=11.5.0
# renovate: datasource=github-tags depName=iib0011/omni-tools
ARG OMNI_TOOLS_VERSION=v0.7.0

# it-tools и CyberChef собраны с относительными путями — берём готовую статику из официальных образов.
FROM ghcr.io/sharevb/it-tools:${IT_TOOLS_VERSION} AS it-tools
FROM ghcr.io/gchq/cyberchef:${CYBERCHEF_VERSION} AS cyberchef

# Omni-Tools собран под корень домена, поэтому собираем из исходников под /omni/.
FROM node:22 AS omni-tools
ARG OMNI_TOOLS_VERSION
WORKDIR /src
# Полный .git не нужен, но vite.config.ts вызывает `git rev-parse`, так что клонируем через git.
RUN git clone --depth 1 --branch "${OMNI_TOOLS_VERSION}" https://github.com/iib0011/omni-tools.git .
RUN HUSKY=0 npm ci --no-audit --no-fund
COPY scripts/patch-omni-tools.sh /tmp/patch-omni-tools.sh
RUN sh /tmp/patch-omni-tools.sh
RUN npm run build -- --base=/omni/

# Собираем всё дерево /srv в отдельной стадии: в итоговый образ попадает один слой без лишних файлов.
FROM alpine:3 AS assemble
ARG IT_TOOLS_VERSION
ARG CYBERCHEF_VERSION
ARG OMNI_TOOLS_VERSION
COPY --from=it-tools   /usr/share/nginx/html /srv/it-tools
COPY --from=cyberchef  /usr/share/nginx/html /srv/cyberchef
COPY --from=omni-tools /src/dist             /srv/omni
COPY home/                        /srv/home/
COPY it-tools/external-tools.json /srv/it-tools/external-tools.json
# it-tools берёт базовый путь из единственного тега <base href="/"> — переносим его на /it-tools/.
# Если тег пропадёт из сборки, падаем сразу, а не отдаём сломанную страницу.
RUN grep -q '<base href="/">' /srv/it-tools/index.html \
 && find /srv/it-tools -name '*.html' -exec sed -i 's|<base href="/">|<base href="/it-tools/">|' {} + \
 # Офлайн-архив CyberChef (~80 МБ) и отчёт webpack в сборке не нужны.
 && rm -f /srv/cyberchef/CyberChef_v*.zip /srv/cyberchef/BundleAnalyzerReport.html \
 && printf '{"it-tools":"%s","cyberchef":"%s","omni-tools":"%s"}\n' \
      "${IT_TOOLS_VERSION}" "${CYBERCHEF_VERSION}" "${OMNI_TOOLS_VERSION#v}" > /srv/home/versions.json

FROM nginxinc/nginx-unprivileged:stable-alpine

LABEL org.opencontainers.image.source=https://github.com/curtisjackson/it-tools-combo \
      org.opencontainers.image.description="it-tools, CyberChef и Omni-Tools в одном nginx за одним портом" \
      org.opencontainers.image.licenses=GPL-3.0-only

COPY --from=assemble /srv /srv
COPY nginx.conf /etc/nginx/conf.d/default.conf

USER root
# По умолчанию nginx запускает воркер на каждое ядро хоста; для статики хватит двух.
RUN sed -i 's/^worker_processes.*/worker_processes 2;/' /etc/nginx/nginx.conf
USER nginx

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1
