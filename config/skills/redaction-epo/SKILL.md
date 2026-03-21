---
name: redaction-epo
description: "Conventions de rédaction EPO : style, typographie française, registre soutenu. Charge les consignes pour guider la rédaction de documents destinés à être émis."
user-invocable: true
---

Quand ce skill est invoqué (`/redaction-epo`), lire et charger les règles définies dans `prompt.md` (même répertoire que ce fichier). Ces règles s'appliquent ensuite à toute rédaction ou modification de document dans la suite de la conversation.

## Comportement par défaut

- Appliquer les consignes de `prompt.md` à tout texte rédigé ou modifié dans la conversation.

## Correction sur demande

Si l'utilisateur demande explicitement une relecture ou correction d'un document existant :

Présenter les corrections une par une. Pour chaque correction :

1. Citer le passage original en signalant clairement la partie problématique (gras, soulignement ou autre mise en évidence).
2. Proposer la correction en signalant clairement la partie modifiée.
3. Pour les reformulations (style, vocabulaire, structure), proposer 2-3 variantes en texte libre. Chaque variante doit être lisible en entier avec la partie modifiée clairement signalée.

Appliquer chaque modification au fur et à mesure, après validation de l'utilisateur. Ne JAMAIS modifier sans validation préalable.
