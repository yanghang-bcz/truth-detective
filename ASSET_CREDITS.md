# Asset provenance

## Detective body base

- Author: Kenney.
- Pack: Blocky Characters 2.0, character-a.
- Official source: https://kenney.nl/assets/blocky-characters
- Download: https://kenney.nl/media/pages/assets/blocky-characters/8369c0cf30-1749547469/kenney_blocky-characters_20.zip
- License: Creative Commons Zero 1.0 (CC0), https://creativecommons.org/publicdomain/zero/1.0/
- Original license and FBX included in assets/characters/source. That folder is excluded from Godot import.
- Modifications: altered proportions, rounded head/sleeve topology, new materials, trench skirt, lapels, epaulettes, pockets, belt, buttons, boots, scarf and fedora. New 7-bone rigid skin and Idle / Walk / Run loops. Original base animation tracks are not used in the final model.
- No Little Nightmares game assets used.

## Existing environment

The user's existing Truth Detective V2 scene and refined building models were reused. Existing Cinzel and DM Serif Display fonts retain their SIL Open Font License files in assets/fonts.

## CJK fallback font

- Font: Noto Sans CJK SC Regular (`assets/fonts/NotoSansCJKsc-Regular.otf`).
- Author: Google / Adobe (Noto CJK project).
- Source: https://github.com/notofonts/noto-cjk
- License: SIL Open Font License 1.1, https://openfontlicense.org/
- Purpose: Web builds cannot access system fonts (PingFang SC etc.), so Chinese text
  needs a bundled font. It is registered as the global fallback (`ThemeDB.fallback_font`)
  and is only used when the primary font lacks a glyph; desktop appearance is unchanged.

## New work

Character accessory geometry, new animation keyframes, controller and integration scripts were created for this project. No additional third-party asset license restriction is introduced for those additions.
