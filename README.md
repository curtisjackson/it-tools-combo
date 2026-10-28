# it-tools-combo

Несколько self-hosted утилит для разработчика в одном образе: один nginx, один порт, одна стартовая страница с поиском.

| Путь | Утилита | Откуда |
|---|---|---|
| `/` | Стартовая страница | [`home/`](home) |
| `/it-tools/` | [IT-Tools (форк sharevb)](https://github.com/sharevb/it-tools) | статика из `ghcr.io/sharevb/it-tools` |
| `/cyberchef/` | [CyberChef](https://github.com/gchq/CyberChef) | статика из `ghcr.io/gchq/cyberchef` |
| `/omni/` | [Omni-Tools](https://github.com/iib0011/omni-tools) | собирается из исходников под подпуть |

Всё работает в браузере: у образа нет состояния, томов и БД.

## Запуск

```sh
docker compose up -d
```

[`compose.yaml`](compose.yaml) поднимает образ `ghcr.io/curtisjackson/it-tools-combo:latest` на `192.168.1.11:9449`. Рядом работает Watchtower: каждую ночь он проверяет `:latest` и перезапускает контейнер, если вышла новая сборка. Он следит только за контейнерами этого стека.

Локальная сборка и проверка:

```sh
docker build -t it-tools-combo:dev .
docker run --rm -d --name combo --read-only --tmpfs /tmp -p 127.0.0.1:9449:8080 it-tools-combo:dev
tests/smoke.sh http://127.0.0.1:9449
```

## Как устроено

- **it-tools** собран с относительными путями и одним тегом `<base href="/">`. При сборке тег меняется на `/it-tools/`. Для утилит на WebAssembly nginx отдаёт `COOP`/`COEP`.
- **CyberChef** использует только относительные пути и работает на подпути как есть. Офлайн-архив (~80 МБ) из образа удалён, поэтому ссылка «Download CyberChef» внутри приложения не работает.
- **Omni-Tools** собирается под корень домена. [`scripts/patch-omni-tools.sh`](scripts/patch-omni-tools.sh) правит роутер, путь к переводам, фон и манифест, а Vite собирается с `--base=/omni/`. Каждая замена проверяется: если upstream поменял код, сборка падает.
- В it-tools через `external-tools.json` добавлена категория «Combo» со ссылками на остальные утилиты.

## Обновления

1. Версии утилит записаны в `ARG` в начале [`Dockerfile`](Dockerfile).
2. Renovate ([`renovate.json`](renovate.json)) замечает новые релизы и открывает PR.
3. GitHub Actions собирает образ и прогоняет [`tests/smoke.sh`](tests/smoke.sh).
4. Minor и patch сливаются автоматически после зелёного CI, major — вручную.
5. После merge в `main` образ публикуется в GHCR как `:latest` и `:ГГГГ.ММ.ДД-sha`. Раз в неделю образ пересобирается ради обновлений nginx и node.
6. Watchtower на сервере подтягивает новый `:latest`.

Откат: укажите в `compose.yaml` тег предыдущей сборки вместо `latest`.

### Как добавить утилиту

1. Добавьте стадию в `Dockerfile` и `COPY` в стадию `assemble`.
2. Добавьте `location` в [`nginx.conf`](nginx.conf).
3. Добавьте карточку в [`home/tools.json`](home/tools.json) и при желании в `it-tools/external-tools.json`.
4. Добавьте проверки в `tests/smoke.sh`.

## Лицензии

Образ содержит сборки сторонних проектов под их лицензиями:

- IT-Tools: [GPL-3.0](https://github.com/sharevb/it-tools/blob/chore/all-my-stuffs/LICENSE), исходники в [sharevb/it-tools](https://github.com/sharevb/it-tools).
- CyberChef: [Apache-2.0](https://github.com/gchq/CyberChef/blob/master/LICENSE), исходники в [gchq/CyberChef](https://github.com/gchq/CyberChef).
- Omni-Tools: [MIT](https://github.com/iib0011/omni-tools/blob/main/LICENSE), исходники в [iib0011/omni-tools](https://github.com/iib0011/omni-tools), изменения в [`scripts/patch-omni-tools.sh`](scripts/patch-omni-tools.sh).

Точные версии каждой сборки — в `ARG` [`Dockerfile`](Dockerfile) и в `/versions.json` запущенного контейнера.
