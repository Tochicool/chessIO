{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell #-}
module Game.Chess.Polyglot.Book (
  PolyglotBook
, fromByteString
, defaultBook, twic
, readPolyglotFile
, bookPly
, bookPlies
, bookForest
) where

import Control.Arrow
import Control.Monad.Random (Rand)
import qualified Control.Monad.Random as Rand
import Data.Bits
import Data.ByteString (ByteString)
import qualified Data.ByteString.Internal as BS
import qualified Data.ByteString as BS
import Data.FileEmbed
import qualified Data.Vector.Storable as VS
import Data.Tree
import Data.Word
import Foreign.ForeignPtr (plusForeignPtr)
import Foreign.Ptr (castPtr)
import Foreign.Storable
import Game.Chess
import Game.Chess.Polyglot.Hash
import GHC.Ptr
import System.Random (RandomGen)

data BookEntry = BookEntry {
  key :: {-# UNPACK #-} !Word64
, ply :: {-# UNPACK #-} !Ply
, weight :: {-# UNPACK #-} !Word16
, learn :: {-# UNPACK #-} !Word32
} deriving (Eq, Show)

instance Storable BookEntry where
  sizeOf _ = 16
  alignment _ = alignment (undefined :: Word64)
  peek ptr = BookEntry <$> peekBE (castPtr ptr)
                       <*> (Ply <$> peekBE (castPtr ptr `plusPtr` 8))
                       <*> peekBE (castPtr ptr `plusPtr` 10)
                       <*> peekBE (castPtr ptr `plusPtr` 12)
  poke ptr (BookEntry key (Ply ply) weight learn) = do
    pokeBE (castPtr ptr) key
    pokeBE (castPtr ptr `plusPtr` 8) ply
    pokeBE (castPtr ptr `plusPtr` 10) weight
    pokeBE (castPtr ptr `plusPtr` 12) learn

peekBE :: forall a. (Bits a, Num a, Storable a) => Ptr Word8 -> IO a
peekBE ptr = go ptr 0 (sizeOf (undefined :: a)) where
  go _ !x 0 = pure x
  go !p !x !n = peek p >>= \w8 -> 
    go (p `plusPtr` 1) (x `shiftL` 8 .|. fromIntegral w8) (n - 1)

pokeBE :: forall a. (Bits a, Integral a, Num a, Storable a) => Ptr Word8 -> a -> IO ()
pokeBE p x = go x (sizeOf x) where
  go _ 0 = pure ()
  go !x !n = do
    pokeElemOff p (n-1) (fromIntegral x)
    go (x `shiftR` 8) (n-1)

defaultBook, twic :: PolyglotBook
defaultBook = twic
twic = fromByteString $(embedFile "book/twic-9g.bin")

pv :: PolyglotBook -> [Ply]
pv b = head . concatMap paths $ bookForest b startpos

newtype PolyglotBook = Book (VS.Vector BookEntry)

fromByteString :: ByteString -> PolyglotBook
fromByteString bs = Book v where
  v = VS.unsafeFromForeignPtr0 (plusForeignPtr fptr off) (len `div` elemSize)
  (fptr, off, len) = BS.toForeignPtr bs
  elemSize = sizeOf (undefined `asTypeOf` VS.head v)

readPolyglotFile :: FilePath -> IO PolyglotBook
readPolyglotFile = fmap fromByteString . BS.readFile

bookForest :: PolyglotBook -> Position -> Forest Ply
bookForest b p = tree <$> bookPlies b p where
  tree pl = Node pl . bookForest b $ unsafeDoPly p pl

paths :: Tree a -> [[a]]
paths = foldTree f where
  f a [] = [[a]]
  f a xs = (a :) <$> concat xs

bookPly :: RandomGen g => PolyglotBook -> Position -> Maybe (Rand g Ply)
bookPly b pos =
  case findPosition b pos of
    [] -> Nothing
    l -> Just . Rand.fromList $ map (ply &&& fromIntegral . weight) l

bookPlies :: PolyglotBook -> Position -> [Ply]
bookPlies b pos
  | halfMoveClock pos > 150 = []
  | otherwise = ply <$> findPosition b pos

findPosition :: PolyglotBook -> Position -> [BookEntry]
findPosition (Book v) pos =
  VS.toList . VS.takeWhile ((hash ==) . key) $ VS.unsafeDrop (lowerBound hash) v
 where
  hash = hashPosition pos
  lowerBound = bsearch (key . VS.unsafeIndex v) (0, VS.length v - 1)
  bsearch :: (Integral a, Ord b) => (a -> b) -> (a, a) -> b -> a
  bsearch f (lo, hi) x
    | lo >= hi   = lo
    | x <= f mid = bsearch f (lo, mid) x
    | otherwise  = bsearch f (mid + 1, hi) x
   where mid = (lo + hi) `div` 2
