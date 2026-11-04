++sound@dock — V2.0 / 0.4.0 (build 11) — UI @@ennuienoir
macOS 13+, Apple Silicon.

LANCER
Ouvrir outputs/++sound@dock.app. Le panneau est accessible depuis l’icône waveform
de la barre des menus. Guide complet : Resources/Guide.html ou bouton Guide.
BlackHole 2ch est requis uniquement pour traiter le son système.

VITESSE SYSTÈME EXPÉRIMENTALE
Mode Système > activer « Vitesse en direct · réserve 30 s » > Connecter.
Après environ trente secondes de chargement, vitesse de 0,5× à 2× avec pitch
indépendant. L’interrupteur peut aussi reconnecter un traitement déjà actif.
Accélération : réserve vidée puis recharge automatique d’environ trente secondes.
Ralenti : retard croissant, réserve bornée à soixante secondes ; à saturation,
les plus anciens instants sont sautés pour revenir à trente secondes de réserve.
Ces transitions peuvent s’entendre. Aucun speed global illimité/synchronisé
n’est promis. Les vidéos/appels ne suivent pas ce retard.
Bypass ramène la vitesse à 1× sans retirer le retard ; Reset aussi, sans
retirer le mode réserve. Désactiver le mode reconnecte le direct habituel.
Un fichier local peut être lu en continu à vitesse variable sans BlackHole.

AUDIO
Capture HAL des canaux BlackHole d’un agrégat privé, correction de dérive,
tampon stéréo à index atomiques, AVAudioSourceNode, EQ/bass, TimePitch,
reverb, limiteur, sortie physique explicitement fixée par setDeviceID.
Pas d’entrée microphone dans AVAudioEngine. Réserve uniquement en RAM.
Niveau neutre conservé à volume 100 % ; limiteur actif en cas de crêtes.
Arrêter/Quitter restaure la sortie précédente. Après arrêt forcé : relancer
l’app ou choisir une sortie physique dans Réglages Système > Son.
Témoins Entrée/Sortie, signalement de sourdine, destination réelle vérifiée.

CONSTRUIRE / TESTER
Avec Xcode ou ses outils développeur : ./build.command
Application et ZIP créés à côté du projet, signature locale non notarisée.
swift test --disable-sandbox --build-system native
Voir TESTS.txt et Test-results.log. Les tests ne modifient pas la sortie système.
Sources/SoundDock/ : panneau SwiftUI/AppKit et moteur AVAudioEngine.
Sources/AudioGuard/ : capture CoreAudio, tampon C atomique, exceptions.
Tests/SoundDockTests/ : effets, niveaux, vitesse, réserve et erreurs.

STYLE ET LOGO
Frosted Sauge (#111410, #c4d3b8, #a4c797), JetBrains Mono Regular incluse
avec sa licence SIL OFL. Logo IC5.png fourni par l’utilisateur : détourage
par imagegen, consigne de retirer le blanc en préservant DVD Audio ;
BrandLogo.png transparent, affiché en sauge dans le panneau.

PRESETS ET VISUALISEUR — V1.3
Menu Presets : sélectionner, enregistrer les réglages actuels, renommer,
supprimer. Chaque preset conserve uniquement vitesse, bass boost et volume.
Stockage JSON dans UserDefaults, clé audioPresets.v1. Les autres effets et
le mode courant sont conservés ; sélection sans redémarrage du moteur.
En direct habituel, une vitesse mémorisée ne devient effective que si le
mode réserve est activé. Aucun preset ne l’active automatiquement.
Visualiseur : seize barres d’amplitude du signal traité, lecture du même
flux de sortie, rafraîchissement maximal 30 Hz, retour au repos en silence.
Les barres ne sont pas un analyseur de fréquences. Aucun nouveau pilote,
framework, dépendance externe ou chemin de capture n’est ajouté.

TRANSITIONS ET SORTIES — V1.4
Lissage : transitions de 300 ms pour basses, volume et vitesse active.
Les changements de cible repartent du niveau courant ; désactiver le
lissage applique directement les valeurs. Aucun tampon de latence ajouté.
Le sélecteur Sortie reste utilisable pendant le traitement ; la liste est
actualisée par les notifications de périphériques CoreAudio.
Système : reconnexion du même chemin existant, courte interruption possible
et recharge de la réserve si activée. Fichier : changement sur le moteur
courant ; si macOS interrompt ce moteur, relancer le fichier est nécessaire.
Les sorties physiques stéréo sont proposées ; les périphériques virtuels
sont exclus pour prévenir les boucles. Un débranchement arrête la lecture
et propose une sortie restante. Le mode Fichier ne change pas la sortie
par défaut de macOS ; le mode Système conserve le routage BlackHole requis.
Visualiseur : 16 colonnes de 10 segments, allumage du bas vers le haut
proportionnel au niveau du signal. Le rendu reste plafonné à environ 30 Hz.

TRANSPARENCE — V1.5
Icône de demi-cercle dans l’en-tête > Opacité du fond : 70–100 %, 88 % par
défaut. Valeur conservée dans UserDefaults (window.backgroundOpacity).
Fond NSVisualEffectView natif, HUD sombre et vibrancy derrière la fenêtre.
Seul le fond change d’opacité : panneau à alpha 1 et contenu inchangé.
Blur natif actif en mode épinglé/flottant comme en mode normal. À 100 %,
ou si macOS active Réduire la transparence, fond uni pour la lisibilité.
Aucun changement du moteur audio, de son routage ou des dépendances.

UI @@ENNUIENOIR — V2.0
Copie de V1.5 avec la refonte graphique reprise d'@@ennuienoir ; le moteur
audio, les presets et les tests sont inchangés. Bundle id distinct
(audio.sounddock.ennuienoir) pour cohabiter avec V1.5 : les presets et
réglages de V1.5 ne sont pas repris.
Sources/SoundDock/Theme.swift : palette light / noir, Helvetica Neue Thin +
JetBrains Mono (Thin/Light/Regular/Medium, Resources/Fonts), barres sombres
« gooey » (metaballs), sliders fins à graduations, pill toggles, chips,
pictos template (Resources/Icons : ring, heart…).
Bouton soleil / lune ou icône demi-cercle > light / noir (clé ui.dark).
Double-clic sur un slider : valeur par défaut.
