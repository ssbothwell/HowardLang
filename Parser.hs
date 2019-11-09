module TypedLambdaCalcInitial.Parser where

import Control.Applicative hiding (some, many)
import Control.Monad.Reader

import Data.Functor.Identity
import Data.List

import Text.Megaparsec
import Text.Megaparsec.Char
import qualified Text.Megaparsec.Char.Lexer as L

import TypedLambdaCalcInitial.Types

{-
TODO: Figure out how to represent parsing `INTEGER` into peano numbers.
BNF Grammer:

ALPHA = "A".."Z" | "a".."z";
DIGIT = "0".."9";
INTEGER = DIGIT {DIGIT};

VAR = ALPHA {ALPHA | INTEGER};
BOOL = "True" | "False";
S = "S" TERM;
Z = "Z" | "0";
APP = TERM TERM;
ABS = ("\\" | "λ") VAR ":" TYPE "." TERM;
CASE = "case" TERM "of" "Z" "=>" TERM "|" "(S" VAR ")" "=>" TERM;
IF = "if:" TERM "then:" TERM "else:" TERM;
PAIR = "<" TERM "," TERM ">";
FST = "fst" TERM;
SND = "snd" TERM;
TUPLE = "(" TERM { "," TERM } ")";
PROJ = TERM ".";
RECORD = "{" VAR "=" TERM { "," VAR "=" TERM } "}";
GROUP = "(" TERM ")";

TYPE = "Unit" | "Bool" | "Nat" | TYPE "->" "TYPE" | TYPE "x" TYPE | "(" TYPE { "," TYPE } ")" | "{" TYPE { "," TYPE } "}";
TERM = GROUP | VAR | S | Z | NAT | BOOL | APP | ABS | CASE | IF | PAIR | FST | SND | TUPLE | PROJ | RECORD;

-}

-- TODO: look into deriving MonadParsec
-- newtype Parser a = Parser { runParser :: ParsecT Void String (Reader Bindings) a }
--   deriving MonadParsec
type Parser a = ParsecT UnboundError String (Reader Bindings) a


handleParseErr :: Either ParseErr Term -> Either Err Term
handleParseErr val = either (Left . P) Right val

runParse :: String -> Either Err Term
runParse = handleParseErr . runIdentity . flip runReaderT [] . runParserT pMain mempty

run :: Parser a -> String -> Either ParseErr a
run p = runIdentity . flip runReaderT [] . runParserT p mempty


-------------
--- Lexer ---
-------------

sc :: Parser ()
sc = L.space space1 lineCmnt blockCmnt
  where
    lineCmnt  = L.skipLineComment "--"
    blockCmnt = L.skipBlockComment "{-" "-}"

lexeme :: Parser a -> Parser a
lexeme = L.lexeme sc

symbol :: String -> Parser String
symbol = L.symbol sc

parens :: Parser a -> Parser a
parens = between (symbol "(") (symbol ")")

bracket :: Parser a -> Parser a
bracket = between (symbol "{") (symbol "}")

angleBracket :: Parser a -> Parser a
angleBracket = between (symbol "<") (symbol ">")

parensOpt :: Parser a -> Parser a
parensOpt p = parens p <|> p

integer :: Parser Integer
integer = lexeme L.decimal

semi :: Parser ()
semi = void $ symbol ";"

colon :: Parser ()
colon = void $ symbol ":"

dot :: Parser ()
dot = void $ symbol "."

arrow :: Parser ()
arrow = void $ symbol "->"

phatArrow :: Parser ()
phatArrow = void $ symbol "=>"

pipe :: Parser ()
pipe = void $ symbol "|"

lambda :: Parser ()
lambda = void $ symbol "λ" <|> symbol "\\"

rword :: String -> Parser ()
rword w = (lexeme . try) (string w *> notFollowedBy alphaNumChar)

rws :: [String]
rws = [ "if"
      , "then"
      , "else"
      , "True"
      , "False"
      , "case"
      , "of"
      , "Z"
      , "S"
      , "|"
      , "Unit"
      , "as"
      , "let"
      , "in"
      , "="
      , "fst"
      , "snd"
      , "get"
      , ","
      ]

identifier :: Parser String
identifier = (lexeme . try) (p >>= check)
  where
    p :: Parser String
    p = (:) <$> letterChar <*> many alphaNumChar
    check :: String -> Parser String
    check str = if str `elem` rws
                 then fail $ "keyword " ++ show str ++ " cannot be an identifier"
                 else pure str


--------------
--- Parser ---
--------------

-- | Types

pUnitT :: Parser Type
pUnitT = rword "Unit" *> pure UnitT

pNatT :: Parser Type
pNatT = rword "Nat" *> pure NatT

pBoolT :: Parser Type
pBoolT = rword "Bool" *> pure BoolT

pArrowNest :: Parser Type
pArrowNest = parens pArrow

pArrow :: Parser Type
pArrow = do
  types <- (parens pArrow <|> pNatT <|> pBoolT <|> pUnitT) `sepBy1` arrow
  pure $ foldr1 FuncT types

pPairT :: Parser Type
pPairT = do
  ty1 <- parseType
  void $ symbol "X"
  ty2 <- parseType
  pure $ PairT ty1 ty2

parseType :: Parser Type
parseType = try pArrow <|> pPairT <|> pBoolT <|> pNatT


-- | Terms:

-- TODO: Figure out how to adjust `pTerm` to allow for `rword "()"`
pUnit :: Parser Term
pUnit = rword "Unit" *> pure Unit

pBool :: Parser Term
pBool = (rword "True" *> pure Tru) <|> (rword "False" *> pure Fls)

searchContext :: Eq a => [a] -> a -> Maybe Int
searchContext ctx val = (find (== val) ctx) >>= flip elemIndex ctx

pVar :: Parser Term
pVar = do
  ctx <- ask
  val <- identifier
  if null ctx
    then pure $ Var 0
    else case searchContext ctx val of
           Just i -> pure $ Var i
           Nothing -> customFailure $ UnboundError $ val ++ " not in scope."

pIf :: Parser Term
pIf = do
  rword "if" *> colon
  t1 <- pTerm
  rword "then" *> colon
  t2 <- pTerm
  rword "else" *> colon
  t3 <- pTerm
  pure $ If t1 t2 t3

pPeano :: Parser Term
pPeano = rword "S" *> (S <$> pTerm) <|> (rword "Z" *> pure Z)

pNat :: Parser Term
pNat = do
   digits <- fromIntegral <$> integer
   pure . foldr (\a b -> a b) Z $ replicate digits S

pPair :: Parser Term
pPair = angleBracket $ do
  t1 <- pTerm
  void $ symbol ","
  t2 <- pTerm
  pure $ Pair t1 t2

pAs :: Parser Term
pAs = parens $ do
  t1 <- pTerm
  rword "as"
  ty <- parseType
  pure $ As t1 ty

pCase :: Parser Term
pCase = do
  rword "case"
  n <- pTerm
  rword "of"
  rword "Z"
  phatArrow
  z <- pTerm
  pipe
  var <- parensOpt $ rword "S" *> identifier
  phatArrow
  s <- local (updateEnv var) pTerm
  pure $ Case n z var s

pLet :: Parser Term
pLet = do
  rword "let"
  var <- identifier
  rword "="
  t1 <- pTerm
  rword "in"
  t2 <- local (updateEnv var) pTerm
  pure $ Let var t1 t2

pFst :: Parser Term
pFst = do
  rword "fst"
  t <- pTerm
  pure $ Fst t

pSnd :: Parser Term
pSnd = do
  rword "snd"
  t <- pTerm
  pure $ Snd t

pTuple :: Parser Term
pTuple = parens $ do
  ts <- pTerm `sepBy1` symbol ","
  if length ts == 1
  then pure $ head ts
  else pure $ Tuple ts

pGet :: Parser Term
pGet = do
  rword "get"
  t1 <- pTerm
  dot
  t2 <- pTerm
  pure $ Get t1 t2

pRecord :: Parser Term
pRecord = bracket $ do
  ts <- pClause `sepBy1` symbol ","
  pure $ Record ts
  where
    pClause :: Parser (Varname, Term)
    pClause = do
      v1 <- identifier
      rword "="
      --t1 <- pTerm
      pure (v1, Tru)

updateEnv :: Varname -> Bindings -> Bindings
updateEnv var env = var : env

pAbs :: Parser Term
pAbs = do
  lambda
  var <- identifier
  colon
  ty <- parseType
  dot
  term <- local (updateEnv var) pTerm
  pure (Abs var ty term)

pValues :: Parser Term
pValues = pTuple <|> pRecord <|> pPair <|> pUnit <|> pBool <|> pNat <|> pPeano <|> pVar

pStmts :: Parser Term
pStmts = pGet <|> pCase <|> pAbs <|> pLet <|> pAs <|> pFst <|> pSnd

pTerm :: Parser Term
pTerm = foldl1 App <$> (  pIf
                      <|> try pStmts
                      <|> try pValues
                      <|> parens pTerm
                       ) `sepBy1` sc

pMain :: Parser Term
pMain = pTerm <* eof
