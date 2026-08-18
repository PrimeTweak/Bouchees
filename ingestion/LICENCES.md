# Licences des sources — vérifié le 17 août 2026

Verdict court : **les deux API grand public envisagées interdisent notre modèle
de stockage.** Le pipeline reste agnostique de la source; le corpus grandit par
du contenu qu'on a le droit de garder.

## Spoonacular (spoonacular.com/food-api/terms)

- Interdiction de copier ou stocker les données de l'API, **y compris les
  données dérivées ou transformées** — ce qui décrit exactement notre
  normalisation vers le catalogue canonique.
- Cache limité à 1 heure, et seulement avec permission écrite préalable.
- À la fin de l'abonnement : suppression de toutes les données obtenues.
- Conclusion : incompatible avec l'architecture sans entente écrite spécifique.

## Edamam (developer.edamam.com, edamam.com/terms/api)

- Requêtes déclenchées par un humain seulement; interdiction de collecter,
  moissonner ou sauvegarder les données; affichage réservé à l'utilisateur qui
  a fait la requête.
- Cache permis seulement pour quelques macronutriments, dans le compte de
  l'utilisateur final, derrière un mot de passe.
- Badge d'attribution obligatoire sur toute utilisation.
- Le contenu des recettes appartient de toute façon aux sites d'origine
  (Edamam est un index) — donc même une entente ne réglerait pas les droits.
- Conclusion : incompatible avec l'architecture.

## Pourquoi on ne « streame » pas au lieu de stocker

Le modèle « appeler l'API en direct et afficher sans stocker » serait conforme
aux conditions, mais il est **incompatible avec notre modèle de sécurité** :
une recette qu'on ne peut pas stocker ne peut pas passer par la quarantaine,
la curation d'âge minimal et la re-dérivation des allergènes. Une recette non
curée est une recette qu'on ne montre pas.

## Sources compatibles avec l'architecture

1. **Contenu maison** : rédaction assistée par IA, validée par un humain,
   stockée et versionnée (c'est le corpus témoin actuel).
2. **Sources sous licence libre** (domaine public, Creative Commons permettant
   la modification) — l'adaptateur `generique` les reçoit telles quelles.
3. **Entente de licence directe** avec un éditeur de contenu (le champ
   `licence` de chaque source trace ce droit).

Les fichiers de `ingestion/sources/` sont des **gabarits rédigés par l'équipe**
conformes aux schémas réels (spoonacular, TheMealDB, générique) : ils prouvent
les adaptateurs sans stocker de données de tiers.
