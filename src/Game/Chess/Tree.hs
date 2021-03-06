module Game.Chess.Tree (
  positionTree, positionForest
, plyTree, plyForest
, pathTree
) where

import Data.List.NonEmpty (NonEmpty, cons)
import Data.Tree ( Tree(Node), Forest, foldTree )
import Game.Chess.Internal

positionTree :: Position -> Tree Position
positionTree pos = Node pos $ positionForest pos

positionForest :: Position -> Forest Position
positionForest pos = positionTree . unsafeDoPly pos <$> legalPlies pos

plyForest :: Position -> Forest Ply
plyForest pos = plyTree pos <$> legalPlies pos

plyTree :: Position -> Ply -> Tree Ply
plyTree pos ply = Node ply . plyForest $ unsafeDoPly pos ply

pathTree :: Tree a -> Tree (NonEmpty a)
pathTree = foldTree $ \a -> Node (pure a) . (fmap . fmap) (cons a)
