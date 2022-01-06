module NOM.State.Tree (
  ForestUpdate (..),
  trimForest,
  replaceDuplicates,
  updateForest,
  sortForest,
  aggregateTree,
) where

import qualified Data.Set as Set
import Data.Tree (Forest, Tree (Node, subForest), rootLabel)
import Relude

subTrees :: Ord a => Tree a -> Set (Tree a)
subTrees t = Set.insert t (foldMap subTrees (subForest t))

data ForestUpdate a = ForestUpdate
  { match :: a -> Bool
  , isChild :: a -> Bool
  , isParent :: a -> Bool
  , update :: a -> a
  , def :: a
   }

updateForest :: forall a. Ord a => ForestUpdate a -> Forest a -> Forest a
updateForest ForestUpdate{..} forest =
  if updated
    then forest'
    else insertedIntoForest
 where
  (updated, forest') = updateIfPresent forest
  updateIfPresent :: Forest a -> (Bool, Forest a)
  updateIfPresent f = (or $ fst <$> f', snd <$> f')
   where
    f' = updateTree <$> f
    updateTree (Node label (updateIfPresent -> (subMatch, subForest))) =
      (match label || subMatch, Node (if match label then update label else label) subForest)

  insertedIntoForest :: Forest a
  insertedIntoForest = appendWhereMatching (Node def children) noChildren
   where
    noChildren = filter (not . isChild . rootLabel) forest
    children = filter (isChild . rootLabel) (toList (foldMap subTrees forest))

  appendWhereMatching :: Tree a -> Forest a -> Forest a
  appendWhereMatching treeToInsert = uncurry prependIfNoMatch . go
   where
    prependIfNoMatch :: Bool -> Forest a -> Forest a
    prependIfNoMatch found = if found then id else (treeToInsert :)
    go :: Forest a -> (Bool, Forest a)
    go (fmap goTree -> f) = (or $ fst <$> f, snd <$> f)
    goTree :: Tree a -> (Bool, Tree a)
    goTree (Node label subForest) =
      let matches = isParent label
          (subMatch, subForest') = go subForest
       in (matches || subMatch, Node label ((if matches then (treeToInsert :) else id) subForest'))

aggregateTree :: Monoid b => (a -> b) -> Tree a -> Tree (a, b)
aggregateTree summary (Node x (fmap (aggregateTree summary) -> xs)) =
  Node (x, summary x <> foldMap (snd . rootLabel) xs) xs

trimForest :: (a -> Bool) -> Forest a -> Forest a
trimForest keep = go
 where
    go = mapMaybe keepTree
    keepTree (Node label (go -> subForest)) = if keep label || not (null subForest) then Just (Node label subForest) else Nothing

sortForest :: Ord c => (Tree a -> c) -> Forest a -> Forest a
sortForest order = go
 where
  go = fmap sortTree . sort'
  sortTree (Node x c) = Node x (go c)
  sort' = sortOn order

{-
mergeForest :: Eq a => NonEmpty (Tree a b) -> NonEmpty (Tree a b)
mergeForest (x :| xs) = foldl' (flip mergeIntoForest . toList) (pure x) xs

mergeIntoForest :: Eq a => Tree a b -> [Tree a b] -> NonEmpty (Tree a b)
mergeIntoForest x [] = pure x
mergeIntoForest x (y : ys) = maybe (y :| toList (mergeIntoForest x ys)) (:| ys) (mergeTrees x y)

mergeTrees :: Eq a => Tree a b -> Tree a b -> Maybe (Tree a b)
mergeTrees (Node x xs) (Node y ys) | x == y = Just (Node x (mergeForest (xs <> ys)))
mergeTrees _ _ = Nothing

-- >>> mergeForest $ (Node 1 (pure (Leaf "a"))) :| [Node 3 (pure (Leaf "b")), Node 3 (pure (Leaf "c"))]
-- Node 1 (Leaf "a" :| []) :| [Node 3 (Leaf "b" :| [Leaf "c"])]

reverseForest :: forall a b. (Ord a, Ord b) => (a -> b) -> Map b (Set b) -> NonEmpty a -> NonEmpty (Tree b a)
reverseForest f parents = (start =<<)
 where
  start :: a -> NonEmpty (Tree b a)
  start x = reverseTree (f x) (pure (Leaf x))
  reverseTree :: b -> NonEmpty (Tree b a) -> NonEmpty (Tree b a)
  reverseTree x t = case lookup x of
    Nothing -> t
    Just pars -> (\y -> reverseTree y (pure $ Node y t)) =<< pars
  lookup x = nonEmpty . toList =<< Map.lookup x parents
-}

replaceDuplicates :: forall a b. Ord a => (a -> b) -> Forest a -> Forest (Either a b)
replaceDuplicates link = snd . filterList mempty
 where
  filterList :: Set (Tree a) -> Forest a -> (Set (Tree a), Forest (Either a b))
  filterList seen [] = (seen, [])
  filterList seen (x : xs) =
    let (seen', x') = if Set.member x seen then (seen, substitute x) else filterTree seen x
        (seen'', xs') = filterList (Set.insert x seen') xs
     in (seen'', x' : xs')
  filterTree :: Set (Tree a) -> Tree a -> (Set (Tree a), Tree (Either a b))
  filterTree seen (Node x t) = second (Node (Left x)) (filterList seen t)
  substitute :: Tree a -> Tree (Either a b)
  substitute (Node x _) = Node (Right (link x)) []
