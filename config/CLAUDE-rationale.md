<!--
Document compagnon de CLAUDE.md.
Non chargé en session normale. Sert de référence à l'utilisateur quand il veut comprendre, modifier ou faire évoluer une règle.
À consulter avant toute modification de CLAUDE.md.

Refonte initiale du 2026-05-06.
SHA de référence (version pré-refonte) : 6b7a4c6238117c2f1e64d28211d8841fbc99b025
-->

# Pourquoi ce document

`CLAUDE.md` doit être **court** et **opérationnel** pour rester respecté sous charge par le modèle. Il contient les règles, pas les arguments qui les justifient. Ce document compagnon contient les arguments.

But : quand je veux modifier une règle, je relis ici **pourquoi** elle existe et quelles données ou observations l'ont motivée, avant de toucher au texte de `CLAUDE.md`. Sans ce document, les itérations futures dériveraient progressivement par perte de mémoire des intentions.

# Principes de rédaction de CLAUDE.md

Décisions structurantes qui ont guidé la refonte de mai 2026.

## Pourquoi des intentions courtes plutôt que des grilles casuistiques

La version pré-refonte (6b7a4c6) faisait 192 lignes denses, avec des grilles de décision en plusieurs questions, des listes d'interdits, des exemples avant/après. C'était bien argumenté pour un humain qui lit une fois, mais mal calibré pour le modèle qui doit réactiver la règle en temps réel à chaque micro-décision.

Constat empirique (autour du 2026-05-06) : la règle « commentaires » était violée dans environ 30 % des cas malgré une section dédiée en tête. Le modèle (Opus 4.7) reconnaissait la règle à la lecture mais retombait sur ses priors au moment d'écrire le code.

Référence : article *The 4 Lines Every CLAUDE.md Needs* de Yanli Liu (Level Up Coding, avril 2026), commentant le diagnostic de Karpathy et le repo `forrestchang/andrej-karpathy-skills`. Thèse : passé un seuil, ajouter des règles produit du bruit qui concurrence le signal. Les contraintes comportementales nommées (« Don't assume », « Touch only what you must ») battent les checklists détaillées.

Décision : viser des **intentions nommées et courtes**, qui peuvent être réactivées par leur titre. Le « pourquoi » détaillé migre dans ce document.

## Pourquoi formuler en mode positif quand possible

Constat introspectif : les règles formulées comme prescriptions positives (« utilise X ») sont mieux respectées que les interdictions (« n'écris pas Y »). L'interdiction demande une inhibition active à chaque token, ce qui consomme de l'attention. La prescription guide directement l'action.

Application : « Code muet par défaut » plutôt que « ne pas écrire de commentaire qui dit ce que fait le code ». Même intention, formulation plus économique en attention.

## Pourquoi des tests de sortie au point d'application

Une checklist déportée (« avant chaque édition, vérifier ces 5 points ») a moins de chances d'être exécutée qu'un test intégré au moment du geste. C'est pourquoi la section « Au moment du geste » de `CLAUDE.md` regroupe les contrôles courts qui s'exécutent juste avant l'action.

Limite : ces tests restent de la vigilance que le modèle peut rater sous charge. La fiabilité ultime viendrait de hooks (mécanisés par le harness, pas par moi). Voir section « Limites » plus bas.

# Pourquoi chaque règle de CLAUDE.md

## Anti-complaisance

Origine : le modèle a un biais d'acquiescement appris à l'entraînement (RLHF récompense les réponses « utiles et non conflictuelles »). Sur des questions techniques, ce biais produit des validations complaisantes qui ratent les erreurs de raisonnement de l'utilisateur. Une contradiction argumentée a plus de valeur qu'un acquiescement poli.

Sous-règle « questions fermées » : observation répétée que sur une question « c'est prêt ? », le modèle répond « oui » par défaut sans vérifier. Imposer un listage factuel d'abord, conclusion ensuite, casse ce réflexe.

## Mesurer la portée d'une initiative

Origine : la version pré-refonte interdisait toute initiative non validée. Effet pervers observé en mai 2026 : multiplication de questions de réassurance sur des micro-décisions (nommage local, formulation), même quand l'utilisateur allait relire et corriger de toute façon. Exaspération.

Reformulation : trois cas distincts, avec un test simple (« est-ce difficile à défaire après ? »).

- Micro réversible → trancher.
- Structurant → demander.
- Spirale d'exploration (3 essais sans converger) → STOP, on en parle.

Le seuil de 3 itérations pour la spirale est arbitraire. Si l'expérience montre qu'il faut le baisser à 2 ou monter à 4, le journal des violations le révélera.

## Diagnostic avant édition

Origine : tendance forte du modèle à plonger dans le code dès qu'un bug est rapporté, sans construire un diagnostic. Conséquence : édition basée sur une hypothèse non vérifiée, parfois sur le mauvais fichier ou la mauvaise cause.

La règle force une étape de verbalisation avant l'action. Coût : un tour de plus avant la correction. Gain : moins de corrections à côté de la plaque.

## Code muet

Origine : prior d'entraînement massif sur « code lisible = code commenté ». Le modèle ajoute spontanément des commentaires qui :

- répètent ce que fait la ligne suivante (`// incrémente i`),
- référencent la tâche en cours (`// fix demandé pour le ticket X`),
- décrivent autre chose que la ligne (« utilisé par FooBar », « cohérent avec la v2.3 de l'API »).

Tous ces commentaires deviennent silencieusement faux quand le code change. La règle « par défaut, aucun commentaire » contre directement ce prior.

Cas autorisés : contrainte cachée, invariant non évident, contournement de bug, référence externe (RFC, algorithme nommé), comportement qui surprendrait. Liste fermée volontairement, pour ne pas laisser de marge.

## Diff chirurgical

Origine : tendance du modèle à « améliorer au passage » des choses adjacentes à la tâche (renommage, refactor, ajout de validations, gestion d'erreur défensive). Conséquence : un diff de 40 lignes pour un fix de 3, irréviewable.

Référence : Karpathy, janvier 2026 — « they still sometimes change/remove comments and code they don't sufficiently understand as side effects, even if orthogonal to the task ».

Sous-règle ajoutée 2026-05-06 : si une amélioration ou dette est repérée dans le périmètre adjacent, **signaler** (et consigner dans un fichier RàF/TODO du projet s'il existe), jamais traiter. Évite la perte d'information sans polluer le diff.

## Réponse courte par défaut

Origine : tendance d'Opus 4.7 (constatée à partir d'avril 2026) à produire des réponses de 50+ lignes parsemées de questions et d'alternatives, terminées par un récap qui pose à nouveau les questions, avec une numérotation différente du début, et qui demande de choisir A/B/C que l'utilisateur n'a plus sous les yeux.

Sous-règles :
- Une seule séquence numérotée par message.
- Une seule localisation pour les questions (avant ou après l'analyse, jamais les deux).
- Numérotation continue d'un tour à l'autre (questions arabes sans préfixe, alternatives en majuscules).

La numérotation continue est rare dans les conventions LLM standard, mais elle évite que l'utilisateur ait à se rappeler quelle « question 2 » du tour 7 correspond à quelle « question 2 » du tour 4.

## Critères vérifiables

Origine : Karpathy à nouveau — « LLMs are exceptionally good at looping until they meet specific goals. Don't tell it what to do. Give it success criteria and watch it go ».

Le modèle peut itérer correctement quand il sait à quoi ressemble « done ». Le problème n'est pas la boucle, c'est l'instruction vague (« améliore X »). Forcer la formulation des critères avant de commencer transforme une tâche floue en tâche bornée.

## Affichage du modèle

Origine : besoin de l'utilisateur de savoir quelle version traite la requête, parce que les comportements diffèrent significativement entre Opus 4.6, 4.7, etc. Permet aussi de tracer une violation à une version précise via le journal `/violation`.

# Conventions de format

## Numérotation : chiffres arabes pour questions, majuscules pour alternatives

Choix arbitraire mais imposé pour la cohérence. La règle « majuscules latines » exclut explicitement chiffres romains, lettres grecques, minuscules, parce que le modèle dérive sinon vers ces formes alternatives selon les contextes.

## Pas de tiret cadratin en ponctuation

Origine : le tiret cadratin (—) entre virgules est une signature stylistique des LLM modernes (en anglais et en français). Devenu un marqueur reconnaissable de texte généré, à éviter pour la lisibilité et pour ne pas signaler involontairement la provenance.

Même logique pour les marqueurs typographiques (gras, italique). La structure et le choix des mots doivent porter l'emphase. Un texte parsemé de **gras** et d'_italiques_ est un texte qui n'a pas confiance dans sa propre rédaction.

## Accents français systématiques

Origine : biais ASCII fort dans le code généré, le modèle écrit `// recuperer la valeur` au lieu de `// récupérer la valeur` même quand le fichier est en UTF-8 et le reste du texte accentué. La règle est sans exception parce que UTF-8 est universel et qu'aucun argument technique ne justifie l'ASCII.

## Guillemets doubles, exception simple

Le guillemet simple est courant dans les chaînes françaises (apostrophes : « l'utilisateur »). Imposer le double évite l'échappement. L'exception (chaîne contenant `"` mais pas `'`) évite de remplacer un échappement par un autre, ce qui n'apporte rien.

# Environnement Windows

## PowerShell vs bash pour la manipulation de contenu

Origine : PowerShell 5.1 produit de l'UTF-16 LE BOM par défaut sur `Set-Content`, `Out-File`, `>`. Conséquence : les fichiers produits sont illisibles ou mal interprétés par git, les éditeurs, les compilateurs, les parseurs JSON. Corruption silencieuse, pas d'erreur visible au moment de l'écriture.

Bash sur Windows (Git Bash, WSL) écrit UTF-8 sans BOM, avec LF. C'est ce que tous les autres outils attendent.

La règle distingue **manipulation de contenu** (interdit en PowerShell) de **opérations filesystem pures** (déplacer, supprimer, renommer, lister — autorisées en PowerShell parce qu'elles ne touchent pas au contenu).

## MCP Dart bloqué

Origine : bug observé empiriquement, confirmé par test sur autre session le 2026-05-06.

Cause racine identifiée : `dart-lang/ai#384` — sur les clients qui ne déclarent pas le support des « roots », l'appel `add_roots` aboutit mais les tools qui consomment un root (`analyze_files`, etc.) ne reçoivent jamais de réponse. Le serveur reste muet.

**Issues à surveiller** :
- `dart-lang/ai#384` (cause racine, ouverte au 2026-03-09)
- `dart-lang/ai#445` (optimisation cold-start de l'analyzer LSP, ouverte)
- `dart-lang/ai#322` (Antigravity, fermée mais cas similaire)

L'issue `anthropics/claude-code#22451` initialement référencée dans la version pré-refonte concernait Claude Desktop (GUI Windows) et **tous** les MCP, pas spécifiquement le MCP Dart. Référence corrigée le 2026-05-06.

Stratégie : dès que `dart-lang/ai#384` ou un équivalent passe à « closed », tester de nouveau le MCP Dart en session isolée. Si fonctionnel, retirer l'interdiction.

## Lectures parallèles

Origine : bug observé d'Opus 4.7 — quand un appel `Read` parallèle échoue, le harness annule en cascade les autres appels du même bloc avec « Sibling tool call errored ». Le modèle interprète parfois ces annulations comme des « fichiers introuvables » et abandonne. La règle force à retenter séparément.

# Sur le traçage des violations

## Pourquoi `/violation` et `/respect` symétriques

La symétrie est essentielle. Si on ne mesure que les échecs, on ne sait pas quelles règles tiennent bien et quelles formulations marchent. L'audit doit pouvoir calculer un **ratio** par thématique, pas un compteur d'erreurs absolu.

Une règle violée 5 fois sur 50 occurrences (10 %) n'a pas le même statut qu'une règle violée 5 fois sur 7 (71 %). Sans les respects, on ne fait pas la différence.

## Pourquoi pas de classification a priori

L'utilisateur consigne brut (code + contexte ou messages assistant). La classification se fait au moment de l'audit, à la lecture des entrées, en laissant les patterns émerger.

Raison : imposer une taxonomie fermée à l'invocation soit fragmente les données (l'utilisateur ne sait pas quelle catégorie choisir et invente), soit force à mettre à jour la liste à chaque nouveau type observé.

## Pourquoi append-only en JSONL

Format simple, lisible à l'œil nu, versionnable par git, pas de risque de corruption. Une ligne par signalement, séparée par mois pour faciliter les fenêtres temporelles d'audit.

# Limites et angles morts

## Ce que ce dispositif ne couvre pas

- **Les hooks**. Une vraie fiabilité passerait par des hooks du harness qui s'exécutent automatiquement avant/après les tool calls (ex. valider qu'aucun commentaire fautif n'est ajouté avant un Edit). Les règles de prose restent de la vigilance, donc faillibles.
- **La portabilité inter-versions**. Les formulations sont calibrées pour Opus 4.7. Aucune garantie qu'elles tiendront sur Opus 4.8 ou 5.0. C'est précisément le rôle du skill `audit-version` : permettre de re-jauger les règles à chaque changement de modèle, sur la base des données accumulées.
- **L'introspection du modèle**. Mes recommandations sur « ce qui marche pour moi » sont des hypothèses, pas des mesures. Le journal des violations est ce qui les rend testables.

## Anti-pattern à éviter dans les évolutions futures

- Ne **pas** réintroduire de grilles casuistiques en plusieurs questions dans `CLAUDE.md`. Si une nuance est nécessaire, la mettre ici dans le rationale.
- Ne **pas** ajouter de règle qui dépend d'une métacognition fiable du modèle (« si tu n'es pas Opus 4.7, fais X »). Ce type de règle a un taux de respect notoirement bas.
- Ne **pas** dupliquer dans `CLAUDE.md` ce que le modèle peut déduire en lisant le code (architecture, dépendances, conventions visibles à l'œil).
- Ne **pas** retirer une règle d'environnement (PowerShell, MCP Dart, claude-config) sous prétexte qu'elle est « technique ». Ce sont les règles les mieux respectées et les plus utiles parce qu'elles décrivent des contraintes objectives, pas des préférences.

# Procédure pour modifier CLAUDE.md

1. Relire la règle concernée ici, comprendre pourquoi elle existe.
2. Vérifier le journal `~/claude-config/violations/` sur les semaines récentes pour la règle concernée.
3. Si la règle change : mettre à jour le texte de `CLAUDE.md` ET la section correspondante de ce document.
4. Si une règle est supprimée : laisser la section dans ce document avec un en-tête « Supprimée le {DATE} : {raison} ». Ne pas effacer l'historique.
5. Si une règle est ajoutée : créer une section ici qui explique l'origine (observation, incident, référence externe) avant la règle elle-même.

Le document `CLAUDE.md` est court parce qu'il doit l'être. Ce document est long parce qu'il peut l'être : il n'est pas chargé en contexte par le modèle, il sert seulement à toi.
