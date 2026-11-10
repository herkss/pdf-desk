const manualFr = <(String, String)>[
  (
    'Prise en main',
    '''
PDF Desk traite les PDF comme du papier étalé sur un bureau.

## La fenêtre
- En haut : la barre de menus (`Fichier` `Édition` `Document` `Affichage` `Aide`) et la barre d'outils
- En haut à gauche : les dossiers du bureau ; `Mon bureau`, tout en haut, est l'endroit où sont rangés les documents
- En bas à gauche : `Ce PC` — Bureau Windows, Documents, Téléchargements et tous les lecteurs
- Au centre : le bureau, où les documents sont posés comme des feuilles de papier
- À droite : le volet d'aperçu (affiché ou masqué avec `Aperçu` dans la barre d'outils)
- En haut à droite : 🎨 thème, 🌐 langue

## Ajouter des documents
- Faites glisser des PDF ou des images (jpg, png…) de l'Explorateur vers le bureau
- `Fichier` → `Importer des fichiers…` ou `Ctrl+O`
- Imprimez depuis n'importe quel programme vers l'imprimante `PDF Desk`
- Clic droit sur le bureau → `Nouveau document…` (`Ctrl+N`) pour un document vierge

## Le dossier du bureau
Les documents sont des fichiers ordinaires dans `C:\\Users\\<nom>\\PdfDesk`. Vous pouvez le changer dans `Réglages`.
''',
  ),
  (
    'Travailler sur le bureau',
    '''
## Déplacer et sélectionner
- Faites glisser un document où vous voulez ; celui sur lequel vous cliquez passe au-dessus
- Faites glisser sur un espace vide pour sélectionner une zone, `Ctrl`/`Maj`+clic pour en choisir plusieurs, `Ctrl+A` pour tout
- Avec au moins deux documents sélectionnés, une barre `Empiler · Étaler · Classeur` apparaît au-dessus
- Faites glisser avec le bouton du milieu pour déplacer tout le bureau

## Zoom
- `Ctrl`+molette agrandit ou réduit les documents autour de la souris
- Le curseur de la barre d'état et le menu `Affichage` font de même

## Copier
- Sélectionnez des documents et faites-les glisser en maintenant `Ctrl` : des copies sont posées (un `+` vert s'affiche)
- `Ctrl+D` duplique

## Autres
- Double-clic : ouvrir dans la visionneuse
- `F2` renommer, `Suppr` supprimer (vers la corbeille) ; toutes les commandes sont aussi dans le menu du clic droit
- `Ranger` aligne les documents par nom ou par date
''',
  ),
  (
    'Empiler · Étaler · Classeur',
    '''
## Empiler (combiner)
- Déposez un document sur un autre : ses pages sont aussitôt ajoutées à la suite
- Vous pouvez continuer à empiler sur le document combiné autant que vous voulez
- `Annuler`, en bas, revient sur le dernier empilement
- Maintenez `Maj` en déposant pour seulement le poser dessus
- Sélectionnez-en plusieurs et cliquez sur `Empiler` pour les combiner dans l'ordre de sélection

## Étaler
- Sépare un document de plusieurs pages en une feuille par page, posées côte à côte
- Empilez de nouveau les feuilles pour les réunir
- `Scinder (conserver l'original)` crée un document par page et garde l'original

## Classeurs
- Rangez des documents ensemble en gardant chacun séparé (affichés en onglets dans la visionneuse)
- Déposez des documents sur un classeur pour les ajouter ; `Défaire le classeur` les sépare
''',
  ),
  (
    'Ce PC et les dossiers',
    '''
## Dossiers du bureau (en haut à gauche)
- Cliquez sur un dossier pour ouvrir son bureau
- Déposez des documents du bureau sur un dossier pour les y déplacer
- Clic droit : nouveau dossier, renommer, supprimer

## Ce PC (en bas à gauche)
- Parcourez le Bureau Windows, les Documents, les Téléchargements et des lecteurs comme C: et D:
- Cliquez sur un dossier pour voir ses sous-dossiers et ses fichiers PDF et images
- Faites glisser un PDF ou une image du disque vers le bureau pour l'y déplacer (`Ctrl` : copier)
- Faites glisser des documents du bureau vers un dossier du disque pour les copier ; les annotations sont incrustées et un classeur devient un seul PDF
- Faites glisser un fichier vers un autre dossier du disque pour le déplacer (`Ctrl` : copier)
- Clic droit sur un dossier → `Ouvrir comme bureau` pour travailler directement dans ce dossier
- Faites glisser l'en-tête `Ce PC` vers le haut ou le bas pour partager la hauteur
''',
  ),
  (
    'Visionneuse et annotations',
    '''
Double-cliquez sur un document pour ouvrir la visionneuse. Les annotations sont conservées à part et le PDF d'origine ne change pas.

## Outils de dessin
- Stylo, surligneur, ligne, flèche, rectangle, ellipse, texte, pense-bête, tampon dateur, gomme
- `Maj`+glisser : lignes à 45°, carrés, cercles
- L'outil de sélection déplace, la poignée d'angle redimensionne, le double-clic modifie le texte

## Propriétés
Sélectionnez une annotation, clic droit → `Propriétés…`
- Couleur du trait, épaisseur, style (continu, tirets, pointillé, tiret-point), pointes de flèche
- Couleur de fond et opacité (les formes peuvent avoir un fond sans trait)
- Police, taille, gras, italique, couleur du texte
- 🎨 : une palette de 126 couleurs, les couleurs récentes ou un code `#RRGGBB`

## Pages
Dans la liste des pages à gauche : glissez pour réorganiser, faites pivoter, supprimez, extrayez, insérez des fichiers

## Rechercher et afficher
`Ctrl+F` rechercher, `F3` suivant, `Ctrl+molette` zoom, `Ctrl+0` ajuster à la largeur
''',
  ),
  (
    'Copier une zone',
    '''
Découpez une partie d'une page et collez-la dans un autre document.

## Comment faire
- Choisissez `Copier une zone` (les ciseaux) dans la barre de la visionneuse
- Tracez un cadre autour de la partie à copier
- Ouvrez un autre document (ou une autre page) et appuyez sur `Ctrl+V`, ou clic droit → `Coller`
- L'image collée se déplace et se redimensionne comme toute annotation

## Bon à savoir
- Les annotations présentes dans le cadre font partie de l'image
- Le texte du cadre va aussi dans le presse-papiers de Windows, pour le Bloc-notes, Word, etc.
- À l'export ou à l'impression, l'image collée est conservée dans le PDF
''',
  ),
  (
    "L'impression et l'imprimante PDF Desk",
    '''
## L'imprimante PDF Desk
Imprimez depuis n'importe quel programme (Word, Excel, un navigateur…) et le document arrive sur le bureau, sans fenêtre d'enregistrement.
- Choisissez `Installer` dans le message du premier démarrage, ou `Fichier` → `Configurer l'imprimante « PDF Desk »…`
- Confirmez la demande d'administrateur (UAC) ; elle devient l'imprimante par défaut
- Aucun pilote n'est installé : elle utilise le « Microsoft Print to PDF » de Windows
- Si vous choisissez le « Microsoft Print to PDF » habituel, l'emplacement d'enregistrement est demandé et rien n'arrive sur le bureau

## Exporter et imprimer
- `Exporter PDF` : un PDF avec les annotations incrustées, identique dans toute visionneuse
- `Imprimer` (`Ctrl+P`) : imprime avec les annotations
''',
  ),
  (
    'Corbeille et annulation',
    '''
## Corbeille
- Les documents supprimés vont d'abord dans la corbeille (conservés 30 jours)
- `Annuler`, juste après la suppression, les fait revenir
- `Fichier` → `Corbeille…` pour `Restaurer`, `Supprimer définitivement` ou `Vider la corbeille`

## Annuler
- Empilement : `Annuler` en bas de la fenêtre
- Annotations dans la visionneuse : `Ctrl+Z` annuler, `Ctrl+Y` rétablir
- Les changements faits dans la fenêtre des propriétés s'annulent d'un seul `Ctrl+Z`
''',
  ),
  (
    'Thèmes et langues',
    '''
## Thèmes
Choisissez-en un avec 🎨 en haut à droite : iOS clair, iOS sombre, Classique (DocuWorks), Papier (sépia), Forêt, Minuit

## Langues
Choisissez-en une avec 🌐 en haut à droite : 한국어, 日本語, 中文, English, Español, Français

Les deux sont mémorisés pour la prochaine fois.
''',
  ),
  (
    'Raccourcis clavier',
    '''
## Bureau
- `Ctrl+N` nouveau document, `Ctrl+O` importer, `Ctrl+P` imprimer
- `Ctrl+A` tout sélectionner, `Ctrl+D` dupliquer, `F2` renommer, `Suppr` supprimer
- `Ctrl+F` rechercher des noms, `F5` actualiser, `F1` manuel
- `Ctrl`+molette zoom, `Ctrl`+glisser copier, `Maj`+déposer poser dessus sans empiler
- Aperçu : `←` `→` `PageUp` `PageDown`

## Visionneuse
- `Ctrl+Z` / `Ctrl+Y` annuler / rétablir
- `Ctrl+C` / `Ctrl+V` copier / coller des annotations et des zones
- `Ctrl+F` rechercher, `F3` / `Maj+F3` suivant / précédent
- `Ctrl+molette`, `Ctrl +`, `Ctrl -` zoom, `Ctrl+0` ajuster à la largeur
- `Échap` outil de sélection, `Suppr` supprimer les annotations sélectionnées
''',
  ),
  (
    'Dépannage',
    '''
## « Le fichier est utilisé et n'a pas pu être traité »
- Si le dossier du bureau est dans OneDrive, les fichiers sont verrouillés pendant leur synchronisation
- Quand `Déplacer le dossier du bureau` apparaît au démarrage, choisissez `Déplacer` (vers C:\\Users\\<nom>\\PdfDesk)
- Fermez le document s'il est ouvert dans une autre visionneuse PDF, puis réessayez

## L'impression n'arrive pas sur le bureau
- Vérifiez que l'imprimante choisie dans la fenêtre d'impression est `PDF Desk`
- PDF Desk doit être ouvert pour poser le document sur le bureau

## Ce PC n'affiche rien
- Vérifiez que vous ne l'avez pas replié avec la flèche à droite du titre `Ce PC`
- Cliquez sur un dossier pour voir son contenu. Un dossier sans PDF ni image indique « Aucun fichier PDF ou image »

## Une police s'affiche différemment
- La police doit être installée sur le PC pour être incluse dans le PDF ; sinon, Malgun Gothic est utilisée
''',
  ),
];
