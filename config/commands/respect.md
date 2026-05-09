---
description: Tracer un respect de consigne (carotte). Symétrique de /violation. Capture le contexte et écrit une entrée dans le journal mensuel.
argument-hint: "optionnel : référence fichier:lignes type src/foo.dart:42-58, bloc collé, ou phrase libre. Sans argument, capture les deux derniers messages assistant."
---

Enregistrer un **respect** de consigne dans `~/claude-config/violations/violations-YYYY-MM.jsonl`.

Cette commande est strictement symétrique de `/violation` : seul le champ `outcome` change. Elle existe pour mesurer aussi les progrès et les contextes où les règles tiennent, pas seulement les échecs.

## Décision sur le contenu à capturer

1. Si l'utilisateur a fourni une référence `chemin:lignes` (ex. `src/foo.dart:42-58`) ou une plage explicite : `kind = "code"`, lire le fichier et capturer le bloc.
2. Sinon, si l'utilisateur a collé un bloc de code dans ses arguments : `kind = "code"`, capturer le bloc tel quel, `file` et `lines` à null.
3. Sinon (pas de référence ni de bloc) : `kind = "message"`, capturer **les deux derniers messages assistant** de la conversation (l'avant-dernier et le dernier).
4. Si le contexte reste ambigu après ces trois cas, demander à l'utilisateur quel est le périmètre **avant** d'écrire.

## Champs de l'entrée JSONL

Une seule ligne JSON, encodée UTF-8, avec ces champs :

- `timestamp` : ISO 8601 (`date -u +%Y-%m-%dT%H:%M:%SZ`)
- `outcome` : `"respect"`
- `kind` : `"code"` ou `"message"`
- `model` : version du modèle exposée dans le contexte session (ex. `"claude-opus-4-7"`)
- `branch` : branche git du **projet courant** (`git rev-parse --abbrev-ref HEAD` depuis le cwd), null si pas un repo
- `file` : chemin si `kind=code` avec référence fichier, sinon null
- `lines` : `"42-58"` si plage fournie, sinon null
- `content` : le bloc capturé (code ou messages assistant), texte brut
- `note` : phrase libre éventuellement passée par l'utilisateur, sinon null

## Écriture

- Cible : `~/claude-config/violations/violations-YYYY-MM.jsonl` (mois courant, **même fichier** que `/violation`).
- Mode : append. Une ligne par invocation.
- **Toujours bash**, jamais PowerShell (UTF-8 sans BOM, LF).
- Forme recommandée : construire le JSON avec `python -c` ou `jq -n`, puis `>>` redirigé en UTF-8.

## ACK

Une seule phrase, factuelle, sobre. Pas de célébration excessive, pas de méta-commentaire. Exemples :

- « OK, noté. Pas de commentaire inutile cette fois. Tracé. »
- « OK, noté. Réponse courte et numérotation cohérente. Tracé. »
- « OK, noté. `src/foo.dart:42-58` capturé. Tracé. »

Puis rendre la main, point.

## Règles

- Ne **jamais** classifier le respect par règle ou catégorie. Le contenu brut suffit, l'audit ultérieur fera l'analyse.
- Si l'écriture du fichier échoue, le signaler clairement à l'utilisateur (ne pas faire échouer silencieusement).
