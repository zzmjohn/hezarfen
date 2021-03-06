module Hezarfen

import Hezarfen.Prover
import Hezarfen.Simplify
import Hezarfen.FunDefn
import Hezarfen.Hint
import Language.Reflection.Utils

%access public export

forget' : TT -> Elab Raw
forget' t = case forget t of
                 Nothing => fail [TextPart "Couldn't forget type"]
                 Just x => pure x

getCtx : Elab Context
getCtx = Ctx <$> xs <*> pure []
  where
    xs : Elab (List (TTName, Ty))
    xs = do env <- getEnv
            pure $ mapMaybe id $ map (\(n, b) =>
              MkPair n <$> forget (binderTy b)) env

getTy : TTName -> Elab (TTName, Ty)
getTy n = case !(lookupTyExact n) of
  (n, _, ty) => pure (n, !(forget' ty))

add : List TTName -> Elab Context
add xs = (flip Ctx) [] <$> traverse getTy xs

hezarfenExpr' : Context -> Elab ()
hezarfenExpr' c =
  do goal <- forget' (snd !getGoal)
     fill !(reduceLoop !(breakdown False $ Seq (c <+> !getCtx) goal))
     solve

hezarfenExpr : Elab ()
hezarfenExpr = hezarfenExpr' neutral

-- Generate declarations
hezarfenDecl : TTName -> Context -> Elab (FunDefn Raw)
hezarfenDecl n c = case !(lookupTy n) of
  [] => fail [TextPart "No type found for", NamePart n]
  [(_, _, tt)] =>
    do tt' <- normalise !getEnv tt
       -- normalization is necessary to change `Not p` into `p -> Void`, etc
       ty <- forget' tt'
       tm <- breakdown False (Seq (c <+> !getCtx) ty)
       proofTerm <- reduceLoop tm
       definitionize n proofTerm
  _ => fail [TextPart "Ambiguity: multiple types found for", NamePart n]

hezarfen' : TTName -> Context -> Elab ()
hezarfen' n c = defineFunction !(hezarfenDecl n c)

||| Generates a function definition for a previously undefined name.
||| Note that there should already be a type signature for that name.
||| Example usage:
||| ```
||| f : a -> a
||| derive f
||| ```
hezarfen : TTName -> Elab ()
hezarfen n = hezarfen' n neutral

||| Returns reflected proof term directly
hezarfenTT : (shouldReduce : Bool) -> TTName -> Elab TT
hezarfenTT b n =
  do (_, _, ty) <- lookupTyExact n
     pf <- breakdown False (Seq !getCtx !(forget' ty))
     pf' <- (if b then reduceLoop else pure) pf
     env <- getEnv
     fst <$> check env pf'

decl syntax "derive" {n} = %runElab (hezarfen `{n})
decl syntax "derive'" {n} = %runElab (hezarfen' `{n} !(add !getHints))

decl syntax "obtain" {n} "from" [xs] = %runElab (hezarfen' `{n} !(add xs))
decl syntax "obtain'" {n} "from" [xs] =
  %runElab (hezarfen' `{n} !(add (Prelude.List.(++) xs !getHints)))
