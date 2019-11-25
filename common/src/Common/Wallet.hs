{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternGuards #-}
{-# LANGUAGE TemplateHaskell #-}

module Common.Wallet
  ( PublicKey(..)
  , unsafePublicKey
  , fromPactPublicKey

  , textToKey
  , keyToText
  , parsePublicKey
  , toPactPublicKey
  , KeyPair(..)
  , AccountName(..)
  , AccountBalance(..)
  , Account(..)
  , AccountGuard(..)
  , pactGuardTypeText
  , fromPactGuard
  , accountGuardKeys
  -- * Util
  , throwDecodingErr
  , decodeBase16M
  -- * Balance checks
  , wrapWithBalanceChecks
  , parseWrappedBalanceChecks
  ) where

import qualified Data.ByteString as BS
import Control.Monad.Fail (MonadFail)
import Control.Lens hiding ((.=))
import Control.Monad
import Control.Monad.Except (MonadError, throwError)
import Control.Newtype.Generics    (Newtype (..))
import Data.Aeson
import Data.Aeson.Types (toJSONKeyText)
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.Decimal (Decimal)
import Data.Default
import Data.Map (Map)
import Data.Set (Set)
import Data.Text (Text)
import Data.Traversable (for)
import GHC.Generics (Generic)
import Kadena.SigningApi (AccountName(..), mkAccountName)
import Pact.Compile (compileExps, mkEmptyInfo)
import Pact.Parse
import Pact.Types.ChainId
import Pact.Types.Exp
import Pact.Types.PactValue
import Pact.Types.Pretty
import Pact.Types.Term hiding (PublicKey)
import Pact.Types.Type
import qualified Data.ByteString.Base16 as Base16
import qualified Data.Map as Map
import qualified Data.Set as Set
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import qualified Pact.Types.Term as Pact
import qualified Pact.Types.Type as Pact

import Common.Foundation
import Common.Network (NetworkName)
import Common.Orphans ()

-- | PublicKey with a Pact compatible JSON representation.
newtype PublicKey = PublicKey ByteString
  deriving (Generic, Eq, Ord, Show)

-- | Input must be base16
unsafePublicKey :: ByteString -> PublicKey
unsafePublicKey = PublicKey

fromPactPublicKey :: Pact.PublicKey -> PublicKey
fromPactPublicKey = PublicKey . fst . Base16.decode . Pact._pubKey

toPactPublicKey :: PublicKey -> Pact.PublicKey
toPactPublicKey (PublicKey pk) = Pact.PublicKey $ Base16.encode pk

instance Newtype PublicKey

instance FromJSONKey PublicKey where
  fromJSONKey = PublicKey . fst . Base16.decode . T.encodeUtf8 <$> fromJSONKey

instance ToJSONKey PublicKey where
  toJSONKey = toJSONKeyText keyToText

instance ToJSON PublicKey where
  toEncoding = toEncoding . keyToText
  toJSON = toJSON . keyToText

instance FromJSON PublicKey where
  parseJSON = textToKey <=< parseJSON

-- | Display key in Base16 format, as expected by older Pact versions.
--
--   Despite the name, this function is also used for serializing signatures.
keyToText :: (Newtype key, O key ~ ByteString) => key -> Text
keyToText = T.decodeUtf8 . Base16.encode . unpack

-- | Read a key in Base16 format, as expected by older Pact versions.
--
--   Despite the name, this function is also used for reading signatures.
textToKey
  :: (Newtype key, O key ~ ByteString, Monad m, MonadFail m)
  => Text
  -> m key
textToKey = fmap pack . decodeBase16M . T.encodeUtf8

-- | Decode a Base16 value in a MonadFail monad and fail if there is input that
-- cannot be parsed.
decodeBase16M :: (Monad m, MonadFail m) => ByteString -> m ByteString
decodeBase16M i =
  let
    (r, rest) = Base16.decode i
  in
    if BS.null rest
       then pure r
       else fail "Input was no valid Base16 encoding."

-- | Parse just a public key with some sanity checks applied.
parsePublicKey :: MonadError Text m => Text -> m PublicKey
parsePublicKey = throwDecodingErr . textToKey <=< checkPub . T.strip

throwDecodingErr
  :: MonadError Text m
  => Maybe v
  -> m v
throwDecodingErr = throwNothing $ T.pack "Invalid base16 encoding"
  where
    throwNothing err = maybe (throwError err) pure

checkPub :: MonadError Text m => Text -> m Text
checkPub t = void (throwEmpty t) >> throwWrongLength 64 t
  where
    throwEmpty k =
      if T.null k
         then throwError $ T.pack "Key must not be empty"
         else pure k

-- | Check length of string key representation.
throwWrongLength :: MonadError Text m => Int -> Text -> m Text
throwWrongLength should k =
  if T.length k /= should
     then throwError $ T.pack "Key has unexpected length"
     else pure k


-- | A key consists of a public key and an optional private key.
--
data KeyPair key = KeyPair
  { _keyPair_publicKey  :: PublicKey
  , _keyPair_privateKey :: Maybe key
  } deriving Generic

instance ToJSON key => ToJSON (KeyPair key) where
  toJSON p = object
    [ "public" .= _keyPair_publicKey p
    , "private" .= _keyPair_privateKey p
    ]

instance FromJSON key => FromJSON (KeyPair key) where
  parseJSON = withObject "KeyPair" $ \o -> do
    public <- o .: "public"
    private <- o .: "private"
    pure $ KeyPair
      { _keyPair_publicKey = public
      , _keyPair_privateKey = private
      }

makePactLenses ''KeyPair

-- | Account guards. We split this out here because we are only really
-- interested in keyset guards right now. Someday we might end up replacing this
-- with pact's representation for guards directly.
data AccountGuard
  = AccountGuard_KeySet Pact.KeySet
  -- ^ Keyset guards
  | AccountGuard_Other Pact.GuardType
  -- ^ Other types of guard
  deriving (Show, Generic)

fromPactGuard :: Pact.Guard a -> AccountGuard
fromPactGuard = \case
  Pact.GKeySet ks -> AccountGuard_KeySet ks
  g -> AccountGuard_Other $ Pact.guardTypeOf g

pactGuardTypeText :: Pact.GuardType -> Text
pactGuardTypeText = \case
  Pact.GTyKeySet -> "Keyset"
  Pact.GTyKeySetName -> "Keyset Name"
  Pact.GTyPact -> "Pact"
  Pact.GTyUser -> "User"
  Pact.GTyModule -> "Module"

accountGuardKeys :: AccountGuard -> [PublicKey]
accountGuardKeys = \case
  AccountGuard_KeySet ks -> fromPactPublicKey <$> Pact._ksKeys ks
  _ -> []

instance FromJSON AccountGuard
instance ToJSON AccountGuard

-- | Account balance wrapper
newtype AccountBalance = AccountBalance { unAccountBalance :: Decimal } deriving (Eq, Ord, Num)

-- Via ParsedDecimal
instance ToJSON AccountBalance where
  toJSON = toJSON . ParsedDecimal . unAccountBalance
instance FromJSON AccountBalance where
  parseJSON x = (\(ParsedDecimal d) -> AccountBalance d) <$> parseJSON x

data Account key = Account
  { _account_name :: AccountName
  , _account_key :: KeyPair key
  , _account_chainId :: ChainId
  , _account_network :: NetworkName
  , _account_notes :: Text
  , _account_balance :: Maybe AccountBalance
  , _account_isWalletAccount :: Bool
  -- ^ We also treat this as proof of the account's existence.
  }

instance ToJSON key => ToJSON (Account key) where
  toJSON a = object $ catMaybes
    [ Just $ "name" .= _account_name a
    , Just $ "key" .= _account_key a
    , Just $ "chain" .= _account_chainId a
    , Just $ "network" .= _account_network a
    , Just $ "notes" .= _account_notes a
    , ("balance" .=) <$> _account_balance a
    , Just $ "isWalletAccount" .= _account_isWalletAccount a
    ]

instance FromJSON key => FromJSON (Account key) where
  parseJSON = withObject "Account" $ \o -> do
    name <- o .: "name"
    key <- o .: "key"
    chain <- o .: "chain"
    network <- o .: "network"
    notes <- o .: "notes"
    balance <- o .:? "balance"
    isWalletAccount <- fromMaybe True <$> o .:? "isWalletAccount"
    pure $ Account
      { _account_name = name
      , _account_key = key
      , _account_chainId = chain
      , _account_network = network
      , _account_notes = notes
      , _account_balance = balance
      , _account_isWalletAccount = isWalletAccount
      }


-- | Helper function for compiling pact code to a list of terms
compileCode :: Text -> Either String [Term Name]
compileCode = first show . compileExps mkEmptyInfo <=< parseExprs

-- | Parse the balance checking object into a map of account balance changes and
-- the result from the inner code
parseWrappedBalanceChecks :: PactValue -> Either Text (Map AccountName AccountBalance, PactValue)
parseWrappedBalanceChecks = first ("parseWrappedBalanceChecks: " <>) . \case
  (PObject (ObjectMap obj)) -> do
    let lookupErr k = case Map.lookup (FieldKey k) obj of
          Nothing -> Left $ "Missing key '" <> k <> "' in map: " <> renderCompactText (ObjectMap obj)
          Just v -> pure v
    before <- parseAccountBalances =<< lookupErr "before"
    result <- parseResults =<< lookupErr "results"
    after <- parseAccountBalances =<< lookupErr "after"
    pure (Map.unionWith subtract before after, result)
  v -> Left $ "Unexpected PactValue (expected object): " <> renderCompactText v

-- | Turn the object of account->balance into a map
parseAccountBalances :: PactValue -> Either Text (Map AccountName AccountBalance)
parseAccountBalances = first ("parseAccountBalances: " <>) . \case
  (PObject (ObjectMap obj)) -> do
    m <- for (Map.toAscList obj) $ \(FieldKey accountText, pv) -> do
      bal <- case pv of
        PLiteral (LDecimal d) -> pure d
        t -> Left $ "Unexpected PactValue (expected decimal): " <> renderCompactText t
      acc <- mkAccountName accountText
      pure (acc, AccountBalance bal)
    pure $ Map.fromList m
  v -> Left $ "Unexpected PactValue (expected object): " <> renderCompactText v

-- | Get the last result, as we would under unwrapped deployment.
parseResults :: PactValue -> Either Text PactValue
parseResults = first ("parseResults: " <>) . \case
  PList vec -> maybe (Left "No value returned") Right $ vec ^? _last
  v -> Left $ "Unexpected PactValue (expected list): " <> renderCompactText v

-- | Wrap the code with a let binding to get the balances of the given accounts
-- before and after executing the code.
wrapWithBalanceChecks :: Set AccountName -> Text -> Either String Text
wrapWithBalanceChecks accounts code = wrapped <$ compileCode code
  where
    getBalance :: AccountName -> (FieldKey, Term Name)
    getBalance acc = (FieldKey (unAccountName acc), TApp
      { _tApp = App
        { _appFun = TVar (QName $ QualifiedName "coin" "get-balance" def) def
        , _appArgs = [TLiteral (LString $ unAccountName acc) def]
        , _appInfo = def
        }
      , _tInfo = def
      })
    -- Produce an object from account names to account balances
    accountBalances = TObject
      { _tObject = Pact.Types.Term.Object
        { _oObject = ObjectMap $ Map.fromList $ map getBalance $ Set.toAscList accounts
        , _oObjectType = TyPrim TyDecimal
        , _oKeyOrder = Nothing
        , _oInfo = def
        }
      , _tInfo = def
      }
    -- It would be nice to parse and compile the code and shove it into a
    -- giant 'Term' so we can serialise it, but 'pretty' is not guaranteed to
    -- produce valid pact code. It at least produces bad type sigs and let
    -- bindings.
    -- Thus we build this from a string and use 'pretty' where appropriate.
    -- We do need to make sure the code compiles before splicing it in.
    -- The order of execution is the same as the order of the bound variables.
    wrapped = T.unlines
      [ "(let"
      , "  ((before " <> renderCompactText accountBalances <> ")"
      , "   (results ["
      , code
      , "   ])"
      , "   (after " <> renderCompactText accountBalances <> "))"
      , "   {\"after\": after, \"results\": results, \"before\": before})"
      ]

