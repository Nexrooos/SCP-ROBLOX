# SCP-ROBLOX · Document de conception

> **FONDATION SCP · SITE-19 · SECTION TECHNIQUE**
> Document DEV-019-C · Conception générale · Accréditation requise : niveau 2
> Rédaction : Dr ██████, service des simulations

## 0. Résumé

Jeu d'horreur coopératif pour 1 à 4 joueurs, situé dans l'univers de la Fondation SCP. Les joueurs incarnent des sujets de classe D au moment d'une brèche de confinement. Leur objectif est de traverser le site jusqu'à la surface. Les salles sont générées aléatoirement à chaque partie.

---

## 1. Déroulement d'une opération

1. Rassemblement dans le hall de transit, puis transfert du groupe par un sas (README, section 1).
2. Le groupe démarre dans le bloc cellulaire D, qui sert d'introduction.
3. Une alarme de brèche retentit et les portes se déverrouillent.
4. Chaque porte franchie mène à une nouvelle salle numérotée, de `SALLE 001` à `SALLE 100`. Les salles sont tirées au hasard dans le catalogue (section 4), si bien que deux parties ne se ressemblent pas.
5. On trouve dans les salles des cartes d'accès, des objets, des documents et des SCP.
6. Toutes les 25 salles environ : point de contrôle, avec changement de zone et sauvegarde de la progression.
7. Fin de l'opération : atteindre une sortie de surface, Gate A ou Gate B.

### 1.1 Mécaniques propres au projet

Ces quatre systèmes distinguent le projet d'un simple enchaînement de couloirs avec un monstre.

- **Cartes d'accès, niveaux 1 à 5.** Certaines portes exigent un niveau d'accréditation minimal. Les cartes se trouvent en fouillant les bureaux et les corps des gardes.
- **Jauge de clignement**, pour SCP-173. Les yeux du sujet se ferment automatiquement à intervalle régulier. Le joueur peut aussi cligner volontairement pour choisir le moment.
- **Archives.** Chaque SCP rencontré débloque son dossier dans un journal : classe, procédures de confinement, point faible. Les archives portent l'essentiel du lore.
- **Interphone du site.** Une voix annonce les événements en cours. Exemples : « Brèche détectée en Zone de Confinement Lourde », « Protocole de purge dans 60 secondes ».

---

## 2. Personnel joueur : classe D

- Combinaison orange et matricule aléatoire (`D-9341`, `D-1207`…), imprimé sur la combinaison et rappelé dans l'interface.
- Aucun armement. La survie dépend de la compréhension des règles propres à chaque SCP.
- En cas de décès, le joueur passe en spectateur jusqu'au prochain point de contrôle. SCP-500 permet une réanimation.

---

## 3. Registre des anomalies

| Objet | Classe | Comportement en jeu | Procédure de survie |
|---|---|---|---|
| **SCP-173** « La Sculpture » | Euclide | Immobile tant qu'il est observé. Se déplace par à-coups dès que le contact visuel est rompu. Tue au contact par fracture des cervicales. | Garder en permanence au moins un observateur. En groupe, décaler les clignements. |
| **SCP-096** « L'Homme Timide » | Euclide | Reste assis et calme. Le sujet qui voit son visage déclenche une crise : SCP-096 hurle, puis le poursuit sans tenir compte des obstacles. | Ne jamais regarder son visage. Garder les yeux baissés, longer les murs. |
| **SCP-106** « Le Vieil Homme » | Keter | Traverse les murs et laisse un résidu noir corrosif. Peut entraîner un sujet dans sa dimension de poche, une petite salle piège. | Fuir vers les zones éclairées. Lancer la procédure de reconfinement (broyeur de fémur) dans la salle prévue à cet effet. |
| **SCP-049** « Le Docteur de la Peste » | Euclide | Patrouille lentement et parle. Un contact suffit : le sujet est « soigné », meurt et devient SCP-049-2. | Fermer les portes derrière soi. SCP-049 ne court pas. |
| **SCP-939** « Aux Multiples Voix » | Keter | Aveugle. Imite la voix des joueurs et réagit au bruit. | Se déplacer accroupi, ne pas courir, ne pas parler. Le chat vocal attire SCP-939. |
| **SCP-106, 682, 008** | Keter | Événements de fin de zone et boss. SCP-682 en Zone Lourde. La salle de confinement de SCP-008 est remplie d'un brouillard infectieux. | Une épreuve de survie distincte pour chacun. |
| **SCP-999** « Le Monstre Chatouilleur » | Sûr | Allié. Soigne le sujet et fait baisser son niveau de stress. | Sans objet. |
| **SCP-131** « Les Gouttes d'Œil » | Sûr | Alliés. Suivent le sujet et surveillent SCP-173 à sa place pendant quelques secondes. | Sans objet. |
| **SCP-500** | Sûr | Objet. Pilule qui soigne ou réanime. Très rare. | Sans objet. |
| **SCP-714** | Sûr | Objet. Bague qui protège de SCP-008 et SCP-049, au prix d'une vitesse réduite. | Sans objet. |

**Répartition par classe.** Les objets Sûrs servent d'aides. Les Euclide peuplent les salles ordinaires. Les Keter sont réservés aux événements rares et aux boss de fin de zone.

---

## 4. Catalogue des salles

Chaque salle est un module préfabriqué : un `Model` rangé dans `ServerStorage/Rooms`, avec une porte d'entrée et une porte de sortie. Le générateur raccorde les modules bout à bout. Plus le catalogue est fourni, moins la répétition se voit. Objectif pour la sortie publique : environ 40 modules.

### 4.1 Zone de Confinement Légère · salles 001 à 025

Aspect général : murs blancs, néons, installations propres mais endommagées.

- **Couloir des cellules D.** Rangée de cellules grillagées, lits renversés, numéros peints au pochoir.
- **Couloir de contrôle.** Vitre blindée, guichet de garde, caméras qui pivotent pour suivre le joueur.
- **Laboratoire d'essais.** Chambre d'observation vitrée, fiche d'essai sur le bureau, sang au sol.
- **Chambre de confinement de SCP-173.** Salle carrée au sol de béton taché. La double porte ferme mal. Traces de raclement au sol.
- **Sanitaires.** Miroirs brisés, lavabo qui fuit, éclairage qui grésille. Bon emplacement pour une salle piège.
- **Réserve.** Étagères, caisses marquées « SCP-███ · NE PAS OUVRIR », carte d'accès dissimulée.
- **Escalier de service.** Plateforme en caillebotis métallique. Mène à la zone suivante.
- **Bureau des chercheurs.** Ordinateurs avec terminaux lisibles (lore), café renversé, tableau blanc.

### 4.2 Zone de Confinement Lourde · salles 026 à 050

Aspect général : obscurité, métal, rouille, vapeur.

- **Couloir de tuyauterie.** Jets de vapeur qui infligent des dégâts. Éclairage de secours rouge.
- **Passerelle au-dessus du vide.** Passerelle métallique dont une section s'effondre.
- **Chambre de SCP-106.** Grande salle équipée du broyeur de fémur : cage, bouton rouge, micro.
- **Salle des générateurs.** Le courant doit être rétabli (énigme) pour ouvrir la suite.
- **Cellule de SCP-096.** Sas d'accès. Des pleurs sont audibles derrière la porte.
- **Salle de décontamination.** Lampes UV, douches, brouillard. Héberge SCP-008.
- **Tunnels de maintenance.** Passages très étroits qui imposent de s'accroupir. Zone de patrouille de SCP-939.
- **Chambre de SCP-682.** Bassin d'acide, grilles arrachées. Boss de fin de zone.

### 4.3 Zone d'Entrée et administration · salles 051 à 075

Aspect général : moquette, boiseries, bureaux.

- **Hall d'accueil.** Logo de la Fondation au mur, portiques de sécurité, banque d'accueil.
- **Salle de réunion du Conseil O5.** Fictive dans le jeu, à titre de clin d'œil. Table immense, 13 chaises, documents classifiés.
- **Cafétéria.** Plateaux renversés. Un distributeur encore en service rend un peu de santé.
- **Infirmerie.** Lits médicaux, armoire à pharmacie (soins), SCP-500 sous clé.
- **Poste de sécurité.** Les écrans des caméras montrent les salles suivantes.
- **Salle des archives.** Rayonnages très hauts disposés en labyrinthe.

### 4.4 Surface · salles 076 à 100 (fin de partie)

- **Gate A.** Ascenseur vers la surface, hélicoptère. Sortie officielle.
- **Gate B.** Tunnel puis hangar. Sortie non répertoriée, qui donne une fin alternative.
- **Protocole Alpha Warhead.** Compte à rebours final jusqu'à la détonation. Le groupe doit atteindre une sortie avant la fin.

### 4.5 Signalétique et détails communs à toutes les zones

- Panneaux au pochoir : `ZONE DE CONFINEMENT LÉGÈRE`, `CARTE NIVEAU 3 REQUISE`.
- Éclairage défaillant qui clignote ou grésille. Gyrophare rouge en cas d'alerte.
- Portes de confinement épaisses à double battant, à ouverture coulissante lente.
- Haut-parleurs d'annonce au plafond.
- Traces de sang, corps de gardes à fouiller, bureaux renversés.
- Caméras de surveillance qui s'orientent vers le joueur.

---

## 5. Note du service juridique (à lire avant publication)

- Le contenu SCP est publié sous licence **Creative Commons BY-SA 3.0**. Son utilisation est autorisée à condition de créditer la source, scp-wiki.wikidot.com et les auteurs des articles, dans le jeu ou dans sa description. Un écran « Crédits » convient.
- L'image originale de SCP-173, la sculpture *Untitled 2004* d'Izumi Kato, **n'est pas libre de droits**. Elle ne doit pas être reproduite. Les modèles du projet sont soit des créations originales (`src/`, `tools/scp173-mesh/`), soit des modèles Sketchfab sous CC BY 4.0 crédités dans le README (annexe A).
- Le principe « salles successives et monstres » est libre d'usage. Les noms, l'interface et les créatures doivent en revanche rester propres au projet ; ne rien reprendre d'un autre jeu Roblox.

---

## 6. Feuille de route

| N° | Tâche | État |
|---|---|---|
| 1 | Concept et SCP-173 : modèle, IA « immobile sous observation », jauge de clignement | Terminé |
| 2 | Bloc cellulaire D : séquence d'ouverture et brèche | Terminé |
| 3 | Hall de transit et sas de matchmaking (remplace l'ascenseur de groupe prévu au départ) | Terminé |
| 4 | Générateur de salles : enchaînement des modules par portes d'entrée et de sortie | En attente |
| 5 | 5 premiers modules de la Zone Légère | En attente |
| 6 | Cartes d'accès et portes verrouillées | En attente |
| 7 | Journal des dossiers SCP (lore à débloquer) | En attente |
| 8 | SCP-096, puis SCP-106 | En attente |

Le scénario reste à écrire. Les dossiers des archives (section 1.1) sont le support prévu pour le raconter.
