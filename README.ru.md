# Сборки dnstt

[English](README.md)

Неофициальные воспроизводимые сборки [dnstt](https://www.bamsoftware.com/software/dnstt/) —
DNS-туннеля Дэвида Файфилда (David Fifield). **Сборки делает не автор dnstt, и он за них
не отвечает.** Код — dnstt из апстрима как есть, собранный по его тегам выпусков без
изменений.

- страница dnstt и документация: <https://www.bamsoftware.com/software/dnstt/>
- репозиторий апстрима: <https://www.bamsoftware.com/git/dnstt.git>
- зеркало, из которого идёт сборка: <https://github.com/FreedomCats/dnstt>

Как настроить dnstt и пользоваться им, написано на
[странице dnstt](https://www.bamsoftware.com/software/dnstt/) и в файле `README` в каждом
архиве (по-английски); здесь это не пересказывается.

## Платформы

| Система | Архитектура           | Архив                                        |
|---------|-----------------------|----------------------------------------------|
| Linux   | x86-64 (amd64)        | `dnstt-<версия>-linux-amd64.tar.gz`          |
| Linux   | ARM64 (aarch64)       | `dnstt-<версия>-linux-arm64.tar.gz`          |
| Windows | x86-64 (amd64)        | `dnstt-<версия>-windows-amd64.zip`           |
| Windows | ARM64                 | `dnstt-<версия>-windows-arm64.zip`           |
| macOS   | Intel (amd64)         | `dnstt-<версия>-darwin-amd64.tar.gz`         |
| macOS   | Apple silicon (arm64) | `dnstt-<версия>-darwin-arm64.tar.gz`         |

В каждом архиве — один каталог с `dnstt-client` и `dnstt-server` (на Windows — `.exe`) и
файлами dnstt `README`, `CHANGELOG` и `COPYING`. Программы — статические бинари Go
(`CGO_ENABLED=0`), ничего больше им не нужно.

`<версия>` — тег апстрима, например `v1.20260501.0`. Пересборка того же тега (скажем, более
новым Go) получает суффикс: `v1.20260501.0-1`.

Бинари не подписаны. Если macOS (Gatekeeper) не даёт их запустить, снимите флаг карантина:
`xattr -d com.apple.quarantine dnstt-client dnstt-server`. Windows (SmartScreen) может
попросить подтверждение.

## Как проверить скачанное

Скачайте со страницы [Releases](https://github.com/FreedomCats/dnstt-builds/releases)
архив для своей платформы и `SHA256SUMS` и сверьте контрольную сумму:

```sh
# Linux
sha256sum -c --ignore-missing SHA256SUMS
# macOS
grep dnstt-v1.20260501.0-darwin-arm64.tar.gz SHA256SUMS | shasum -a 256 -c
```

```powershell
# Windows (PowerShell): сравните со строкой в SHA256SUMS
(Get-FileHash dnstt-v1.20260501.0-windows-amd64.zip -Algorithm SHA256).Hash.ToLower()
```

У каждого архива есть ещё и подпись происхождения (build provenance attestation):
подписанное заявление, что архив собран workflow выпуска этого репозитория, из какого
коммита и в каком прогоне. Проверяется [GitHub CLI](https://cli.github.com/):

```sh
gh attestation verify dnstt-v1.20260501.0-linux-amd64.tar.gz --repo FreedomCats/dnstt-builds
```

## Как собрать то же самое самому

Сборка воспроизводима: тот же тег, собранный тем же `build.sh`, даёт архивы, байт в байт
равные выпущенным, — так выпуск можно проверить, не доверяя GitHub. Нужны `git`,
POSIX-оболочка и Go 1.21 или новее; Linux или macOS (на Windows — WSL). Точная версия Go —
строка `go` в [`go.mod`](go.mod): `build.sh` сам скачивает её и запускает через
`GOTOOLCHAIN`, какой бы Go ни стоял (качается с прокси модулей Go — нужен доступ к
`proxy.golang.org` или свой `GOPROXY`).

```sh
# Этот репозиторий на выпуске (тег — имя выпуска)
git clone --branch v1.20260501.0 https://github.com/FreedomCats/dnstt-builds
# dnstt на теге апстрима: из зеркала или из апстрима, коммит тот же
git clone --branch v1.20260501.0 https://github.com/FreedomCats/dnstt
#   или: git clone --branch v1.20260501.0 https://www.bamsoftware.com/git/dnstt.git dnstt

dnstt-builds/build.sh dnstt v1.20260501.0 out
diff out/SHA256SUMS SHA256SUMS    # SHA256SUMS выпуска: пустой вывод — совпало
```

Для пересборки вроде `v1.20260501.0-1` выпишите этот репозиторий на `v1.20260501.0-1` и
передайте суффикс четвёртым аргументом: `build.sh dnstt v1.20260501.0 out 1`.

Что делает `build.sh`:

- отказывается собирать тег, которого нет в [`versions.txt`](versions.txt), чекаут, где
  `HEAD` или тег указывают не на записанный там коммит, и чекаут с локальными изменениями;
- собирает обе программы под все платформы с `-trimpath`, `-ldflags "-s -w -buildid="` и
  `CGO_ENABLED=0`, не глядя на настройки Go машины (`go env -w`, `GOFLAGS`, `GOAMD64` и
  подобные);
- упаковывает архивы маленькой программой на Go ([`cmd/pack`](cmd/pack/main.go)), а не
  `tar` и `zip`, чтобы они не зависели от местных утилит, часового пояса и umask: имена
  по порядку, владелец 0:0, время каждого файла — время коммита тега;
- пишет `SHA256SUMS`.

В бинарях записаны версия Go, коммит апстрима и настройки сборки; посмотреть —
`go version -m dnstt-client`.

## Как выпускается релиз (для сопровождающих)

1. Чтобы собрать новый тег апстрима, добавьте его в `versions.txt` с полным хешем коммита.
   Хеш возьмите из апстрима и проверьте, что в зеркале тот же (зеркало сначала обновить):

   ```sh
   git ls-remote --tags https://www.bamsoftware.com/git/dnstt.git 'refs/tags/<тег>^{}'
   git ls-remote --tags https://github.com/FreedomCats/dnstt 'refs/tags/<тег>^{}'
   ```

   Закоммитьте и запушьте в `main`.
2. В Actions запустите workflow **release** из `main`: `tag` — тег апстрима; `suffix` —
   пусто для первой сборки тега, `1`, `2`, … для пересборок (например, после смены версии
   Go в `go.mod`); `draft` по умолчанию включён.
3. Workflow сверяет коммит, гоняет тесты апстрима, собирает, подписывает происхождение и
   создаёт релиз (по умолчанию черновиком). Проверьте черновик и опубликуйте его на
   странице Releases; при публикации в этом репозитории появится тег.

Описание релиза пишет [`release-notes.sh`](release-notes.sh): ссылки на каждый архив, на
исходники dnstt и `SHA256SUMS`, что и чем собрано. Чтобы переписать описание уже созданного
релиза, скачайте его архивы (`gh release download <релиз>`), запустите на них скрипт со
значениями того прогона (их список — в начале скрипта) и передайте вывод в
`gh release edit <релиз> --notes-file`.

Существующий релиз или тег не перезаписывается: workflow останавливается. Запущенный не
из `main`, workflow только собирает и оставляет архивы артефактом прогона.

Запускайте релиз, только когда репозиторий уже публичный: на бесплатном тарифе шаг
подписи происхождения в приватном репозитории падает, и релиз не создаётся.

## Лицензия

Скрипты и документы этого репозитория переданы в общественное достояние по
[CC0 1.0](COPYING), как и сам dnstt. Автор dnstt — Дэвид Файфилд; его `COPYING` лежит в
каждом архиве.
