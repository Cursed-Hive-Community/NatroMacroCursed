# Installer le fork sur une Natro Macro que tu as déjà

Pour quelqu'un qui n'a jamais touché à git. Windows, cinq minutes.

**Tes réglages ne sont pas touchés.** Comptes, raccourcis, champs, patterns,
webhook Discord : tout le dossier `settings` est laissé tel quel, par cette
installation et par toutes les mises à jour qui suivront. Rien n'est
retéléchargé non plus : le dossier que tu lances déjà devient celui qui se met
à jour tout seul.

---

## 1. Ferme la macro

Toutes ses fenêtres. Puis ouvre le **Gestionnaire des tâches**
(Ctrl+Maj+Échap), cherche **AutoHotkey** dans la liste et termine ce qui reste.

Windows verrouille les fichiers d'un programme pendant qu'il tourne, et
l'installation doit en remplacer deux. Si tu sautes cette étape, l'étape 3
s'arrête et te le dit — rien n'est cassé, il faut juste revenir ici.

## 2. Installe Git, une fois par ordinateur

Git est ce qui va chercher les mises à jour. Tu n'auras jamais à t'en servir
toi-même.

Clic droit sur le bouton **Démarrer**, choisis **Terminal** ou
**PowerShell**, colle ceci et appuie sur Entrée :

```powershell
winget install --id Git.Git -e
```

Quand c'est fini, **ferme cette fenêtre et ouvre-en une nouvelle**. Sans ça,
`git` ne sera pas reconnu.

> Pas de `winget` sur ton Windows ? Télécharge l'installeur sur
> <https://git-scm.com/download/win> et clique Suivant jusqu'au bout. Tous les
> choix par défaut conviennent.

## 3. Branche ton dossier sur le dépôt

Dans la nouvelle fenêtre Terminal, colle ce bloc — **en remplaçant le chemin
de la première ligne par celui de ton dossier de macro**, celui qui contient
`START.bat` :

```powershell
cd "C:\Natro\Bot1"
git init -b main
git remote add origin https://github.com/Cursed-Hive-Community/NatroMacroCursed.git
git fetch origin
git reset --hard origin/main
git branch -u origin/main
```

Ligne par ligne, pour que tu saches ce que tu lances :

| Commande | Ce qu'elle fait |
|---|---|
| `cd "..."` | va dans ton dossier de macro |
| `git init -b main` | prépare le dossier à être suivi par git |
| `git remote add origin ...` | dit où est le fork |
| `git fetch origin` | télécharge le fork, sans encore rien changer |
| `git reset --hard origin/main` | remplace les fichiers de la macro par ceux du fork |
| `git branch -u origin/main` | retient la branche à suivre, pour les mises à jour |

C'est `git reset --hard` qui fait le travail, et c'est aussi lui qui **ne peut
pas** toucher à `settings` : git n'a jamais eu ce dossier dans ses fichiers, et
`reset` ne touche que les fichiers qu'il connaît. Tes notes, tes logs et tout
ce que tu as mis là de ton côté restent aussi.

## 4. Lance la macro

Double-clique sur **`START.bat`**, comme d'habitude.

Tout est là où tu l'avais laissé. En bas de la fenêtre de la macro il y a
maintenant un bouton **Git Sync**, à côté de Stop : c'est par là que tu mettras
à jour.

---

## Mettre à jour, ensuite

Deux façons, un clic chacune :

- le bouton **Git Sync** dans la macro, puis **Update** ;
- ou **`nm-update.bat`** dans le dossier.

Les deux arrêtent la macro, installent la nouvelle version, gardent tes
réglages et relancent la macro.

---

## Si ça coince

### `fatal: detected dubious ownership in repository at ...`

Git refuse de travailler dans un dossier qui, selon Windows, appartient à
quelqu'un d'autre — parce qu'un dépôt qui ne t'appartient pas pourrait
exécuter son propre code. Ça arrive si le dossier a été créé sous une autre
session Windows, copié depuis un autre PC, ou créé par un programme lancé en
administrateur.

Sur ton propre PC ce n'est pas ce qui se passe. Colle la ligne que git te
propose lui-même, elle est dans son message d'erreur, et elle ressemble à :

```powershell
git config --global --add safe.directory "C:/Natro/Bot1"
```

Puis reprends l'étape 3 là où elle s'était arrêtée.

> Si tu as cinq dossiers de macro et que tu ne veux pas le faire cinq fois :
> `git config --global --add safe.directory "*"` accepte tout. Ça désactive la
> vérification partout, ce qui est acceptable sur ton PC et à éviter sur une
> machine partagée.

### `Permission denied` ou `Accès refusé`

Là, Windows ne te laisse pas écrire dans le dossier du tout : il appartient à
un autre utilisateur **et** celui-ci n'a pas donné les droits au tien. Même
l'updater officiel de Natro Macro ne pourrait pas y travailler.

Le plus simple : **copie le dossier chez toi**. Crée `C:\Natro`, copie tout le
dossier de la macro dedans, et refais l'étape 3 sur la copie. Tes réglages
suivent.

Sinon, pour t'en rendre propriétaire : clic droit sur **Démarrer**,
**Terminal (admin)**, puis en mettant ton chemin à la place de l'exemple :

```powershell
takeown /F "C:\Natro\Bot1" /R /D Y
icacls "C:\Natro\Bot1" /grant "$env:USERNAME":(OI)(CI)F /T
```

### `error: unable to unlink ...` ou un nom de `.exe` dans l'erreur

La macro tourne encore. Retour à l'étape 1 : ferme ses fenêtres, vérifie dans
le Gestionnaire des tâches qu'aucun **AutoHotkey** ne reste, et relance la
dernière commande.

### `git n'est pas reconnu`

L'étape 2 n'est pas finie, ou tu es resté dans la même fenêtre. Ferme tous les
Terminaux, ouvre-en un nouveau et vérifie :

```powershell
git --version
```

### Tu veux revenir en arrière

Rien n'est perdu, l'ancienne version est dans l'historique du dossier. Dans le
Terminal, dans ton dossier de macro :

```powershell
git log --oneline
git reset --hard <le numéro de la ligne que tu veux>
```

`settings` n'est jamais concerné par ça non plus.

---

## Questions qu'on pose

**Ça remplace Natro Macro ?** Non. *C'est* Natro Macro, avec des
fonctionnalités en plus. Tout ce que tu sais faire marche pareil.

**Je vais perdre mes réglages ?** Non. `settings` est laissé tranquille par
chaque installation et chaque mise à jour, définitivement.

**Plusieurs comptes ?** Oui, un dossier par compte, comme avant. Refais
l'étape 3 dans chaque dossier.

**Revenir à la version officielle ?** Dans **Git Sync**, mets le dépôt à
`https://github.com/NatroTeam/NatroMacro.git`, Save, puis Update.

**Il me faut un compte GitHub ?** Non.

**On m'a dit de suivre une autre branche que `main` ?** Remplace `main` par son
nom dans les deux dernières commandes de l'étape 3.

---

## Si tu es bloqué

Dis à quelle étape tu en étais et colle ce que la fenêtre a affiché. Le texte
exact compte : les messages ci-dessus sont écrits pour être distingués les uns
des autres.

Les détails de tout ce mécanisme, pour qui les veut, sont dans
[UPDATE-GIT.md](UPDATE-GIT.md) (en anglais).
