#!/bin/sh
# Проверяет запущенный контейнер: каждая утилита открывается, её главный ассет отдаётся с правильным типом.
# Использование: tests/smoke.sh [http://127.0.0.1:9449]
set -eu

BASE=${1:-http://127.0.0.1:9449}
fail=0

check() { # check <путь> <ожидаемый код> [подстрока в теле]
  path=$1 code=$2 needle=${3:-}
  body=$(mktemp)
  got=$(curl -s -o "$body" -w '%{http_code}' "$BASE$path")
  if [ "$got" != "$code" ]; then
    echo "FAIL $path: код $got, ожидался $code"; fail=1
  elif [ -n "$needle" ] && ! grep -qF -- "$needle" "$body"; then
    echo "FAIL $path: нет '$needle' в ответе"; fail=1
  else
    echo "ok   $path"
  fi
  rm -f "$body"
}

check_type() { # check_type <путь> <часть Content-Type>
  path=$1 type=$2
  got=$(curl -s -o /dev/null -w '%{http_code} %{content_type}' "$BASE$path")
  case "$got" in
    "200 "*"$type"*) echo "ok   $path ($got)" ;;
    *) echo "FAIL $path: $got, ожидался 200 $type"; fail=1 ;;
  esac
}

header() { # header <путь> <заголовок: значение>
  if curl -sI "$BASE$1" | tr -d '\r' | grep -qiF -- "$2"; then
    echo "ok   $1 [$2]"
  else
    echo "FAIL $1: нет заголовка '$2'"; fail=1
  fi
}

# Первый ассет из HTML-страницы по шаблону (относительный путь резолвим от каталога страницы).
asset() { # asset <путь страницы> <regex>
  ref=$(curl -s "$BASE$1" | grep -oE "$2" | head -1 | sed -E 's/^(src|href)="?//; s/"$//')
  case "$ref" in
    /*) echo "$ref" ;;
    "") echo "" ;;
    *) echo "$1${ref#./}" ;;
  esac
}

check /healthz 200 ok
check / 200 '<title>Tools</title>'
check /tools.json 200 '"it-tools"'
check /versions.json 200 '"cyberchef"'

check /it-tools 301
check /it-tools/ 200 '<base href="/it-tools/">'
check /it-tools/base64-string-converter 200 '<base href="/it-tools/">'
check /it-tools/external-tools.json 200 '/cyberchef/'
header /it-tools/ 'Cross-Origin-Embedder-Policy: require-corp'
a=$(asset /it-tools/ 'src="[^"]*assets/index-[^"]+\.js"')
[ -n "$a" ] && check_type "$a" javascript || { echo "FAIL /it-tools/: не найден главный js"; fail=1; }

check /cyberchef 301
check /cyberchef/ 200 'CyberChef'
# CyberChef минифицирует HTML и пишет атрибуты без кавычек.
a=$(asset /cyberchef/ 'src="?[^" >]+\.js')
[ -n "$a" ] && check_type "$a" javascript || { echo "FAIL /cyberchef/: не найден js"; fail=1; }

check /omni 301
check /omni/ 200 '/omni/assets/'
check /omni/image-resize 200 '/omni/assets/'
check_type /omni/locales/en/image.json json
check_type /omni/site.webmanifest manifest+json
check /omni/site.webmanifest 200 '"/omni/web-app-manifest-192x192.png"'
a=$(asset /omni/ 'src="/omni/assets/[^"]+\.js"')
[ -n "$a" ] && check_type "$a" javascript || { echo "FAIL /omni/: не найден главный js"; fail=1; }

check /omni/assets/does-not-exist.js 404
check /nope 404

[ "$fail" = 0 ] && echo "smoke: всё ок" || { echo "smoke: есть ошибки"; exit 1; }
