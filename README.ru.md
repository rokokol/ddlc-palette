<div align="center">

# Палитра DDLC

**Цвета Doki Doki Literature Club, снятые с официального сайта** ⊂(◉‿◉)つ

![source](https://img.shields.io/badge/source-ddlc.moe-FF80C0?style=flat)
![Nix](https://img.shields.io/badge/Nix-flake-7EBAE4?style=flat&logo=nixos&logoColor=white)
[![license](https://img.shields.io/badge/code-MIT-3DA639?style=flat)](LICENSE)
[![check](https://github.com/rokokol/ddlc-palette/actions/workflows/check.yml/badge.svg)](https://github.com/rokokol/ddlc-palette/actions/workflows/check.yml)

<img src="dist/palette.svg" alt="палитра" width="680"/>

[English](README.md)

</div>

Единственный источник правды для всего, что я делаю в стиле DDLC, чтобы один и тот же розовый не подбирался на глаз в пятый раз. Источник — [`palette.json`](palette.json), всё в [`dist/`](dist) из него генерируется и коммитится, так что потребителю без Nix достаточно прочитать файл

## Откуда взяты числа

Не со скриншота и не на вкус — с самого [ddlc.moe](https://ddlc.moe/):

| | что прочитано |
| --- | --- |
| **интерфейс** | `main.css` — разделитель, кнопка и её hover, цвет ссылок, тёмный футер |
| **dot**, **paper** | `images/tilebg.png`, фоновый тайл сайта: 200×200, кружки радиуса 40 на решётке со сдвигом в полшага, `#FFDBF0` на белом |
| **персонажи** | спрайты `sticker_?.png`, самый частый цвет волос по верхней части головы |

Придуманы только `error` и `corrupt` — состояния ошибки на сайте нет, копировать нечего

У каждой записи в `palette.json` есть свои `where` и `source`, так что происхождение любого цвета прослеживается

## Как пользоваться

**Nix.** Флейк отдаёт палитру просто данными — ни модуля, ни опций, включать нечего:

```nix
{
  inputs.ddlc-palette.url = "github:rokokol/ddlc-palette";

  # inputs.ddlc-palette.lib.palette.plum  ->  "#BB5599"
  # inputs.ddlc-palette.lib.bare.plum     ->  "BB5599"   (hyprland, hyprlock, mako)
  # inputs.ddlc-palette.lib.annotated     ->  по группам, с происхождением
}
```

**Всё остальное.** Бери файл, который подходит:

| файл | вид |
| --- | --- |
| `dist/palette.css` | `:root { --ddlc-plum: #BB5599; … }` |
| `dist/palette.nix` | `{ plum = "#BB5599"; … }` |
| `dist/palette.sh` | `DDLC_PLUM='#BB5599'` — сорсится |
| `dist/palette.env` | `plum=BB5599` — голый хекс, для конфигов, которые не терпят `#` |
| `dist/palette.svg` | карточка со свотчами сверху |

## Поменять цвет

Правишь `palette.json`, затем:

```sh
./generate.sh          # нужен jq
```

Коммитишь оба. CI пересобирает `dist/` и сравнивает с закоммиченным, так что разъехаться они не могут

## Кто использует

- [ddlc-sddm-theme](https://github.com/rokokol/ddlc-sddm-theme) — экран логина
- дальше — то, что будет вынесено из [rokokol/huix](https://github.com/rokokol/huix): hyprlock, waybar, mako, rofi

## Благодарности

Doki Doki Literature Club сделана [Team Salvato](https://teamsalvato.com/), и цвета в том виде, в каком они лежат на их сайте, тоже их — этот репозиторий их только записывает. Проект не аффилирован с ними и ими не одобрен. Код под MIT
