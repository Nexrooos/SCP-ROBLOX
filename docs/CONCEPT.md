# SCP-ROBLOX — Document de concept

> Jeu d'horreur coopératif (1 à 4 joueurs) en salles générées aléatoirement,
> dans l'univers de la Fondation SCP. On incarne des **Classe D** qui doivent
> traverser un Site de confinement en pleine brèche, salle après salle.

---

## 1. Boucle de jeu

1. On démarre dans une **cellule de Classe D** (le "lobby" de la partie).
2. Une alarme de **brèche de confinement** retentit : les portes s'ouvrent.
3. Chaque porte franchie = une nouvelle salle, numérotée (`SALLE 001` → `SALLE 100`).
   Les salles sont tirées au hasard dans un catalogue (voir §4), donc chaque partie est différente.
4. Dans les salles : **cartes d'accès**, **objets**, **documents**, et bien sûr des **SCP**.
5. Tous les ~25 salles : une **zone-checkpoint** (changement de zone + sauvegarde de progression).
6. Fin : atteindre la **sortie de surface (Gate A / Gate B)**.

### Ce qui rend le jeu différent d'un simple "couloir + monstre"
- **Cartes d'accès niveau 1 → 5** : certaines portes exigent un niveau. Il faut fouiller les bureaux / cadavres de gardes.
- **Jauge de clignement** (pour SCP-173) : tes yeux se ferment automatiquement, tu peux aussi cligner manuellement au bon moment.
- **Archives** : chaque SCP rencontré débloque son **dossier** dans un journal (classe, procédures de confinement, point faible). C'est ta progression "lore".
- **Interphone de la Fondation** : une voix annonce des événements (« Brèche détectée en Zone Lourde », « Protocole de purge dans 60 secondes »).

---

## 2. Les joueurs : Classe D

- Combinaison orange + numéro aléatoire (`D-9341`, `D-1207`…) affiché au-dessus du joueur.
- Pas d'armes. On survit en **comprenant les règles** de chaque SCP.
- Mort = spectateur jusqu'au prochain checkpoint (ou réanimation avec **SCP-500**).

---

## 3. Bestiaire (premiers SCP proposés)

| SCP | Classe | Comportement en jeu | Comment survivre (point faible) |
|---|---|---|---|
| **SCP-173** "La Sculpture" | Euclide | Ne bouge **que si personne ne le regarde**. Se téléporte par à-coups, tue au contact (nuque brisée). | Toujours garder un joueur qui le regarde. Coordonner les clignements en coop. |
| **SCP-096** "L'Homme Timide" | Euclide | Calme et assis. Si on **voit son visage**, il hurle, puis poursuit le joueur à travers tout. | Ne jamais le regarder en face : baisser les yeux, longer les murs. |
| **SCP-106** "Le Vieil Homme" | Keter | Traverse les murs, laisse une **flaque noire corrosive**. Peut t'envoyer dans sa **Dimension de poche** (mini-salle piège). | Fuir vers la lumière, actionner le **"recontainment"** (femur breaker) dans une salle spéciale. |
| **SCP-049** "Le Docteur de la Peste" | Euclide | Patrouille lentement, parle. Te "soigne" (tue) au toucher, puis tu deviens un **SCP-049-2** (zombie). | Le semer en fermant des portes ; il ne peut pas courir. |
| **SCP-939** "Aux Multiples Voix" | Keter | Aveugle. **Imite la voix** des joueurs. Réagit au bruit. | Marcher accroupi, ne pas courir, ne pas parler (chat vocal = danger !). |
| **SCP-106 / 682 / 008** | Keter | Événements de fin de zone / boss (682 en Zone Lourde, salle de confinement de 008 = brouillard infectieux). | Chacun a son puzzle de survie. |
| **SCP-999** "Le Monstre Chatouilleur" | Sûr | **Allié** : soigne et rassure (réduit la peur / le stress). | — |
| **SCP-131** "Les Gouttes d'Œil" | Sûr | **Alliés** : te suivent et regardent SCP-173 à ta place quelques secondes. | — |
| **SCP-500** | Sûr | Objet : pilule qui soigne / réanime. Très rare. | — |
| **SCP-714** | Sûr | Objet : bague qui protège de 008 et 049, mais ralentit. | — |

> Idée de progression : les **SCP Sûrs** = aides, **Euclide** = monstres des salles normales,
> **Keter** = événements rares, boss de fin de zone.

---

## 4. Catalogue de décors / salles

L'idée : chaque salle est un "module" préfabriqué (un `Model` dans `ServerStorage/Rooms`)
avec une **porte d'entrée** et une **porte de sortie**. Le générateur les enchaîne.
Plus il y a de modules, moins le jeu est répétitif. Objectif : **~40 modules** pour la sortie.

### Zone de Confinement Légère (salles 1-25) — blanc, néons, propre mais abîmé
- **Couloir à cellules D** : rangée de cellules grillagées, lits renversés, numéros peints au pochoir.
- **Couloir de contrôle** : vitre blindée, guichet de garde, caméras qui pivotent (suivent le joueur).
- **Laboratoire de test** : chambre d'observation avec vitre, fiche de test sur le bureau, sang au sol.
- **Chambre de confinement de 173** : salle carrée, sol en béton taché, porte double qui ferme mal, **traces de raclement** au sol.
- **Toilettes** : miroirs brisés, un lavabo qui coule, lumière qui grésille (salle "piège" idéale).
- **Salle de stockage** : étagères, caisses "SCP-XXX — NE PAS OUVRIR", carte d'accès cachée.
- **Escalier de service** : descente vers la zone suivante, plateforme en métal grillagée.
- **Bureau des chercheurs** : ordinateurs (terminaux lisibles = lore), café renversé, tableau blanc.

### Zone de Confinement Lourde (salles 26-50) — sombre, métal, rouille, vapeur
- **Couloir de tuyaux** : vapeur qui jaillit (dégâts), éclairage rouge d'urgence.
- **Pont au-dessus du vide** : passerelle métallique, une partie s'effondre.
- **Chambre de 106** : grande salle avec le **broyeur de fémur** (cage, bouton rouge, micro).
- **Salle des générateurs** : il faut rallumer le courant (puzzle) pour ouvrir la suite.
- **Cellule de 096** : sas, bruits de pleurs derrière la porte.
- **Salle de décontamination** : lumières UV, douches, brouillard (salle de 008).
- **Tunnels de maintenance** : très étroits, on doit s'accroupir, 939 rôde.
- **Chambre de 682** : bac d'acide géant, grilles cassées (boss de fin de zone).

### Zone d'Entrée / Administration (salles 51-75) — moquette, bois, bureaux
- **Hall d'accueil** : logo de la Fondation au mur, portiques de sécurité, bureau d'accueil.
- **Salle de réunion O5** (fausse, mais clin d'œil) : table immense, 13 chaises, documents classés.
- **Cafétéria** : plateaux renversés, distributeur qui marche encore (soin léger).
- **Infirmerie** : lits médicaux, armoire à pharmacie (soins), SCP-500 sous clé.
- **Poste de sécurité** : écrans de caméras → permet de **voir les salles suivantes**.
- **Salle des archives** : rayonnages immenses, labyrinthe de dossiers papier.

### Surface (salles 76-100) — fin de partie
- **Gate A** : ascenseur vers la surface, hélicoptère, sortie "officielle".
- **Gate B** : tunnel, hangar, sortie "secrète" (fin alternative).
- **Protocole Alpha Warhead** : compte à rebours final, course jusqu'à la sortie.

### Petits détails qui donnent l'ambiance (à mettre partout)
- Panneaux au pochoir : `ZONE DE CONFINEMENT LÉGÈRE`, `PORTÉE CARTE NIVEAU 3 REQUISE`.
- Lumières qui clignotent / grésillent, alarme rouge tournante.
- Portes de confinement épaisses à double battant (ouverture coulissante lente).
- Haut-parleurs d'annonces au plafond.
- Traces de sang, cadavres de gardes (lootables), bureaux renversés.
- Caméras de surveillance qui tournent vers le joueur.

---

## 5. ⚠️ Licence — important avant de publier

- Le contenu SCP est sous licence **Creative Commons BY-SA 3.0**. Tu peux l'utiliser,
  **mais** tu dois créditer la source (scp-wiki.wikidot.com + auteurs des articles) dans le jeu
  (ex. un écran "Crédits" ou la description du jeu).
- **L'image originale de SCP-173** (la sculpture "Untitled 2004" d'Izumi Kato) **n'est PAS libre**.
  Il ne faut **pas** copier cette sculpture. Le modèle fourni dans `src/` est un **design original**
  (statue en béton avec armature et peinture) — c'est volontaire.
- Inspiration "salles + monstres" : OK. Mais garde tes propres noms, interface et monstres
  (ici les SCP) plutôt que de reprendre ceux d'un autre jeu Roblox.

---

## 6. Feuille de route proposée

1. ✅ Concept + SCP-173 (modèle + IA "ne bouge pas si on le regarde" + jauge de clignement)
2. ⬜ Générateur de salles (enchaîner des modules avec porte d'entrée / sortie)
3. ⬜ 5 premiers modules de salles (Zone Légère)
4. ⬜ Cartes d'accès + portes verrouillées
5. ⬜ Journal des dossiers SCP (lore débloquable)
6. ⬜ SCP-096, puis SCP-106
7. ⬜ Lobby + matchmaking (ascenseur de groupe)

L'histoire reste à écrire de ton côté — les dossiers (§1) sont l'endroit idéal pour la raconter.
