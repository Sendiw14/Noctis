// The six sounds and their names live in `SoundCatalog`, a module with no audio in it, so a widget extension can name a sound without
// linking the player (APP_RULES.md R48). Everything that imports SoundKit still sees `SoundKind` as before.
@_exported import SoundCatalog
