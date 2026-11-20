# SCP-ROBLOX

> **FONDATION SCP · SITE-19 · SECTION TECHNIQUE**
> Dossier DEV-019 · Révision 4 · Accréditation requise : niveau 2
> Destinataires : personnel chargé de l'intégration dans Roblox Studio

## Objet du dossier

Jeu d'horreur coopératif sur Roblox, de 1 à 4 joueurs. Les joueurs sont des sujets de classe D qui traversent un site de la Fondation après une brèche de confinement. Les salles s'enchaînent par génération aléatoire, et chacune expose le groupe à une anomalie différente.

Le document de conception (registre des anomalies, catalogue des salles, feuille de route) est archivé sous [`docs/CONCEPT.md`](docs/CONCEPT.md). Le texte de la page du jeu se trouve dans [`docs/DESCRIPTION-ROBLOX.md`](docs/DESCRIPTION-ROBLOX.md).

Le présent dossier suit l'ordre d'arrivée d'un joueur : hall de transit, bloc cellulaire D, puis première anomalie (SCP-173).

---

## Section 1 · Hall de transit (serveur public)

### 1.1 Description

Structure `Workspace.Hub`, construite directement dans la place Studio. Tous les joueurs connectés au serveur public y apparaissent et se voient. Le hall comprend la zone d'arrivée, l'enseigne de la Fondation, le panneau des consignes, un poste de garde vitré et une rangée de casiers.

Six sas de transfert occupent le mur nord : `Hub.Sas.Sas_01` à `Sas_06`, tag `HubSas`.

### 1.2 Scripts

| Fichier | Type dans Roblox Studio | Emplacement |
|---|---|---|
| `src/ServerScriptService/HubServer.server.lua` | **Script** | `ServerScriptService` |
| `src/StarterPlayerScripts/HubHUD.client.lua` | **LocalScript** | `StarterPlayer > StarterPlayerScripts` |

### 1.3 Protocole de transfert 7-A

L'état de chaque sas est signalé par le voyant placé au-dessus de la porte.

1. **Voyant vert.** Sas disponible. Le premier sujet qui entre devient responsable du groupe (l'hôte). Il dispose de 25 s pour fixer l'effectif : SOLO, 2, 3 ou 4 sujets. Passé ce délai, il est reconduit dans le hall et le sas est libéré.
2. **Voyant orange.** Embarquement. La porte reste ouverte tant que l'effectif n'est pas atteint. Départ au bout de 30 s, ou 5 s après le remplissage complet. L'hôte peut avancer le départ avec la commande « Lancer maintenant ».
3. **Voyant rouge.** Porte verrouillée. Le cycle de décontamination se déclenche (brume, puis fondu au noir) et le groupe est transféré.

En mode SOLO, le cycle démarre dès que l'effectif est fixé.
Un sujet peut quitter le sas à pied ou par la commande « Quitter le sas », sauf pendant la décontamination. Si l'hôte sort, la responsabilité passe au sujet arrivé ensuite.

### 1.4 Répartition des serveurs

Chaque partie s'exécute sur un serveur réservé de la même place (`TeleportOptions.ShouldReserveServer`). L'effectif est transmis dans les données de téléportation (`partySize`).

Au démarrage, `HubServer` fixe l'attribut `workspace.ServerMode` :

| Valeur | Type de serveur | Effet |
|---|---|---|
| `"Hub"` | public | le bloc D est rangé dans ServerStorage |
| `"Match"` | réservé | le hall est supprimé |

`DClassLobby`, `SCP173AI`, `BlinkAndWatch` et `DClassHUD` restent inactifs tant que la valeur n'est pas `"Match"`. Le bloc D attend uniquement l'effectif annoncé (`PartySize`).

### 1.5 Essais dans Studio

Studio ne permet pas la téléportation. Au départ d'un sas, le serveur d'essai passe donc lui-même en `"Match"`.
Pour accéder directement au bloc D, placer l'attribut `StudioStart = "Match"` sur le script `HubServer`.

Le hall et les parties partagent la même place. Régler *Paramètres du jeu > Places > Nombre max. de joueurs* selon la capacité voulue pour le hall (20, par exemple). Les sas limitent de toute façon chaque partie à 4 sujets.

Sons à renseigner dans `CONFIG` : `DOOR_SOUND_ID`, `DEPART_SOUND_ID`.

### 1.6 Décor du hall

Dossier `Workspace.Hub.Decor`, construit dans la place Studio (pas de script de génération) :

| Élément | Emplacement | Contenu |
|---|---|---|
| `CelluleIsolement` | mur ouest | cellule capitonnée à barreaux de D-0451, gribouillis au marqueur, néon qui grésille, repère `FouSpot` du PNJ |
| `Vitrine173` | mur est | réplique de SCP-173 sous verre, plaque « EUCLIDE », cordon de sécurité, traces de raclement au sol |
| `Affiches` | murs est, ouest et sud | classes Sûr / Euclide / Keter, « Sécuriser · Contenir · Protéger », avertissement SCP-096, compteur « jours sans incident : 00 » |
| `Cameras` | coins du plafond | caméras de surveillance, voyant rouge clignotant (attribut `Blink`) |
| `Menage` | côté nord-ouest | panneau « sol glissant », flaque, chariot de ménage |

### 1.7 D-0451 « Le Fou » et dossier des anomalies

Un Classe D enfermé dans la cellule d'isolement. On lui parle à travers les barreaux (touche E). Il ne parle que des anomalies que le joueur a déjà rencontrées, et donne un conseil par conversation.

- **Dossier.** `SCPCodex` enregistre, pour chaque joueur, les anomalies vues et le nombre de morts contre chacune (DataStore `SCPCodex_v1`, car le hall et les parties sont sur des serveurs différents). SCP-173 entre au dossier dès que le joueur le regarde, et chaque mort est comptée. À la première rencontre, une notification « DOSSIER » renvoie vers D-0451.
- **Répliques.** `SCPTips` contient les répliques : salut, salut selon le nombre de morts, conseils dans l'ordre puis en boucle, et réponses quand le joueur n'a encore rien vu. Les conseils de SCP-096, 106, 049 et 939 sont déjà écrits pour la suite.
- **Ajouter une anomalie.** Une entrée dans `SCPTips.ENTRIES`, plus un appel à `SCPCodex.markSeen(player, "SCP-XXX", { died = true })` dans son script.

| Fichier | Type dans Roblox Studio | Emplacement |
|---|---|---|
| `src/ServerScriptService/SCPCodex.lua` | **ModuleScript** | `ServerScriptService` |
| `src/ServerScriptService/CrazyDClass.server.lua` | **Script** | `ServerScriptService` |
| `src/ReplicatedStorage/SCPTips.lua` | **ModuleScript** | `ReplicatedStorage` |
| `src/StarterPlayerScripts/CrazyDClassDialog.client.lua` | **LocalScript** | `StarterPlayer > StarterPlayerScripts` |

Dans Studio, le dossier n'est sauvegardé que si *Paramètres du jeu > Sécurité > Autoriser l'accès de Studio aux services API* est activé. Sinon, il reste en mémoire le temps de l'essai.

---

## Section 2 · Bloc cellulaire D (début de partie)

### 2.1 Description

Structure `Workspace.DClassBlock`, construite dans la place Studio. Bloc sur deux niveaux relié par une passerelle : 24 cellules, poste de garde surélevé avec armurerie, cantine, douches, salle de briefing, sas de décontamination et porte SALLE 001.

### 2.2 Scripts

| Fichier | Type dans Roblox Studio | Emplacement |
|---|---|---|
| `src/ServerScriptService/DClassLobby.server.lua` | **Script** | `ServerScriptService` |
| `src/StarterPlayerScripts/DClassHUD.client.lua` | **LocalScript** | `StarterPlayer > StarterPlayerScripts` |

### 2.3 Séquence d'ouverture

1. Chaque sujet reçoit une cellule, un matricule `D-XXXX` et la combinaison orange.
2. Attente des sujets manquants : 25 s au maximum (8 s dans Studio).
3. Appel nominatif au haut-parleur.
4. Brèche de confinement. L'éclairage clignote puis baisse, l'alarme se déclenche et les écrans du poste de garde perdent le signal.
5. Déverrouillage des cellules, puis des portes du briefing et du sas.
6. Les sujets doivent se regrouper dans le sas de décontamination. L'ouverture de la SALLE 001 est conditionnée à la présence de tous les sujets vivants. Au-delà de 90 s, elle est forcée.
7. Déclenchement de `ServerStorage.LobbyFinished`. Le générateur de salles, à venir, se raccordera à `Airlock.Room001Anchor`.

Sons à renseigner dans `CONFIG` : `PA_SOUND_ID`, `ALARM_SOUND_ID`, `DOOR_SOUND_ID`.

### 2.4 Audit visuel du bloc (`tools/lobby-audit/LobbyAudit.lua`)

Copier le fichier dans un ModuleScript `ServerStorage.LobbyAudit`. Dans la barre de commande de Studio, en mode Édition :

```lua
print(require(game.ServerStorage.LobbyAudit:Clone()).report())  -- liste les problèmes
print(require(game.ServerStorage.LobbyAudit:Clone()).fix())     -- corrige, puis liste ce qui reste
```

Le rapport relève trois défauts : faces coplanaires superposées (z-fighting), pièces cachées dans une autre, pièces qui flottent.

`fix()` applique les règles du bloc :
- décor fin décollé de 0,05 stud de son support, sans ombre ;
- en cas de faces confondues, la plus petite est rentrée de 0,04 stud ;
- pièces cachées supprimées, îlots flottants recollés ;
- textes en `PixelsPerStud` 50 avec `TextScaled`.

Les portes coulissantes sont exclues du traitement. Relancer l'audit après chaque modification du décor.

---

## Section 3 · SCP-173

> **Objet n° :** SCP-173
> **Classe :** Euclide
> **Statut dans le projet :** opérationnel

### 3.1 Comportement en jeu

SCP-173 reste immobile tant qu'au moins un sujet vivant l'a dans son champ de vision, sans obstacle entre eux. Dès que le contact visuel est rompu, par un regard détourné ou un clignement, il se dirige vers le sujet le plus proche (35 studs/s environ, contournement des murs par pathfinding) et le tue au contact.

Les yeux de chaque sujet se ferment automatiquement toutes les 9 s. La touche **B** permet de cligner volontairement, ce qui sert à décaler les clignements en groupe.

### 3.2 Scripts

| Fichier | Type dans Roblox Studio | Emplacement |
|---|---|---|
| `src/ServerStorage/SCP173Model.lua` | **ModuleScript** nommé `SCP173Model` | `ServerStorage` |
| `src/ServerScriptService/SCP173AI.server.lua` | **Script** | `ServerScriptService` |
| `src/StarterPlayerScripts/BlinkAndWatch.client.lua` | **LocalScript** | `StarterPlayer > StarterPlayerScripts` |

### 3.3 Modèles 3D

**Version 2 (recommandée)**

![Aperçu SCP-173 v2](docs/scp173-v2-apercu.png)

1. Dans Studio : **Accueil > Importer 3D**, fichier `assets/SCP173.obj`.
2. Renommer le Model importé en **`SCP173Mesh`** et le placer dans **ServerStorage**.
3. Le script applique automatiquement couleurs, matériaux et taille (environ 10 studs). Sans ce modèle, l'ancienne version en blocs (v1) est utilisée.

Le mesh est généré par code (`tools/scp173-mesh/`, three.js). Il compte 5 pièces : corps, peinture noire, rouge et verte, armature. Chacune fait moins de 10 000 triangles.

**Version 3 : aspect classique, texturée (`assets/SCP173.fbx`)**

Mesh unique `SCP173_Statue` : 3 996 triangles, 2,4 m, visage orienté vers −Y/−Z. Tête ovale sans cou, bande rouge, yeux noirs cerclés de vert, bras courts, jambes fines.
Textures 2K dans `assets/textures/scp173/` : béton crème sale et abîmé avec éclats de peinture rouge et verte (`baseColor`), plus une carte `roughness`.
Installation identique : **Importer 3D** → `assets/SCP173.fbx`, renommer en **`SCP173Mesh`**, ranger dans **ServerStorage**. Le nom `SCP173_Statue` ne contient aucun mot-clé de `MESH_LOOK`, la texture est donc conservée.

**Variante** : `assets/SCP173_Unity.fbx` (textures dans `textures/scp173_unity/`). Version inspirée de « SCP Unity » : béton, armature et peinture aérosol Krylon. Deux meshes, `SCP173_Statue` et `SCP173_Rebar`.

### 3.4 Essai

1. Créer les 3 scripts ci-dessus et y coller le contenu des fichiers.
2. Facultatif : ajouter une Part nommée `SCP173Spawn` dans le Workspace pour fixer le point d'apparition.
3. Lancer **Play**. SCP-173 reste figé tant que le joueur le regarde. Tourner la caméra ou cligner (jauge en bas de l'écran, touche **B**) suffit à le libérer.

Sons à renseigner en tête de `SCP173AI`, dans `CONFIG` : `SCRAPE_SOUND_ID`, `SNAP_SOUND_ID`.

---

## Section 4 · Interface : cases « terminal »

Toutes les indications et notifications passent par un module commun.

| Fichier | Type dans Roblox Studio | Emplacement |
|---|---|---|
| `src/ReplicatedStorage/SCPTerminal.lua` | **ModuleScript** nommé `SCPTerminal` | `ReplicatedStorage` |

Chaque case reproduit un document de terminal du site, de haut en bas :
1. bandeau plein avec le logo de la Fondation à gauche, le titre et la référence à droite. Jaune-orange `#E8A33D` et texte noir pour `"info"`, rouge `#B3261E` et texte blanc pour `"alerte"` ;
2. bande de rayures de danger jaunes et noires ;
3. corps `#0E1014` avec un dégradé vertical et des lignes de balayage CRT, barre d'accent de 4 px à gauche ;
4. ligne de métadonnées en petite police grise, avec l'heure locale qui défile (`NIV. ACCRÉD. 1 · CLASSE D · 14:02:31`).

La case porte une bordure de 1 px de la couleur d'accent (transparence 0,5) et une ombre portée douce.

Séquence d'ouverture : dépliage du bandeau de gauche à droite, ouverture du corps vers le bas, puis frappe du texte avec un curseur clignotant. Pour une alerte, le bandeau clignote trois fois, la case tremble et l'image se coupe un court instant avant l'ouverture du corps. Fermeture en fondu.

### 4.1 Disposition à l'écran

| Zone | Hall de transit | Bloc D |
|---|---|---|
| Colonne gauche (fixe) | case du lieu, remplacée par le panneau du sas quand le joueur est dans un sas | matricule |
| Haut centre | — | état du bloc, masqué pendant les annonces du haut-parleur |
| Bas centre | indication de transit | haut-parleur / alerte système |
| Colonne droite | notifications (`Terminal.notify`) : 2 au maximum, espacées de 8 px, fondu après 4 s | idem |

Les ScreenGui sont créés par `Terminal.screenGui(nom, ordre)` : `IgnoreGuiInset = false` et `ScreenInsets = CoreUISafeInsets`, pour rester sous la barre du haut et à l'écart des boutons Roblox. Seuls les fonds plein écran (fondu de départ, vignette d'alarme) utilisent `Terminal.screenGui(nom, ordre, true)`.
Les largeurs sont en Scale, bornées par un `UISizeConstraint`. Les polices sont réduites jusqu'à 80 % quand l'écran fait moins de 820 px de haut. Le panneau du sas est mis à l'échelle (`UIScale`) pour tenir dans la colonne.
Remarque : `UITextSizeConstraint` n'agit que sur les textes en `TextScaled`. Ce mode est incompatible avec la hauteur automatique et l'effet machine à écrire, d'où la réduction de police par facteur d'écran.

### 4.2 Logo de la Fondation

Asset image `121817411121794`. Tant que Roblox ne sert pas encore l'image directe (modération), le jeu utilise sa vignette : `rbxthumb://type=Asset&id=121817411121794&w=420&h=420` (`Terminal.LOGO_IMAGE`).
Emplacements dans la place : bandeau de chaque case terminal, enseigne du hall (sur disque clair), sol du hall, poste de garde du hall (sur disque clair), mur haut de la cabine du poste de garde du bloc D, battant de la porte de sortie du bloc (`HallDoor`). Les logos du décor sont des SurfaceGui sur des plaques invisibles décollées de 0,05 stud de leur support.

```lua
local Terminal = require(ReplicatedStorage.SCPTerminal)
local box = Terminal.new({ kind = "info", header = "TERMINAL SITE-19 · TRANSIT", ref = "REF-0019", parent = screenGui })
box:show("Présentez-vous à un sas de transit pour être affecté à une équipe.")
box:setText("…")   -- mise à jour sans effet machine à écrire (comptes à rebours)
box:hide()
Terminal.notify("alerte", "Sas complet. Affectation refusée.", { hold = 4 })  -- avis temporaire, en haut au centre
Terminal.decorate(frame, "info")  -- applique bordure et équerres à un panneau existant
```

`HubHUD` et `DClassHUD` en dépendent : le module doit être présent dans ReplicatedStorage avant le lancement.
Toute nouvelle notification du jeu doit utiliser ce module, pour garder une présentation uniforme.

---

## Annexe A · Licences et crédits

Contenu basé sur la [Fondation SCP](https://scp-wiki.wikidot.com), sous licence CC BY-SA 3.0.

La sculpture d'origine de SCP-173, œuvre d'Izumi Kato, n'est **pas** sous licence libre. Les modèles du projet reprennent la silhouette connue (tête allongée, petits bras, peinture) avec leurs propres détails, sans copie exacte.

`assets/SCP173.fbx` et `assets/textures/scp173/` : « [SCP-173](https://sketchfab.com/models/e4ef798fb0284b31bf90bad0d3bc7fc8) » par **ThatJamGuy**, sous licence [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Modifications : orientation, texture agrandie en 2K et vieillie (saleté, éclats de béton et de peinture), ajout d'une carte roughness.

`assets/SCP173_Unity.fbx` et `assets/textures/scp173_unity/` : « [SCP UNITY | SCP-173](https://sketchfab.com/models/f8e38ace9d28481e8201f773f7f76c26) » par **ThatJamGuy**, sous licence [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Modifications : rig retiré, pose figée, sommets parasites supprimés, bras séparés en mesh d'armature. La texture a été refaite en béton avec traces de peinture aérosol ; seule la peinture d'origine du visage est conservée. Les cartes roughness et metalness ont été refaites.

Ce crédit doit aussi figurer dans la description du jeu sur Roblox (voir [`docs/DESCRIPTION-ROBLOX.md`](docs/DESCRIPTION-ROBLOX.md)).
