# LO03 Projet 2026 - Bash File System Synchronizer

## Présentation

Ce projet implémente un synchroniseur de deux arborescences locales en Bash.

Le programme compare deux répertoires `A` et `B` situés sur la même machine et utilise un journal décrivant le dernier état synchronisé avec succès. La spécification principale reste [`LO03-Projet-2026.pdf`](./LO03-Projet-2026.pdf).

L’implémentation adopte un comportement conservateur :

- si une action sûre peut être déduite, elle est appliquée
- si la situation est ambiguë, le programme signale un conflit au lieu de deviner

## Structure Du Dépôt

```text
src/
  sync.sh              Script principal
tests/
  run_tests.sh         Suite de tests locale
demo/
  demo.sh              Démonstration simple pour présentation
docs/
  design-notes.md      Notes de conception
  report-outline.md    Plan de rapport
TASK.md                Résumé de travail
LO03-Projet-2026.pdf   Sujet principal
README.md              Documentation d'utilisation
```

## Utilisation

Commande principale :

```bash
bash src/sync.sh [options] DIR_A DIR_B LOG_FILE
```

Exemple minimal :

```bash
mkdir -p /tmp/treeA /tmp/treeB
printf 'bonjour\n' > /tmp/treeA/note.txt

bash src/sync.sh /tmp/treeA /tmp/treeB /tmp/journal.tsv
```

Exemple en mode verbeux :

```bash
bash src/sync.sh --verbose /tmp/treeA /tmp/treeB /tmp/journal.tsv
```

Exemple avec mode amélioré :

```bash
bash src/sync.sh --enhanced /tmp/treeA /tmp/treeB /tmp/journal.tsv
```

## Options

- `--help`
  Affiche l’aide.

- `--verbose`
  Affiche les chemins détectés, les décisions prises et les actions exécutées.

- `--enhanced`
  Active la comparaison de contenu pour réduire les faux conflits entre fichiers réguliers.

## Journal

Le journal représente l’état du dernier cycle de synchronisation réussi.

Il sert à répondre à la question suivante :

“Quelle copie correspond encore à l’ancien état synchronisé, et quelle copie a changé depuis ?”

Format actuel du journal :

```text
relative/path<TAB>mode<TAB>size<TAB>mtime
```

Le journal stocke uniquement les fichiers réguliers.

## Qu’est-Ce Qu’un Conflit ?

Un conflit correspond à une situation où le programme ne peut pas décider une action sûre sans risquer d’écraser une information importante.

Les principales catégories actuellement gérées sont :

- `type-conflict`
  Un chemin est un répertoire d’un côté et un fichier régulier de l’autre.

- `presence-conflict`
  Un chemin n’existe que d’un côté dans une situation où une suppression ne doit pas être supposée automatiquement.

- `regular-conflict`
  Les règles simples sur les fichiers réguliers ne permettent pas de déterminer un sens de copie sûr.

- `content-conflict`
  En mode amélioré, les contenus des deux fichiers diffèrent réellement.

- `metadata-only-conflict`
  Les contenus sont identiques, mais les métadonnées ont divergé des deux côtés par rapport au journal.

- `unsupported-type`
  Le chemin correspond à un type de fichier non pris en charge par l’implémentation actuelle.

## Pris En Charge / Non Pris En Charge

Pris en charge actuellement :

- deux arborescences locales sur la même machine
- fichiers réguliers
- répertoires
- chemins contenant des espaces
- comparaison des métadonnées `mode`, `size`, `mtime`
- mode amélioré avec comparaison de contenu

Non pris en charge ou volontairement conservateur :

- liens symboliques et types spéciaux
- propagation automatique de suppressions
- synchronisation réseau ou entre machines différentes
- noms de chemins contenant des tabulations dans le journal

## Exemples De Comportement

### 1. Deux arbres identiques

Le programme ne fait rien et réécrit un journal cohérent.

### 2. Un seul côté a changé

Si un côté correspond encore au journal et l’autre non, le changement est propagé vers le côté ancien.

### 3. Même contenu, métadonnées différentes

En mode `--enhanced`, si le contenu est identique, le programme peut synchroniser uniquement les métadonnées au lieu de recopier tout le fichier.

### 4. Deux contenus différents

Le programme déclare un conflit au lieu d’écraser l’une des deux versions sans certitude.

## Tests

Lancer toute la suite de tests :

```bash
bash tests/run_tests.sh
```

La suite :

- crée des répertoires temporaires
- couvre les cas de succès et de conflit
- échoue avec un message explicite si une attente n’est pas respectée

## Démonstration

Pour une démonstration simple en salle :

```bash
bash demo/demo.sh
```

Le script montre :

- une première synchronisation
- une modification d’un seul côté
- un cas de métadonnées seules en mode amélioré
- un cas de conflit réel de contenu

## Limitations

- le comportement sur certains cas de répertoires asymétriques reste conservateur
- la sortie des conflits peut encore être rendue plus pédagogique
- l’implémentation suit `TASK.md` et la lecture disponible du sujet PDF, avec priorité à la sécurité quand une ambiguïté subsiste
