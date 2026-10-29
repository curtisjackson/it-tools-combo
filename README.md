# it-tools-combo

Стек сервера `cj_serv` для http://tools.bit2byte.pro/: [форк IT-Tools](https://github.com/curtisjackson/it-tools) с перенесёнными утилитами Omni-Tools и CyberChef, плюс Watchtower.

Раньше здесь собирался общий образ из трёх приложений (IT-Tools, CyberChef и Omni-Tools за одним nginx со стартовой страницей). Их утилиты теперь в самом форке, поэтому сборка ушла туда, а здесь остался только стек. Старая версия — в истории git до коммита `20259f8`.

## Запуск

```sh
docker compose up -d
```

[`compose.yaml`](compose.yaml) поднимает `ghcr.io/curtisjackson/it-tools:latest` на `192.168.1.11:9449`. Контейнер работает с файловой системой только для чтения, `/tmp` — в tmpfs. Healthcheck запрашивает главную страницу.

Проверка запущенного контейнера:

```sh
sh tests/smoke.sh http://192.168.1.11:9449/
```

[`tests/smoke.sh`](tests/smoke.sh) — копия `scripts/fork/smoke.sh` из форка. Он проверяет страницу и заголовки COOP/COEP, `<base href>`, прямую ссылку, сжатые ассеты, чанки утилит форка и ядро ffmpeg.

## Обновления

1. Форк собирает образ после каждого зелёного CI на `main` и раз в неделю, ради обновлений nginx и node. Подробности — в [`FORK.md`](https://github.com/curtisjackson/it-tools/blob/main/FORK.md).
2. Образ публикуется в GHCR как `:latest` и `:ГГГГ.ММ.ДД-sha`.
3. Watchtower каждую ночь в 04:00 МСК проверяет `:latest` и перезапускает контейнер. Он следит только за контейнерами этого стека.

Откат: укажите в `compose.yaml` тег предыдущей сборки вместо `latest` и выполните `docker compose up -d`. Пока стоит фиксированный тег, Watchtower ничего не обновляет.

## Лицензия

Образ — сборка [curtisjackson/it-tools](https://github.com/curtisjackson/it-tools), форка [sharevb/it-tools](https://github.com/sharevb/it-tools) под [GPL-3.0](https://github.com/sharevb/it-tools/blob/chore/all-my-stuffs/LICENSE). Перенесённый код Omni-Tools (MIT) и CyberChef (Apache-2.0) перечислен в его `THIRD_PARTY.md`.
