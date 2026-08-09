#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"

flutter create --platforms=android,ios,web --org ru.buronahodok .
flutter pub get
flutter analyze
flutter test

echo "Готово. Запустите: flutter run"
