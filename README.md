# AgroTehComert Service

Десктопное и мобильное приложение для сервиса [service.agrotehcomert.com](https://service.agrotehcomert.com).

## Скачать

Последний релиз: [Releases](https://github.com/trekgame55/apk/releases/latest)

- **Android**: `AgroTehComert-vX.Y.Z.apk` — установить на телефон
- **Windows**: `AgroTehComert-Setup-vX.Y.Z.exe` — запустить установщик, выбрать язык, нажать «Установить»

## Авто-обновления

После первой установки приложение само проверяет наличие обновлений на GitHub при запуске. Если есть новая версия — предложит её скачать и установить автоматически (одной кнопкой).

## Сборка

Сборка происходит автоматически на GitHub Actions при каждом push в `main`:

- **Android APK** — Ubuntu runner
- **Windows installer** — Windows runner с Inno Setup
- **GitHub Release** — оба файла прикрепляются автоматически

См. `.github/workflows/build.yml`.
