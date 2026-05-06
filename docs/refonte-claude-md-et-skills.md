# Refonte de CLAUDE.md et des skills — passage aux contraintes comportementales

Date : 2026-05-04

## Pourquoi cette refonte

Constat opérationnel : malgré un CLAUDE.md global dense et plusieurs skills,
Claude continue à enfreindre des consignes pourtant écrites noir sur blanc
(numérotation par lettres latines, dissémination des questions dans la prose,
ajout de code hors périmètre demandé, etc.). Ajouter des consignes
supplémentaires ne corrige pas le problème : ça l'aggrave.

Diagnostic emprunté à l'article *The 4 Lines Every CLAUDE.md Needs* (Yanli
Liu, avril 2026, Level Up Coding) :

> **Configuration Paradox** : plus on ajoute de règles, moins l'agent les
> respecte. Au-delà d'un seuil, ajouter des règles produit un agent confus,
> pas un agent discipliné. Les contraintes **comportementales** (comment
> penser) battent les listes de **features** (quoi faire).

Critère de coupe imposé par l'article (et par la doc Anthropic) :

> *Would removing this cause Claude to make a mistake it couldn't recover
> from? If no, leave it out.*

Limites techniques rappelées par Claude Code : 6 000 caractères max par
fichier de règles, 12 000 caractères combinés. Si on dépasse, c'est un
signal qu'on disperse au lieu de prioriser.

## Les 5 lignes comportementales

Quatre viennent de Karpathy (via l'article). La cinquième vient d'une
discussion locale (épisode du 2026-05-04 : Claude pose des questions
disséminées dans la prose, le récap final n'en reprend que certaines, et
l'utilisateur perd la moitié du temps gagné à reconstruire l'état des
arbitrages ouverts).

```markdown
1. Don't assume. Don't hide confusion. Surface tradeoffs.
2. Minimum code that solves the problem. Nothing speculative.
3. Touch only what you must. Clean up only your own mess.
4. Define success criteria. Loop until verified.
5. Le récap doit suffire. L'utilisateur doit pouvoir sauter toute la prose
   et ne lire que la fin pour savoir quoi faire. Si une question,
   alternative ou décision n'apparaît pas dans le récap, elle n'existe pas.
```

### Pourquoi chacune

**1. Don't assume / Don't hide confusion / Surface tradeoffs.** Force le
réflexe : avant d'écrire du code, lever les ambiguïtés. Si une décision
implicite doit être prise, elle est posée comme question, pas tranchée
silencieusement. Couvre les cas où l'agent assume un format, un périmètre,
un mode d'exécution sans demander.

**2. Minimum code / Nothing speculative.** Force la simplicité temporelle :
résoudre le problème d'aujourd'hui simplement, pas le problème de demain
prématurément. Test mental : « un ingénieur senior dirait-il que c'est
sur-architecturé ? » Si oui, simplifier.

**3. Touch only what you must / Clean up only your own mess.** Protège la
revue. Chaque ligne du diff doit se justifier par la demande. Si tes
propres changements créent des orphelins (imports inutilisés, variables
mortes), tu les nettoies. Le code mort préexistant, tu n'y touches pas
sauf demande.

**4. Define success criteria / Loop until verified.** Les trois premières
sont des garde-fous (elles empêchent un mauvais comportement). Celle-ci
est un **levier** : elle débloque la capacité de l'agent à itérer
seul jusqu'à atteindre un critère vérifiable. Concrètement : structurer
les tâches comme « écris d'abord un test qui reproduit le bug → vérifie
qu'il échoue → implémente → vérifie que le test passe → cas limites →
régression complète » plutôt que « répare le système d'authentification ».

**5. Le récap doit suffire.** Règle d'intention falsifiable : avant
d'envoyer, relire seulement le récap, et se demander « est-ce que c'est
suffisant pour répondre ? ». Si non, récrire. Cette règle rend
mécaniquement impossibles les comportements suivants :
- question disséminée dans la prose (le récap ne suffit plus),
- alternative A/B en cours d'analyse sans trancher (idem),
- décision prise implicitement plus haut sans la rappeler dans le récap.

## Plan de refonte du CLAUDE.md global

Cible : `~/claude-config/config/CLAUDE.md`.

**Étape 1 — Couper.**

Ouvrir le fichier et appliquer le critère de coupe à **chaque** consigne :
« Est-ce que retirer cette ligne ferait commettre à l'agent une erreur
irrécupérable ? » Si non, retirer.

Cibles évidentes à retirer :
- consignes que l'agent peut déduire en lisant le code (architecture,
  conventions de nommage, structure de dossiers),
- duplications sémantiques entre sections (« Posture intellectuelle » et
  « Anti-complaisance — questions fermées » se recouvrent partiellement),
- procédures détaillées qui décrivent des étapes que l'agent fait déjà
  par défaut,
- mises en forme rappelées plusieurs fois (numérotation, accents, langue
  française) — une mention suffit si elle est claire.

**Étape 2 — Garder le squelette comportemental.**

Conserver la section qui pose les 5 lignes (avec leur intention en une
phrase chacune). Pas de sous-bullets de procédure : la ligne est
l'instruction, pas un titre suivi d'explications.

**Étape 3 — Ajouter une couche fine de contexte projet.**

L'article distingue trois types d'information à garder, qui ne sont **pas**
du code et que l'agent ne peut pas inférer :

- **Build commands** : commandes pour exécuter, tester, formater (utile
  uniquement si non triviales ou non documentées dans `pubspec.yaml` /
  `package.json`).
- **Conventions invisibles** : décisions qui ne sont pas visibles dans le
  code existant (ex. « toutes les dates en UTC », « les feature flags
  vivent dans `config/flags.ts` »).
- **Watch out** : leçons d'incidents passés, en une ligne (ex. « le
  timeout du service de paiement est 30s, pas 5s par défaut »).

Le reste — préférences personnelles, tutoiement, accents, langue — peut
rester si chaque ligne passe le critère de coupe. Sinon, dégager.

**Étape 4 — Vérifier la taille.**

Compter les caractères. Si > 6 000, c'est qu'on n'a pas fini de couper.
La cible raisonnable selon l'article : suffisamment court pour que
chaque ligne ait été choisie, pas accumulée.

## Plan de refonte des skills

Les skills (`~/claude-config/config/skills/`) suivent la même logique mais
sont **scopés** à un cas d'usage. Donc :

- **Garder uniquement les skills qui résolvent un problème dont la solution
  ne tient pas dans CLAUDE.md.** Un skill « comment écrire des fonctions
  Dart » est probablement absorbable par CLAUDE.md ou par les conventions
  du projet ; un skill « comment générer un PDF avec pandoc » est un cas
  d'usage spécifique avec sa logique propre, à garder.

- **Pour chaque skill, appliquer le critère de coupe.** Une procédure de
  10 étapes peut souvent se réduire à 3 décisions clés + une référence
  externe. Le reste se déduit.

- **Tester l'invocation.** Un skill qui ne se déclenche jamais (parce que
  son `description` ne matche pas les requêtes naturelles de l'utilisateur)
  est mort. Soit on retravaille le `description`, soit on supprime.

## Comment exécuter la refonte

1. **Inventaire** : lister CLAUDE.md global + tous les skills, avec leur
   taille en caractères et leur fréquence supposée d'utilisation.
2. **Coupe première passe** : appliquer le critère de coupe ligne par
   ligne, sans pitié. Mesurer le gain en caractères.
3. **Restructuration** : poser les 5 lignes en tête de CLAUDE.md global,
   puis la couche fine de contexte (build / conventions / watch out).
4. **Test sur 3-5 sessions réelles** : observer si Claude continue à
   enfreindre les consignes restantes. Si oui, c'est que la formulation
   est mauvaise (pas que la consigne est manquante). Reformuler en
   intention plutôt qu'en procédure.
5. **Itération** : après une semaine d'usage, refaire une passe de coupe.

## Pièges à éviter

- **Ajouter une règle pour corriger un comportement.** Premier réflexe
  naturel mais mauvais : si Claude enfreint X, ajouter « toujours faire X »
  va se diluer dans le bruit existant. Demander d'abord pourquoi la règle
  actuelle n'est pas respectée — c'est presque toujours une question de
  formulation (procédure vs intention) ou de localisation (noyée dans
  d'autres règles).

- **Confondre intention et procédure.** « Avant chaque édition, vérifier
  X, Y, Z » est une procédure. « Le code doit pouvoir être relu sans
  contexte » est une intention. L'intention génère le bon comportement
  dans des cas non anticipés ; la procédure ne couvre que les cas listés.

- **Mettre des consignes sur ce que l'agent fait déjà bien.** Si Claude
  écrit naturellement des chaînes en double-quote dans 95 % des cas, la
  règle « toujours utiliser des double-quotes » paie le coût d'une ligne
  pour gagner les 5 % restants — souvent un mauvais ratio.

- **Documenter au lieu de contraindre.** CLAUDE.md n'est pas un manuel
  de référence. Une ligne qui *décrit* une convention sans changer le
  comportement de l'agent est du bruit.

## Référence

Article source : *The 4 Lines Every CLAUDE.md Needs*, Yanli Liu, Level Up
Coding, avril 2026.

Repo cité par l'article (les 4 lignes + EXAMPLES.md avec walkthroughs
avant/après) : `forrestchang/andrej-karpathy-skills` sur GitHub.

Diagnostic original de Karpathy (janvier 2026) : trois failles des LLM en
contexte agentique :
1. ils font des suppositions silencieuses,
2. ils sur-architecturent (1 000 lignes là où 100 suffiraient),
3. ils modifient ou suppriment du code orthogonal qu'ils ne comprennent
   pas suffisamment.

Les 4 lignes mappent directement sur ces trois failles ; la 4e ligne
ajoute le levier « critères de succès + boucle » que Karpathy avait
mentionné comme la vraie force des LLM mal exploitée.
