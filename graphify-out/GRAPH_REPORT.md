# Graph Report - SCP-ROBLOX  (2026-11-19)

## Corpus Check
- 9 files · ~6,048 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 1 file(s) not represented in the graph (top: .obj 1)

## Summary
- 75 nodes · 88 edges · 10 communities (5 shown, 5 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `b26668cf`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- scene2.js
- SCP-ROBLOX — Document de concept
- V3
- SCP173AI.server.lua
- Contenu actuel : SCP-173 jouable
- render2.js
- SCP173Model.lua
- CLAUDE.md
- profile

## God Nodes (most connected - your core abstractions)
1. `V3()` - 7 edges
2. `SCP-ROBLOX — Document de concept` - 7 edges
3. `4. Catalogue de décors / salles` - 6 edges
4. `runAI()` - 5 edges
5. `blob()` - 5 edges
6. `getAliveRoot()` - 3 edges
7. `isObserved()` - 3 edges
8. `nearestTarget()` - 3 edges
9. `noise()` - 3 edges
10. `lumpy()` - 3 edges

## Surprising Connections (you probably didn't know these)
- None detected - all connections are within the same source files.

## Import Cycles
- None detected.

## Communities (10 total, 5 thin omitted)

### Community 0 - "scene2.js"
Cohesion: 0.10
Nodes (18): back, BASE, camA, camB, fill, floor, ft, groups (+10 more)

### Community 1 - "SCP-ROBLOX — Document de concept"
Cohesion: 0.15
Nodes (13): 1. Boucle de jeu, 2. Les joueurs : Classe D, 3. Bestiaire (premiers SCP proposés), 4. Catalogue de décors / salles, 5. ⚠️ Licence — important avant de publier, 6. Feuille de route proposée, Ce qui rend le jeu différent d'un simple "couloir + monstre", Petits détails qui donnent l'ambiance (à mettre partout) (+5 more)

### Community 2 - "V3"
Cohesion: 0.27
Nodes (10): addMesh(), blob(), grime(), limb(), lumpy(), noise(), rebar(), stroke() (+2 more)

### Community 3 - "SCP173AI.server.lua"
Cohesion: 0.46
Nodes (6): flat(), getAliveRoot(), isObserved(), nearestTarget(), playSound(), runAI()

### Community 4 - "Contenu actuel : SCP-173 jouable"
Cohesion: 0.29
Nodes (5): Contenu actuel : SCP-173 jouable, Crédits / licence, Modèle 3D v2 (recommandé), SCP-ROBLOX, Tester dans Studio

## Knowledge Gaps
- **5 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `SCP-ROBLOX — Document de concept` connect `SCP-ROBLOX — Document de concept` to `Contenu actuel : SCP-173 jouable`?**
  _High betweenness centrality (0.050) - this node is a cross-community bridge._
- **Should `scene2.js` be split into smaller, more focused modules?**
  _Cohesion score 0.09523809523809523 - nodes in this community are weakly interconnected._