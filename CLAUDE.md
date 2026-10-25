# Swouf – règles du projet

## Le projet
- Swouf est une app web pour chiens (PWA), en ligne via GitHub Pages : dépôt `swoof-app/swoof-app.github.io`.
- Travailler **uniquement** sur ce projet. Ne toucher à aucun autre projet ni dépôt.
- L'app tient dans `index.html` (+ `sw.js`, `manifest.json`, images). Données et connexion : Supabase (plan gratuit), projet `wfwjrgwgtyiiavpsycns`.
- En cours : l'**Espace refuge** (refuges agréés qui publient leurs chiens) et l'**espace administration** (réservé à swouf.app@gmail.com).

## Branches
- Branche de travail : **`espace-refuge`**.
- **Ne jamais toucher à `main`** (c'est l'app en ligne) sans l'accord explicite de Julie.
- Ne rien envoyer sur GitHub (push) sans son accord.

## Façon de travailler avec Julie
- Julie n'est pas développeuse : expliquer chaque étape simplement, **une à la fois**, et attendre sa confirmation avant la suivante.
- **Toujours prévenir AVANT** tout ce qui pourrait devenir payant (Supabase, GitHub, services externes…).
- Indiquer à chaque message où on en est dans la liste de travail numérotée.

## Sécurité
- Ne jamais demander ni écrire la clé `service_role` / `secret` de Supabase. Seules l'adresse du projet et la clé publique (publishable/anon) vont dans le code.
- Row Level Security partout : chaque refuge ne voit et ne modifie que ses propres chiens ; seul swouf.app@gmail.com accède à l'administration.
- Refuges non validés ou suspendus : rien de publié. Données « test » : jamais visibles dans l'app publique.

## Langue et ton
- Français pour l'instant ; textes organisés pour ajouter l'anglais et le néerlandais (comme dans l'app : `tr(fr, en, nl)`).
- **Vouvoiement** pour les refuges (Espace refuge).
- **Tutoiement** pour les utilisateurs de l'app Swouf.
- Ne pas écrire « gratuit » sur l'Espace refuge.

## Couleurs (celles de l'app, rien d'inventé)
| Rôle | Couleur |
|---|---|
| Corail (signature) : boutons principaux, icônes | `#E86A4F` |
| Corail foncé : liens et textes corail sur fond clair | `#B8452D` |
| Corail clair : fonds doux, petits boutons | `#FBE1D8` |
| Brun encre : textes, titres (jamais de noir pur) | `#2A1E18` |
| Brun doux : textes secondaires | `#6B5549` |
| Crème : fond des pages | `#FFF4E6` |
| Blanc cassé : cartes et cadres | `#FFFDF9` |
| Beige bordure : contours des cadres et champs | `#EBDAC6` |
| Message succès | `#2F7A45` sur `#DDF0E0` |
| Message attention | `#9A5A0B` sur `#FCEBD0` |

## Polices
- Google Fonts : **Fredoka** pour les titres et boutons, **Nunito** pour les textes.
- Utiliser le vrai logo de Swouf (fichiers du projet), jamais un logo inventé.
- Interface simple, chaleureuse, parfaite sur téléphone.

## Matching
- Les critères de matching des chiens de refuge reprennent exactement les critères et valeurs utilisés par le quiz pour noter les races (`BREEDS` / `QUESTIONS` / `compute()` dans `index.html`), pour une comparaison directe.
