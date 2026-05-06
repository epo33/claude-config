---
name: audit-version
description: "Audit manuel des règles CLAUDE.md à l'occasion d'un changement de version de modèle. Lit le journal des violations/respects, croise avec CLAUDE.md et CLAUDE-rationale.md, produit un rapport markdown que l'utilisateur exploite ensuite pour décider des ajustements. INVOCATION MANUELLE UNIQUEMENT par /audit-version, jamais auto-déclenchée."
user-invocable: true
---

Audit des règles comportementales sur la base des données empiriques accumulées dans le journal `~/claude-config/violations/violations-YYYY-MM.jsonl`.

**Ce skill ne modifie rien.** Il produit uniquement un rapport markdown que l'utilisateur lit et utilise pour décider lui-même des ajustements à `CLAUDE.md` ou aux skills.

## Quand l'invoquer

L'utilisateur lance `/audit-version` typiquement :

- au début d'une session sur une nouvelle version du modèle, pour vérifier si les règles tiennent encore,
- périodiquement (hebdo, mensuel) pour observer les tendances et identifier les règles qui dérivent.

Ne jamais s'auto-déclencher.

## Entrées

1. Le journal `~/claude-config/violations/violations-YYYY-MM.jsonl` (mois courant) et les mois précédents s'il y en a.
2. Le fichier `~/claude-config/config/CLAUDE.md` (règles actuellement en vigueur).
3. Le fichier `~/claude-config/config/CLAUDE-rationale.md` s'il existe (motivations détaillées des règles, à consulter pour comprendre l'intention).
4. Argument optionnel : fenêtre temporelle (`--since 7d`, `--since 30d`, `--all`). Par défaut, 30 jours.

## Étapes

1. **Confirmer la portée à l'utilisateur** avant de lire :
   - Fenêtre temporelle retenue (par défaut 30 jours).
   - Modèle actuellement en cours (lu dans le contexte session) ; signaler s'il a changé depuis le dernier audit.

2. **Lire le journal** sur la fenêtre demandée. Compter par `outcome` (`violation` vs `respect`) et par `model`. Si plusieurs versions de modèle sont représentées, segmenter l'analyse par modèle.

3. **Regrouper les entrées par thématique** sur la base du contenu brut (pas de classification a priori). Le regroupement se fait à la lecture, en identifiant les patterns récurrents (commentaires inutiles, longueur de réponse, numérotation incohérente, etc.). Si une entrée ne se rattache à rien de clair, la lister à part dans une section « inclassées ».

4. **Pour chaque thématique identifiée**, produire :
   - Le nombre de violations et de respects, avec ratio.
   - Un ou deux exemples représentatifs (extrait du `content` du journal).
   - La ou les règles de `CLAUDE.md` concernées (par référence textuelle ou citation courte).
   - Une analyse en trois axes : **formulation** (la règle est-elle bien calibrée pour la version actuelle ?), **activation** (est-elle réactivée au bon moment ?), **conflit** (est-elle en concurrence avec une autre règle ?).
   - Une recommandation d'action **proposée**, jamais imposée : conserver tel quel, reformuler, déplacer, supprimer, scinder.

5. **Top 3 des thématiques les plus violées** : section dédiée en tête du rapport, parce que c'est là que l'attention de l'utilisateur doit aller en priorité.

6. **Top 3 des thématiques les mieux respectées** : section symétrique, parce que ce sont les formulations qui marchent et qui peuvent servir de modèle pour les règles à reformuler.

7. **Écrire le rapport** dans `~/claude-config/violations/audit-YYYY-MM-DD.md` (date du jour). Format markdown, lisible d'un bloc par l'utilisateur. **Bash uniquement** pour l'écriture (UTF-8, LF).

8. **ACK final** : indiquer le chemin du rapport produit, en une phrase. Pas de récapitulatif inline.

## Règles de production du rapport

- Pas de proposition de patch ou de diff sur `CLAUDE.md`. Uniquement des recommandations textuelles.
- Pas de classification rigide en taxonomie fermée. Le regroupement émerge des données.
- Si le journal est vide ou contient moins de 5 entrées sur la fenêtre, le signaler explicitement et conseiller d'attendre plus de signalements avant de tirer des conclusions.
- Distinguer clairement les recommandations qui s'appuient sur **plusieurs cas observés** (forte confiance) de celles qui s'appuient sur **un seul cas** (faible confiance, à confirmer).
- Citer le contenu brut des entrées du journal, jamais reformuler ou « interpréter pour le compte de ». L'utilisateur doit pouvoir vérifier ce qui a été observé.

## Format du rapport

```
# Audit version — {DATE}

## Périmètre
- Fenêtre : {DEPUIS} → {AUJOURDHUI}
- Modèle(s) couvert(s) : {LISTE}
- Total signalements : {N} ({V} violations, {R} respects)

## Top 3 thématiques violées
{...}

## Top 3 thématiques respectées
{...}

## Détail par thématique
{...}

## Inclassées
{...}

## Recommandations consolidées
{...}
```

## Sortie attendue côté utilisateur

L'utilisateur lit le rapport et décide :
- de modifier `CLAUDE.md` lui-même (ou de me demander de le faire dans une session ultérieure),
- de modifier le rationale,
- d'attendre plus de données avant d'agir,
- de fermer une thématique comme résolue.

Ce skill ne fait aucune de ces actions. Il produit uniquement la matière pour les décider.
