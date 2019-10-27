module TypedLambdaCalcInitial.Interpreters where

import Control.Monad.Reader
import Data.List

import Debug.Trace

import TypedLambdaCalcInitial.Types


----------------------
--- Pretty Printer ---
----------------------

primeSieve :: [Integer]
primeSieve = 2 : [i | i <- [3..], and [rem i p > 0 | p <- takeWhile (\p -> p^(2 :: Integer) <= i) primeSieve]]

appendPrime :: String -> Int -> String
appendPrime str i = str ++ show (primeSieve !! i)

pickFreshName :: Bindings -> String -> (Bindings, String)
pickFreshName ctx str = f ctx str 0
  where f :: Bindings -> String -> Int -> (Bindings, String)
        f ctx' str' i = let res = find (== str') ctx'
                        in case res of
                             Nothing -> (str' : ctx', str')
                             Just _  -> let str'' = appendPrime str i
                                        in f ctx' str'' (i+1)

-- TODO: Bug fix. This blows up on `> (\x:Nat. S x)`
showNat :: Term -> String
showNat nat = show $ f nat
  where
    f :: Term -> Int
    f Z = 0
    f (S n) = 1 + f n
    f _ = undefined

-- TODO: Implement `Show Term` Instance
pretty :: Term -> String
pretty t = runReader (f t) []
  where
    f :: Term -> Reader Bindings String
    f (App t1 t2) = do
      t1' <- f t1
      t2' <- f t2
      pure $ "(" ++ t1' ++ " " ++ t2' ++ ")"
    f (Var x) = ask >>= \ctx -> pure $ ctx !! x
    f (Abs x ty t1) = do
      ctx <- ask
      let (ctx', x') = pickFreshName ctx x
      t1' <- local (const ctx') (f t1)
      pure $ "(λ " ++ x' ++ " : " ++ show ty ++ ". " ++ t1' ++ ")"
    f Tru = pure "True"
    f Fls = pure "False"
    f Unit = pure "Unit"
    f (As (Var i) ty) = do
      ctx <- ask
      let var = ctx !! i
      pure $ "(" ++ var ++ " as " ++ show ty ++ ")"
    f (As t1 ty) = f t1 >>= \t1' -> pure $ "(" ++ t1' ++ "as" ++ show ty ++ ")"
    f Z = pure "0"
    f s@(S _) = pure $ show s
    f (If t1 t2 t3) = do
      t1' <- f t1
      t2' <- f t2
      t3' <- f t3
      pure $ "If " ++ t1' ++ " then " ++ t2' ++ " else " ++ t3'
    f (Case l m v n) = do
      l' <- f l
      m' <- f m
      n' <- f n
      pure $ "case "   ++ l' ++ " of: " ++
             "Z => " ++ m' ++ " | "  ++
             "S "    ++ v  ++ " => " ++ n'
    f (Let x t1 t2) = do
      t1' <- f t1
      t2' <- f t2
      pure $ "let " ++ x ++ " = " ++ t1' ++ " in " ++ t2'


-------------
--- Depth ---
-------------

-- TOD0:
depth :: Term -> Integer
depth (Var _) = 0
depth (Abs _ _ t1) = 1 + depth t1
depth (App t1 t2) = depth t1 + depth t2
depth Tru = 0
depth Fls = 0
depth Z = 0
depth Unit = 0
depth (As t1 _) = depth t1
depth (S t) = depth t
depth (If t1 t2 t3) = depth t1 + depth t2 + depth t3
depth (Case l m _ n) = depth l + depth m + depth n
depth (Let _ t1 t2) = 1 + depth t1 + depth t2


------------
--- Size ---
------------

-- TODO:
size :: Term -> Integer
size = undefined


------------------
--- Evaluation ---
------------------

shift :: DeBruijn -> Term -> Term
shift target t = f 0 t
  where
    f :: Int -> Term -> Term
    f i (Var x) = if x >= i then Var (x + target) else Var x
    f i (Abs v ty t1) = Abs v ty $ f (i + 1) t1
    f i (App t1 t2) = App (f i t1) (f i t2)
    f _ Tru = Tru
    f _ Fls = Fls
    f _ Unit = Unit
    f _ Z = Z
    f i (S t1) = S (f i t1)
    f i (If t1 t2 t3) = If (f i t1) (f i t2) (f i t3)
    f i (Case l m x n) = Case (f i l) (f i m) x (f (i + 1) n)
    f i (As t1 ty) = As (f i t1) ty
    f i (Let v t1 t2) = Let v (f i t1) (f (i + 1) t2)

{-
Substitution Rules:
1. [j -> s]k       = if j == k then s else k
2. [j -> s](\.t1)  = \.[j+1 -> ↑¹(s)]t1
2. [j -> s](t1 t2) = ([j -> s]t1 [j -> s]t2)

[1 -> 2]0 = 0
[1 -> 2]1 = 2
[1 -> 2]\.0 = \.0
[1 -> 2]\.1 = \.2
-}

subst :: DeBruijn -> Term -> Term -> Term
subst j s t = f 0 s t
  where f :: DeBruijn -> Term -> Term -> Term
        f c s' (Var x) = if x == j + c then s' else Var x
        f c s' (Abs v ty t') = Abs v ty (f (c+1) (shift c s') t')
        f c s' (App t1 t2) = App (f c s' t1) (f c s' t2)
        f _ _ Tru = Tru
        f _ _ Fls = Fls
        f _ _ Unit = Unit
        f c s' (If t1 t2 t3) = If (f c s' t1) (f c s' t2) (f c s' t3)
        f _ _ Z = Z
        f c s' (S t1) = S (f c s' t1)
        f c s' (Case l m x n) = Case (f c s' l)
                                     (f c s' m)
                                     x
                                     (f (c+1) (shift c s') n)
        f c s' (As t1 ty) = As (f c s' t1) ty
        f c s' (Let v t1 t2) = Let v (f c s' t1) (f (c+1) (shift c s') t2)

substTop :: Term -> Term -> Term
substTop s t = shift (-1) (subst 0 (shift 1 s) t)

isVal :: Context -> Term -> Bool
isVal _ (Abs _ _ _) = True
isVal _ Tru         = True
isVal _ Fls         = True
isVal _ Z           = True
isVal _ Unit        = True
isVal c (S n)       = isVal c n
isVal c (As t1 _)   = isVal c t1
isVal _ _           = False

-- Single Step Evaluation Function
singleEval :: Context -> Term -> Maybe Term
singleEval ctx t =
  case t of
    (App (Abs _ _ t12) v2) | isVal ctx v2 -> pure $ substTop v2 t12
    (App v1@(Abs _ _ _) t2) -> App v1 <$> singleEval ctx t2
    (App t1 t2) -> singleEval ctx t1 >>= \t1' -> pure $ App t1' t2
    (If Tru t2 _) -> pure t2
    (If Fls _ t3) -> pure t3
    (If t1 t2 t3) ->
      singleEval ctx t1 >>= \t1' -> pure $ If t1' t2 t3
    (S n) | not $ isVal ctx n-> S <$> singleEval ctx n
    (Case Z m _ _) -> pure m
    (Case (S l) _ _ n) | isVal ctx l -> pure $ substTop l n
    (Case l m x n) ->
      singleEval ctx l >>= \l' -> pure $ Case l' m x n
    (As t1 _) -> pure t1
    (Let _ v1 t2) | isVal ctx v1 -> pure $ substTop v1 t2
    (Let v t1 t2) -> singleEval ctx t1 >>= \t1' -> pure $ Let v t1' t2
    _ -> Nothing

-- Multistep Evaluation Function
multiStepEval :: Context -> Term -> Term
multiStepEval ctx t = maybe t (multiStepEval ctx) (singleEval ctx t)

-- Big Step Evaluation Function
bigStepEval :: Context -> Term -> Term
bigStepEval _ t@(Abs _ _ _) = t
bigStepEval ctx (App t1 t2) =
  let (Abs _ _ t12) = bigStepEval ctx t1
      v2  = bigStepEval ctx t2
  in bigStepEval ctx $ substTop v2 t12
bigStepEval ctx (If t1' t2' t3') =
  case bigStepEval ctx t1' of
    Tru -> bigStepEval ctx t2'
    Fls -> bigStepEval ctx t3'
    _   -> undefined
bigStepEval ctx (Case l m _ n) =
  case bigStepEval ctx l of
    Z -> bigStepEval ctx m
    (S l') -> bigStepEval ctx $ substTop l' n
    x -> error $ show x
bigStepEval ctx (As t1 _) = bigStepEval ctx t1
bigStepEval _ Tru = Tru
bigStepEval _ Fls = Fls
bigStepEval _ x = error $ show x

{-
TODO: Fix this horrible bug!

> (\l:Nat.(\n:Nat.let x = case n of Z => 0 | (S m) => l in x)) 1 2
S S 0

> (\l:Nat.(\n:Nat.let x = case n of Z => 0 | (S m) => l in x)) 1
typedLCI: Prelude.!!: index too large

> (\l:Nat.(\n:Nat.case n of Z => 0 | (S m) => l)) 1
typedLCI: Prelude.!!: index too large
-}
