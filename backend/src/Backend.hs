{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Backend where

import           Control.Concurrent.Async (mapConcurrently_, withAsync)
import           Control.Monad.Identity   (Identity (..))
import           Control.Monad.IO.Class   (liftIO)
import           Data.Dependent.Sum       (DSum ((:=>)))
import           Data.Foldable            (traverse_)
import           Data.List                (foldl')
import           Data.Monoid              ((<>))
import qualified Data.Text                as T
import qualified Data.Text.IO             as T
import qualified Obelisk.Backend          as Ob
import qualified Obelisk.ExecutableConfig as Conf
import           Obelisk.Route            (R)
import qualified Pact.Server.Server       as Pact
import           Snap                     (Snap)
import           Snap.Util.FileServe      (serveFile)
import           System.Directory         (createDirectoryIfMissing, canonicalizePath)
import           System.FilePath          ((</>))

import           Common.Api
import           Common.Route


-- | Configuration for pact instances.
data PactInstanceConfig = PactInstanceConfig
  { _pic_conf :: FilePath -- ^ Config file path
  , _pic_log  :: FilePath -- ^ Persist and logging directory
  , _pic_num  :: Int      -- ^ What instance number do we have?
  }

-- | Directory for storing the configuration for our development pact instances.
pactConfigDir :: FilePath
pactConfigDir = "/var/tmp/pact-conf"

-- | Root directory for pact logging directories.
pactLogBaseDir :: FilePath
pactLogBaseDir = "/var/tmp/pact-log"

-- | Pact instance configurations
pactConfigs :: [PactInstanceConfig]
pactConfigs = map mkConfig [1 .. numPactInstances]
  where
    mkConfig num = PactInstanceConfig
      { _pic_conf = pactConfigDir  </> mkFileName num <> ".yaml"
      , _pic_log  = pactLogBaseDir </> mkFileName num
      , _pic_num  = num
      }
    mkFileName num = "pact-" <> show num

backend :: Ob.Backend BackendRoute FrontendRoute
backend = Ob.Backend
    { Ob._backend_run = \serve -> do

        mRuntimeConfig <- getRuntimeConfigPath
        case mRuntimeConfig of
          -- Devel mode:
          Nothing
            -> withDevelPactInstances serve
          -- Production mode:
          Just p -> do
           serve $ serveBackendRoute p

    , Ob._backend_routeEncoder = backendRouteEncoder
    }
  where
    getRuntimeConfigPath :: IO (Maybe FilePath)
    getRuntimeConfigPath =
      fmap (T.unpack . T.strip) <$> Conf.get "config/backend/runtime-config-path"

    withDevelPactInstances serve = do
      traverse_ (createDirectoryIfMissing True . _pic_log) pactConfigs
      createDirectoryIfMissing False $ pactConfigDir
      traverse_ writePactConfig pactConfigs

      let servePact = Pact.serve . _pic_conf

      withAsync (mapConcurrently_ servePact pactConfigs) $ \_ ->
          serve (const $ pure ())

    serveBackendRoute :: FilePath -> R BackendRoute -> Snap ()
    serveBackendRoute dynConfigs = \case
      BackendRoute_DynConfigs :=> Identity ps
        -> do
          let
            strSegs = map T.unpack ps
            p = foldl' (</>) dynConfigs strSegs
          pNorm <- liftIO $ canonicalizePath p
          baseNorm <- liftIO $ canonicalizePath dynConfigs
          -- Sanity check: Make sure we are serving a file in the target directory.
          if length baseNorm < length pNorm
             then serveFile p
             else pure () -- We should probably throw an error instead, I guess.

      _ -> pure ()

writePactConfig :: PactInstanceConfig -> IO ()
writePactConfig cfg =
 T.writeFile (_pic_conf cfg) $ T.unlines
   [ "port: "       <> getPactInstancePort (_pic_num cfg)
   , "logDir: "     <> (T.pack $ _pic_log cfg)
   , "persistDir: " <> (T.pack $ _pic_log cfg)
   , "pragmas: []"
   , "verbose: True"
   ]

