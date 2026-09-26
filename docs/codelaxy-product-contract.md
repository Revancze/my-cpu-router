# Produktový kontrakt Codelaxy

## Identita produktu

Codelaxy je Git-native.

Git je základní součást infrastruktury Codelaxy, nikoli Provider.

Codelaxy je určena pro Git repozitáře a používá Git jako zdroj pravdy pro:
- stav repozitáře,
- identitu Snapshotu,
- historii,
- index,
- worktree,
- reference a Git objekty.

## Veřejné CLI

Veřejné příkazy Codelaxy jsou:

- `codelaxy status`
- `codelaxy init`
- `codelaxy verify`
- `codelaxy explain`
- `codelaxy verdict`

Další interní komponenty nejsou součástí veřejného CLI.

## Základní slovník

Codelaxy používá tyto hlavní pojmy:

- `Snapshot`
- `Requirement`
- `Evidence`
- `Verdict`
- `Provider`

Staré názvy se nahrazují:

- `Plan` → `Requirement`
- `Receipt` → `Evidence`

## Hranice Provideru

Codelaxy core nevlastní sémantiku:

- buildu,
- testování,
- lintingu,
- formátování,
- kompilace,
- linkování.

Tyto činnosti patří Providerům a externím nástrojům.

Codelaxy rozhoduje:
- co musí být prokázáno,
- co už bylo prokázáno,
- zda je Evidence stále platná,
- zda může být Evidence znovu použita,
- proč byla Evidence zneplatněna,
- zda může být vydán úspěšný Verdict.

Provider rozhoduje:
- jak se čerstvá Evidence získá.

## Základní pravidlo

Codelaxy není build systém.

Codelaxy je evidence engine pro Git projekty.
