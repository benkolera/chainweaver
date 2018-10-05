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
{-# LANGUAGE TypeApplications       #-}
{-# LANGUAGE TypeFamilies           #-}

-- | Definitions common to the whole frontend.
--
--   And commonly used imports.

module Frontend.Foundation
  ( makePactLenses
  , ReflexValue
  , module Data.Maybe
  , module Reflex.Extended
  , module Reflex.Network.Extended
  , module Data.Semigroup
  , module Data.Foldable
  ) where

import           Control.Lens
import           Data.Foldable
import           Data.Semigroup
import           Language.Haskell.TH        (DecsQ)
import           Language.Haskell.TH.Syntax (Name)
import           Reflex.Extended
import           Reflex.Network.Extended

import           Data.Maybe

-- | Lenses in this project should be generated by means of this function.
--
--   We generate lazy classy lenses. Classes make the export lists less tedious
--   and allows for generic code, which will come in handy when the project
--   grows.
--
--   We want lazy lenses so we can uses lenses also in recursive definitions.

makePactLenses :: Name -> DecsQ
makePactLenses =
  makeLensesWith
    ( classyRules         -- So we can use them in recursive definitions:
        & generateLazyPatterns .~ True
        & createClass .~ True
    )



-- | Re-use data constructors more flexibly.
type family ReflexValue (f :: * -> *) x where
    ReflexValue (Dynamic t) x = Dynamic t x

    ReflexValue Identity x = x

    ReflexValue (Behavior t) x = Behavior t x

    ReflexValue (Event t) x = Event t x
