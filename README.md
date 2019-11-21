# Howard Lang

A pure interpreted lambda calculus with Algebraic and Recursive Types.

### Current features:
- Sum and Product types
- Recursive Types
- Ascriptions
- Let bindings
- Nat and Bool base types
- A REPL

### TODO:
- Complete Parser for Recursive Types
- Overhaul error reporting
- Overhaul pretty printing
- Type Aliases
- Data Type Binding
- Polymorphism (System F)
- Type Inference
- Type Operators (Omega)
- Ocaml style module system

### Example Usage:
#### Base types:
```ml
λ> True
True

λ> :t True
Bool

λ> 1
S Z

λ> :t 1
Nat

λ> Unit
Unit

λ> :t Unit
Unit
```
#### Sums and Products:
```ml
λ> (1, True, Unit)
(S Z , True , Unit)

λ> :t (1, True, Unit)
[Nat, Bool, Unit]

λ> tag Left True as (Left Bool | Right Nat)
Left True

λ> :t tag Left True as (Left Bool | Right Nat)
Left Bool | Right Nat

λ> tag Nothing as (Nothing | Just Nat)
Nothing

λ> :t tag Nothing as (Nothing | Just Nat)
Nothing | Just Nat
```

#### Recursive Types:
The parser is incomplete but here is the AST for a linked list:
```haskell
ListT :: Type
ListT = FixT "ListT" (VariantT [("Nil", UnitT), ("Cons", TupleT [NatT, VarT 0])])

nil :: Term
nil = Roll ListT (Tag "Nil" Unit (VariantT [("Nil", UnitT), ("Cons", TupleT [NatT, ListT])]))

cons :: Term
cons = Abs "x" NatT . Abs "xs" ListT .
       Roll ListT $ Tag "Cons" (Tuple [("0", Var 1), ("1", Var 0)]) (VariantT [("Nil", UnitT), ("Cons", TupleT [NatT, ListT])])
```

#### Functions:
```ml
λ> (\n:Nat.n)
(λ n : Nat. n)

λ> :t (\n:Nat.n)
Nat -> Nat

λ> (\n:Nat.n) 1
S Z

λ> :t (\p:Bool.\n:Nat.n)
Bool -> (Nat -> Nat)

λ> let f (n : Nat) = S n in f
(λ n : Nat. S n)

λ> :t let f (n : Nat) = S n in f
Nat -> Nat

λ> let f (n : Nat) = S n in f 2
S (S (S Z))

λ> let f (n : Nat) (p : Bool) = S n in f
(λ n : Nat. (λ p : Bool. S n))
```

#### Pattern Matching:
```ml
λ> :t (\x:(Nothing | Just Nat).variantCase x of Nothing => 0 | Just=y => y)
Nothing | Just Nat -> Nat

λ> (\x:(Nothing | Just Nat).variantCase x of Nothing => 0 | Just=y => y) (tag Nothing as (Nothing | Just Nat))
0

λ> (\x:(Nothing | Just Nat).variantCase x of Nothing => 0 | Just=y => y) (tag Just 2 as (Nothing | Just Nat))
S (S Z)
```
