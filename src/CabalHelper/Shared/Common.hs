-- Copyright (C) 2015  Daniel Gröber <dxld ÄT darkboxed DOT org>
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU Affero General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU Affero General Public License for more details.
--
-- You should have received a copy of the GNU Affero General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.

{-|
Module      : CabalHelper.Shared.Common
Description : Shared utility functions
License     : AGPL-3
-}

{-# LANGUAGE DeriveDataTypeable, OverloadedStrings #-}
module CabalHelper.Shared.Common where

import Control.Applicative
import Control.Exception as E
import Control.Monad
import Data.List
import Data.Maybe
import Data.Version
import Data.Typeable
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BS8
import System.Environment
import System.IO
import qualified System.Info
import System.Exit
import System.Directory
import System.FilePath
import Text.ParserCombinators.ReadP
import Prelude

data Panic = Panic String deriving (Typeable, Show)
instance Exception Panic

panic :: String -> a
panic msg = throw $ Panic msg

panicIO :: String -> IO a
panicIO msg = throwIO $ Panic msg

handlePanic :: IO a -> IO a
handlePanic action =
    action `E.catch` \(Panic msg) -> errMsg msg >> exitFailure

errMsg :: String -> IO ()
errMsg str = do
  prog <- getProgName
  hPutStrLn stderr $ prog ++ ": " ++ str

-- | @getCabalConfigHeader "dist/setup-config"@ returns the cabal version and
-- compiler version
getCabalConfigHeader :: FilePath -> IO (Maybe (Version, (ByteString, Version)))
getCabalConfigHeader file = bracket (openFile file ReadMode) hClose $ \h -> do
  parseHeader <$> BS.hGetLine h

parseHeader :: ByteString -> Maybe (Version, (ByteString, Version))
parseHeader header = case BS8.words header of
  ["Saved", "package", "config", "for", _pkgId ,
   "written", "by", cabalId,
   "using", compId]
    -> liftM2 (,) (snd <$> parsePkgId cabalId) (parsePkgId compId)
  _ -> Nothing

parsePkgId :: ByteString -> Maybe (ByteString, Version)
parsePkgId bs =
    case BS8.split '-' bs of
      [pkg, vers] -> Just (pkg, parseVer $ BS8.unpack vers)
      _ -> Nothing

parseVer :: String -> Version
parseVer vers = runReadP parseVersion vers

majorVer :: Version -> Version
majorVer (Version b _) = Version (take 2 b) []

sameMajorVersionAs :: Version -> Version -> Bool
sameMajorVersionAs a b = majorVer a == majorVer b

runReadP :: ReadP t -> String -> t
runReadP p i = case filter ((=="") . snd) $ readP_to_S p i of
                 (a,""):[] -> a
                 _ -> error $ "Error parsing: " ++ show i

appCacheDir :: IO FilePath
appCacheDir =
    (</> "cabal-helper") <$> getEnvDefault "XDG_CACHE_HOME" (homeRel cache)
 where
    -- for GHC 7.4
    lookupEnv' var = do env <- getEnvironment; return (lookup var env)
    getEnvDefault var def = lookupEnv' var >>= \m -> case m of Nothing -> def; Just x -> return x
    homeRel path = (</> path) <$> getHomeDirectory
    cache =
        case System.Info.os of
          "mingw32" -> windowsCache
          _         -> unixCache

    windowsCache = "Local Settings" </> "Cache"
    unixCache = ".cache"

isCabalFile :: FilePath -> Bool
isCabalFile f = takeExtension' f == ".cabal"

takeExtension' :: FilePath -> String
takeExtension' p =
    if takeFileName p == takeExtension p
      then "" -- just ".cabal" is not a valid cabal file
      else takeExtension p

replace :: String -> String -> String -> String
replace n r hs' = go "" hs'
 where
   go acc h
       | take (length n) h == n =
           reverse acc ++ r ++ drop (length n) h
   go acc (h:hs) = go (h:acc) hs
   go acc [] = reverse acc
