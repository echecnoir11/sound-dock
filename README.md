# ++sound@dock — UI @@ennuienoir

Petit panneau flottant macOS (barre des menus) qui applique des effets en direct
au son système ou à un fichier audio : vitesse 0,5×–2× avec pitch indépendant,
bass boost, pitch, reverb, égaliseur 3 bandes, presets, visualiseur.

Version 2.0 : refonte graphique reprenant le design d'[@@ennuienoir](https://github.com/echecnoir11/ennuienoir)
(light / noir, barres « gooey », Helvetica Neue Thin + JetBrains Mono).

<p>
  <img src="docs/apercu-light.png" width="300" alt="Panneau en mode light">
  <img src="docs/apercu-noir.png" width="300" alt="Panneau en mode noir">
</p>

## Prérequis
- macOS 13+, Apple Silicon.
- [BlackHole 2ch](https://github.com/ExistentialAudio/BlackHole), uniquement pour traiter le son système.

## Construire
```bash
./build.command
```
L'application est créée dans `outputs/++sound@dock.app` (signature locale, non notarisée).

## Tests
```bash
swift test --disable-sandbox --build-system native
```

Le détail du fonctionnement (réserve de vitesse, sorties, transparence…) est dans `README.txt`
et `Resources/Guide.html`.

## Licence
MIT — voir [LICENSE](LICENSE). JetBrains Mono est sous SIL OFL 1.1.
