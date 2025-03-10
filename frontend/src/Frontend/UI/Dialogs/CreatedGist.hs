{-# LANGUAGE ConstraintKinds       #-}
{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE ExtendedDefaultRules  #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE KindSignatures        #-}
{-# LANGUAGE LambdaCase            #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE QuasiQuotes           #-}
{-# LANGUAGE RecursiveDo           #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE StandaloneDeriving    #-}
{-# LANGUAGE TemplateHaskell       #-}
{-# LANGUAGE TupleSections         #-}
{-# LANGUAGE TypeApplications      #-}

-- | Confirmation dialog for creating a GIST allowing setting of name and description.
-- Copyright   :  (C) 2018 Kadena
-- License     :  BSD-style (see the file LICENSE)
module Frontend.UI.Dialogs.CreatedGist
  ( uiCreatedGist
  , HasUICreatedGistModelCfg
  ) where

------------------------------------------------------------------------------
import           Control.Lens
import           Control.Monad               (void)
import           Reflex
import           Reflex.Dom
------------------------------------------------------------------------------
import           Obelisk.Generated.Static
import           Obelisk.Route.Frontend
------------------------------------------------------------------------------
import           Common.Api                  (getConfigRoute)
import           Common.Route
import           Frontend.Foundation         hiding (Arg)
import           Frontend.GistStore          (GistRef)
import           Frontend.UI.Modal
import           Frontend.UI.Widgets
import           Frontend.UI.Widgets.Helpers (imgWithAltCls)
------------------------------------------------------------------------------

type HasUICreatedGistModelCfg mConf t = (Monoid mConf)


-- | Dialog showing created Gist URL after it has been created.
--
--   Ask user for name and description for the gist.
uiCreatedGist
  :: forall t m mConf
  . ( HasUICreatedGistModelCfg mConf t, RouteToUrl (R FrontendRoute) m
    , Monad m
    , DomBuilder t m
    , PerformEvent t m
    , MonadJSM (Performable m)
    , PostBuild t m
    , HasConfigs m
    )
  => GistRef -- ^ The rendered route of the Gist (only the path).
  -> Event t () -> m (mConf, Event t ())
uiCreatedGist gistRef _onClose = do
    onClose <- modalHeader $ text "Gist Created"
    modalMain $ do
      modalBody $ do
        divClass "segment modal__filler" $ do
          divClass "modal__filler-horizontal-center-box" $
            imgWithAltCls "modal__filler-img" (static @"img/Octocat.jpg") "Github logo" blank

          elClass "h2" "heading heading_type_h2" $ text "Find your link below:"
          divClass "group" $ do


            elClass "ol" "table" $ do

              elClass "li" "table__row table__row_type_primary table__row_type_silent" $ do

                baseUrlText <- getConfigRoute
                routeToUrl <- askRouteToUrl
                let route = routeToUrl $ FrontendRoute_Gist :/ [gistRef]

                elClass "td" "table__text-cell table__cell_size_flex" $
                  text $ baseUrlText <> route

                void $ elClass "td" "table__last-cell table__cell_size_flex" $
                  copyButton copyBtnCfg $ pure $ baseUrlText <> route

      modalFooter $ do
        onConfirm <- confirmButton def "Ok"
        pure (mempty, leftmost [onClose, onConfirm])
  where
    copyBtnCfg = def & uiButtonCfg_class .~ "button_type_secondary table__action-button"
