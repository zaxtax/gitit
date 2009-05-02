{-
Copyright (C) 2009 John MacFarlane <jgm@berkeley.edu>

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
-}

{- | Interface for plugins.

A plugin is a Haskell module that is dynamically loaded by gitit.

There are three kinds of plugins: 'PageTransform's,
'PreParseTransform's, and 'PreCommitTransform's. These plugins differ
chiefly in where they are applied. 'PreCommitTransform' plugins are
applied just before changes to a page are saved and may transform
the raw source that is saved. 'PreParseTransform' plugins are applied
when a page is viewed and may alter the raw page source before it
is parsed as a 'Pandoc' document. Finally, 'PageTransform' plugins
modify the 'Pandoc' document that results after a page's source is
parsed, but before it is converted to HTML:

>                 +--------------------------+
>                 | edited text from browser |
>                 +--------------------------+
>                              ||         <----  PreCommitTransform plugins
>                              \/
>                              ||         <----  saved to repository
>                              \/
>              +---------------------------------+
>              | raw page source from repository |
>              +---------------------------------+
>                              ||         <----  PreParseTransform plugins
>                              \/
>                              ||         <----  markdown or RST reader
>                              \/
>                     +-----------------+
>                     | Pandoc document |
>                     +-----------------+
>                              ||         <---- PageTransform plugins
>                              \/
>                   +---------------------+
>                   | new Pandoc document |
>                   +---------------------+
>                              ||         <---- HTML writer
>                              \/
>                   +----------------------+
>                   | HTML version of page |
>                   +----------------------+

Note that 'PreParseTransform' and 'PageTransform' plugins do not alter
the page source stored in the repository. They only affect what is
visible on the website.  Only 'PreCommitTransform' plugins can
alter what is stored in the repository.

Note also that 'PreParseTransform' and 'PageTransform' plugins will
not be run when the cached version of a page is used.  Plugins can
use the 'doNotCache' command to prevent a page from being cached,
if their behavior is sensitive to things that might change from
one time to another (such as the time or currently logged-in user).

You can use the helper functions 'mkPageTransform' and 'mkPageTransformM'
to create 'PageTransform' plugins from a transformation of any
of the basic types used by Pandoc (for example, 'Inline', 'Block',
'[Inline]', even 'String'). Here is a simple (if silly) example:

> -- DeprofanizerPlugin.hs
> module DeprofanizerPlugin (plugin) where
>
> -- This plugin replaces profane words with "XXXXX".
>
> import Gitit.Interface
> import Data.Char (toLower)
>
> plugin :: Plugin
> plugin = mkPageTransform deprofanize
>
> deprofanize :: Inline -> Inline
> deprofanize (Str x) | isBadWord x = Str "XXXXX"
> deprofanize x                     = x
>
> isBadWord :: String -> Bool
> isBadWord x = (map toLower x) `elem` ["darn", "blasted", "stinker"]
> -- there are more, but this is a family program

Further examples can be found in the @plugins@ directory in
the source distribution.  If you have installed gitit using Cabal,
you can also find them in the directory
@CABALDIR/share/gitit-X.Y.Z/plugins@, where @CABALDIR@ is the cabal
install directory.

-}

module Gitit.Interface ( Config(..)
                       , PluginM
                       , module Text.Pandoc.Definition
                       , Plugin(..)
                       , inlinesToURL
                       , inlinesToString
                       , mkPageTransform
                       , mkPageTransformM
                       , askConfig
                       , askUsername
                       , doNotCache
                       , getContext
                       , modifyContext
                       , Context(..)
                       , PageType(..)
                       , PageLayout(..)
                       , liftIO
                       )
where
import Text.Pandoc.Definition
import Data.Data
import Gitit.Types
import Gitit.ContentTransformer
import Control.Monad.Reader (ask)
import Control.Monad (liftM)
import Control.Monad.Trans (liftIO)

askConfig :: PluginM Config
askConfig = liftM fst ask

askUsername :: PluginM (Maybe String)
askUsername = liftM snd ask

doNotCache :: PluginM ()
doNotCache = modifyContext (\ctx -> ctx{ ctxCacheable = False })

-- | Lifts a function from @a -> a@ (for example, @Inline -> Inline@,
-- @Block -> Block@, @[Inline] -> [Inline]@, or @String -> String@)
-- to a 'PageTransform' plugin.
mkPageTransform :: Data a => (a -> a) -> Plugin
mkPageTransform fn = PageTransform $ return . processWith fn

-- | Monadic version of 'mkPageTransform'.
-- Lifts a function from @a -> Web a@ to a 'PageTransform' plugin.
mkPageTransformM :: Data a => (a -> PluginM a) -> Plugin
mkPageTransformM =  PageTransform . processWithM

