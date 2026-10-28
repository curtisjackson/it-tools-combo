#!/bin/sh
# Учит Omni-Tools работать не из корня домена, а из подпути (vite --base=/omni/).
# Vite сам переписывает пути к ассетам и index.html, но в коде остались абсолютные пути.
# Каждая замена проверяется: если upstream поменял код, сборка падает, а не выпускает сломанный образ.
set -eu

replace() {
  file=$1 from=$2 to=$3
  if ! grep -qF "$from" "$file"; then
    echo "patch-omni-tools: '$from' не найден в $file — проверьте патч под новую версию" >&2
    exit 1
  fi
  # Разделитель '#' — в заменах встречаются '/' и '|'.
  sed -i "s#$(printf '%s' "$from" | sed 's/[]#.*^$[\\]/\\&/g')#$(printf '%s' "$to" | sed 's/[#&\\]/\\&/g')#g" "$file"
}

# Роутер без basename: на /omni/ все маршруты уходили бы в 404.
replace src/components/App.tsx '<BrowserRouter>' '<BrowserRouter basename={import.meta.env.BASE_URL}>'
# Переводы грузятся по абсолютному пути.
replace src/i18n/index.ts "loadPath: '/locales/" "loadPath: import.meta.env.BASE_URL + 'locales/"
# Фон главной страницы.
replace src/pages/home/index.tsx 'url(/assets/${' 'url(${import.meta.env.BASE_URL}assets/${'
# Иконки PWA в манифесте (Vite его не трогает).
replace public/site.webmanifest '"src": "/' '"src": "/omni/'

echo "patch-omni-tools: OK"
