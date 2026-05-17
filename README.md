# claude-config

Dépôt de synchronisation de la configuration Claude Code entre machines.

## Besoin

Travailler avec Claude Code sur plusieurs postes (Windows, macOS, etc.) en conservant une configuration homogène : instructions personnalisées, settings, skills, commandes, serveurs MCP.

## Principes

- **Source unique de vérité** : toute modification de config se fait dans `config/`, jamais directement dans `~/.claude/`.
- **Synchronisation bidirectionnelle** : une seule commande (`/claude-sync`) pour envoyer les changements locaux ET récupérer ceux des autres machines.
- **Adaptation automatique des chemins** : les chemins spécifiques à l'OS (Windows ↔ macOS) sont substitués à l'application.
- **Simplicité** : des scripts shell courts et lisibles, pas de dépendance externe.

## Structure

```
claude-config/
├── config/                 # Source de vérité de la configuration
│   ├── CLAUDE.md           # Instructions globales Claude
│   ├── dart.instructions.md
│   ├── settings.json
│   ├── mcp.json
│   ├── statusline-command.sh
│   ├── commands/           # Commandes slash personnalisées
│   └── skills/             # Skills personnalisés
├── _apply.sh               # Copie config/ → ~/.claude/ avec substitution de chemins
├── sync.sh                 # Synchronisation bidirectionnelle (commit+push → pull → apply)
├── push.sh                 # Commit + push local → apply
├── pull.sh                 # Pull remote → apply
├── status.sh               # Vérifie l'état de synchronisation avec le remote
└── README.md
```

## Usage quotidien

Une seule commande à retenir :

```
/claude-sync
```

Cette commande (utilisable dans Claude Code) :
1. Commit et pousse les modifications locales vers le remote
2. Récupère les changements depuis le remote (autres machines)
3. Applique la configuration dans `~/.claude/`

## Scripts individuels

| Script | Usage |
|---|---|
| `bash ~/claude-config/sync.sh` | Synchronisation complète (équivalent de `/claude-sync`) |
| `bash ~/claude-config/push.sh` | Commit + push + apply (sans pull) |
| `bash ~/claude-config/pull.sh` | Pull + apply (sans commit/push local) |
| `bash ~/claude-config/status.sh` | Affiche l'état de synchronisation avec le remote |
