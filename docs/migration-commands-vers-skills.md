# Migration commands → skills

**Contexte** : Claude Code a fusionné les mécanismes `commands` et `skills`. Les fichiers dans `.claude/commands/` continuent de fonctionner mais sont dépréciés. Les skills sont le standard recommandé.

## Différences pratiques

| Aspect | Commands (déprécié) | Skills (recommandé) |
|---|---|---|
| Emplacement | `.claude/commands/<nom>.md` | `.claude/skills/<nom>/SKILL.md` |
| Format | Markdown brut | Markdown + frontmatter YAML |
| Fichiers support | Non | Oui (templates, exemples, scripts dans le répertoire) |
| Frontmatter | Non | `name`, `description`, `allowed-tools`, `context: fork`, etc. |
| Exécution en subagent | Non | Oui (`context: fork`) |
| Injection dynamique | Non | Oui (`` !`commande` ``) |
| Contrôle d'invocation | Utilisateur uniquement | Utilisateur, Claude, ou les deux |
| Priorité en cas de conflit | Basse | Haute (le skill gagne) |

## État actuel de claude-config

### Commands existantes (à migrer)

```
config/commands/
├── claude-sync.md
├── commit_and_push.md
├── enum_jsonifiable.md
├── execute_plan.md
├── extract_children.md
└── prepare_plan.md
```

### Skills existants (déjà au bon format)

```
config/skills/
├── sing-project/
│   ├── SKILL.md
│   ├── DOC.md
│   └── skills/
└── widget_decomposition/
    ├── SKILL.md
    ├── refactoring.md
    ├── styled_widget.md
    └── templates/
```

## Plan de migration

### 1. Migrer chaque commande vers un skill

Pour chaque `config/commands/<nom>.md` :

1. Créer `config/skills/<nom>/SKILL.md`
2. Ajouter un frontmatter YAML avec au minimum `name` et `description`
3. Déplacer le contenu du `.md` dans le `SKILL.md`
4. Si pertinent, extraire les templates ou fichiers support dans le répertoire du skill

**Exemple** — `commands/prepare_plan.md` → `skills/prepare_plan/SKILL.md` :

```yaml
---
name: prepare_plan
description: Préparation d'un plan de réalisation d'une fonctionnalité ou refactoring
---

(contenu actuel de prepare_plan.md)
```

### 2. Mettre à jour `_apply.sh`

Vérifier que le script copie bien `config/skills/` vers `~/.claude/skills/`. Après migration complète, retirer la copie de `commands/`.

### 3. Supprimer les commandes migrées

Une fois chaque skill testé et fonctionnel, supprimer le fichier correspondant dans `config/commands/`.

### 4. Conserver `commands/` temporairement

Migrer progressivement, valider chaque skill, puis nettoyer.
