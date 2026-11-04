<p align="center">
  <img src="docs/icon.png" alt="MoveMouse" width="160">
</p>

# MoveMouse

Mała aplikacja dla macOS działająca wyłącznie w pasku menu. Gdy użytkownik jest bezczynny, płynnie porusza kursorem, żeby inne programy widziały aktywność (odpowiednik Move Mouse z Windowsa).

## Funkcje

- Ikona tylko w pasku menu (bez ikony w Docku).
- Ruch następuje **tylko po wykryciu bezczynności** użytkownika; próg jest konfigurowalny.
- Losowy kierunek i losowa odległość (od 1 px do ustawionego maksimum), w granicach ekranów.
- Płynna animacja ruchu (ease-in-out), przerywana, gdy użytkownik dotknie myszy.
- Konfigurowalny odstęp między ruchami.
- Harmonogram: osobne włączenie i godziny pracy dla każdego dnia tygodnia (tydzień od poniedziałku, przedziały przez północ działają).
- Ikona w pasku menu zmienia kolor na zielony, gdy aplikacja faktycznie porusza myszą.
- Opcjonalne uruchamianie przy logowaniu (`SMAppService`).
- Ustawienia zapisywane między uruchomieniami.

## Wymagania

- macOS 14 lub nowszy
- Xcode (do zbudowania), opcjonalnie [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Budowanie

```sh
open MoveMouse.xcodeproj
```

albo z wiersza poleceń:

```sh
xcodebuild -project MoveMouse.xcodeproj -scheme MoveMouse -configuration Release -derivedDataPath build build
```

Aplikacja powstaje w `build/Build/Products/Release/MoveMouse.app`. Przed uruchomieniem z Xcode ustaw własny Team w *Signing & Capabilities*.

Konfiguracja projektu jest w `project.yml`; po jej zmianie odtwórz projekt poleceniem `xcodegen generate`.

## Uprawnienia

Do poruszania kursorem potrzebne jest uprawnienie **Dostępność**: *Ustawienia systemowe → Prywatność i ochrona → Dostępność*. Aplikacja poprosi o nie z poziomu menu.

Autostart najlepiej włączać z aplikacji skopiowanej do `/Applications`.

## Struktura

- `MoveMouse/MoveMouseApp.swift` – cały kod aplikacji
- `MoveMouse/Assets.xcassets` – ikona szczura (SVG)
- `project.yml` – definicja projektu dla XcodeGen
- `docs/icon.png` – szara ikona użyta w README
