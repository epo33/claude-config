# Versionning d'un modèle

A chaque modification du modèle, Sing permet de mettre à jour automatiquement les structures de données (schéma, tables, colonnes, index, etc). [How to prepare database schema migration](MIGRATIONS.md).

Les versions d'un modèle sont déclarées par `Model.majorVersions` (arbre `MajorVersion` → `MinorVersion` → `PatchVersion`, numéroté par position en `major.minor.patch`). La version courante d'un modèle est portée par `Xxx$Layer.version` et `ServerDataRegistry.version` (`"0.0.0"` sans aucune version déclarée). Une application enregistre `ServerDataRegistry.layerVersionChain` (une version par couche de modèle, eg `"Base=1.1.1;OrderHub=2.1.8"`) et la repasse à `migrateDatabase(callContext, fromVersionChain:)`.
