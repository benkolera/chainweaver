{-# LANGUAGE DataKinds              #-}
{-# LANGUAGE DeriveGeneric          #-}
{-# LANGUAGE ExtendedDefaultRules   #-}
{-# LANGUAGE FlexibleContexts       #-}
{-# LANGUAGE FlexibleInstances      #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE KindSignatures         #-}
{-# LANGUAGE LambdaCase             #-}
{-# LANGUAGE MultiParamTypeClasses  #-}
{-# LANGUAGE OverloadedStrings      #-}
{-# LANGUAGE QuasiQuotes            #-}
{-# LANGUAGE RecursiveDo            #-}
{-# LANGUAGE ScopedTypeVariables    #-}
{-# LANGUAGE StandaloneDeriving     #-}
{-# LANGUAGE TemplateHaskell        #-}
{-# LANGUAGE TupleSections          #-}
{-# LANGUAGE TypeApplications       #-}
{-# LANGUAGE TypeFamilies           #-}
{-# LANGUAGE GeneralizedNewtypeDeriving           #-}

-- | References that can be rendered as some kind of path (string
-- representation) and parsed again.
--
-- Copyright   :  (C) 2019 Kadena
-- License     :  BSD-style (see the file LICENSE)
--

module Common.RefPath
  ( -- * Types and classes
    -- ** Paths
    RefPath (..)
  , PathSegment
    -- ** Reference parsing
  , RefParser
  , IsRefPath (..)
  , tryParseRef
  , runParseRef
    -- * Handle `RefPath`s
  , parsePath
  , renderPath
  , mkRefPath
    -- * Backports of newer megaparsec:
  , module MPChar
  , anySingle
  ) where

------------------------------------------------------------------------------
import           Control.Arrow        (second, (***))
import qualified Data.List            as L
import           Data.String          (IsString (fromString))
import           Data.Text            (Text)
import qualified Data.Text            as T
import           Data.Void            (Void)
import           Text.Megaparsec      as MP
import           Text.Megaparsec.Char as MPChar (satisfy)
------------------------------------------------------------------------------

-- | A path segment is just a piece of `Text`.
type PathSegment = Text

newtype RefPath = RefPath { unRefPath :: [ PathSegment ] }
 deriving (Monoid, Semigroup, Show, Eq, Ord)


-- | Parser parsing a path.
type RefParser = Parsec Void RefPath


-- | References that can be rendered to and parsed from a `RefPath` should have an instance of this class.
class IsRefPath r where
  -- | Render a reference to a `RefPath`.
  renderRef :: r -> RefPath

  -- | Parse a reference from a `RefPath`.
  parseRef :: RefParser r

-- | Instance for simple path elements consisting of just some `Text`.
instance IsRefPath Text where
  renderRef = mkRefPath
  parseRef = anySingle


-- | Try to parse a ref.
--
--   Same as `try parseRef`
tryParseRef :: IsRefPath r => RefParser r
tryParseRef = MP.try parseRef

-- | Actually run a `RefPath` parser.
runParseRef :: IsRefPath r => RefPath -> Maybe r
runParseRef = MP.parseMaybe parseRef

-- | RefPath separator.
--   We use \ as it won't get percent encoded in url encoding.
pathSepChar :: Char
pathSepChar = '\\'

-- | RefPath separator as Text.
pathSep :: Text
pathSep = T.singleton pathSepChar

-- | Make a `RefPath` singleton from a single `PathSegment`.
mkRefPath :: PathSegment -> RefPath
mkRefPath = RefPath . pure


-- | Split a given `Text` by occurrences of `pathSep`.
parsePath :: Text -> RefPath
parsePath = RefPath . map (unescapeSegment . T.pack . reverse) . splitIt "" . T.unpack
  where
    splitIt :: String -> String -> [String]
    splitIt building (x:xsA@(y:xs))
      -- Not escaped path separation character - do split:
      | x == pathSepChar && y /= pathSepChar = building : splitIt "" xsA
      | x == pathSepChar && y == pathSepChar = splitIt (y:x:building) xs
      | otherwise                            = splitIt (x:building) xsA
    splitIt building (x:[])
      | x == pathSepChar = building : []
      | otherwise = (x:building) : []
    splitIt building []   = building : []

    unescapeSegment = T.replace (pathSep <> pathSep) pathSep

-- | Render a given `RefPath` as Text.
renderPath :: RefPath -> Text
renderPath = T.intercalate pathSep . map escapeSegment . unRefPath
  where
    escapeSegment = T.replace pathSep (pathSep <> pathSep)


-- | Becomes available in a more recent version of megaparsec than what we have
-- currently in nixpkgs:
anySingle :: MonadParsec e s m => m (Token s)
anySingle = satisfy (const True)


instance IsString RefPath where
  fromString = parsePath . T.pack

instance MP.Stream RefPath where
  type Token RefPath = Text
  type Tokens RefPath = RefPath

  tokenToChunk _ = RefPath . pure
  tokensToChunk _  = RefPath
  chunkToTokens _  = unRefPath
  chunkLength _ = length . unRefPath
  chunkEmpty _ = null . unRefPath
  take1_ = fmap (second RefPath) . L.uncons . unRefPath
  takeN_ n (RefPath xs)
    | n <= 0 = Just (RefPath [], RefPath xs)
    | null xs = Nothing
    | otherwise = Just . (RefPath *** RefPath) $ splitAt n xs
  takeWhile_ f = (RefPath *** RefPath) . span f . unRefPath
  advance1 _ p sp = refPathAdvance1 p sp
  advanceN _ p sp (RefPath w) = L.foldl' (refPathAdvance1 p) sp w
  {- showTokens _ = renderPath -}

refPathAdvance1 :: Pos -> SourcePos -> Text -> SourcePos
refPathAdvance1 _ (SourcePos n l c) _ = SourcePos n l (mkPos $ unPos c + 1)
