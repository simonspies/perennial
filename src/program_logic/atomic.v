From Perennial.program_logic Require Export crash_weakestpre.
Set Default Proof Using "Type".

(** Sugar for TaDA-style logically atomic non-crash specs. We only have the variants we need. *)
(** Use [ncfupd_mask_intro] if you are stuck with non-matching masks. *)
(* Full variant *)
Notation "'{{{' P } } } '<<<' ∀∀ x1 .. xn , α '>>>' e @ Eo '<<<' ∃∃ y1 .. yn , β '>>>' {{{ z1 .. zn , 'RET' v ; Q } } }" :=
  (□ ∀ Φ, P -∗ (▷ |NC={⊤∖Eo%I%I%I%I,∅}=> ∃ x1, .. (∃ xn, α ∗ ∀ y1, .. (∀ yn, β -∗ |NC={∅,⊤∖Eo}=> ∀ z1, .. (∀ zn, Q -∗ Φ v%V) .. ) .. ) .. ) -∗
   WP e @ ⊤ {{ Φ }})%I
  (at level 20, x1 closed binder, xn closed binder, y1 closed binder, yn closed binder, z1 closed binder, zn closed binder,
   format "'[hv' {{{  '[' P  ']' } } }  '/' '<<<'  '[' ∀∀  x1  ..  xn ,  '/' α  ']' '>>>'  '/  ' e  '/' @  Eo  '/' '<<<'  '[' ∃∃  y1  ..  yn ,  '/' β  ']' '>>>'  '/' {{{  '[' z1  ..  zn ,  RET  v ;  '/' Q  ']' } } } ']'")
  : bi_scope.
(* No RET binders *)
Notation "'{{{' P } } } '<<<' ∀∀ x1 .. xn , α '>>>' e @ Eo '<<<' ∃∃ y1 .. yn , β '>>>' {{{ 'RET' v ; Q } } }" :=
  (□ ∀ Φ, P -∗ (▷ |NC={⊤∖Eo%I%I%I%I,∅}=> ∃ x1, .. (∃ xn, α ∗ ∀ y1, .. (∀ yn, β -∗ |NC={∅,⊤∖Eo}=> Q -∗ Φ v%V) .. ) .. ) -∗
   WP e @ ⊤ {{ Φ }})%I
  (at level 20, x1 closed binder, xn closed binder, y1 closed binder, yn closed binder,
   format "'[hv' {{{  '[' P  ']' } } }  '/' '<<<'  '[' ∀∀  x1  ..  xn ,  '/' α  ']' '>>>'  '/  ' e  '/' @  Eo  '/' '<<<'  '[' ∃∃  y1  ..  yn ,  '/' β  ']' '>>>'  '/' {{{  '[' RET  v ;  '/' Q  ']' } } } ']'")
  : bi_scope.
(* No ∃∃ *)
Notation "'{{{' P } } } '<<<' ∀∀ x1 .. xn , α '>>>' e @ Eo '<<<' β '>>>' {{{ z1 .. zn , 'RET' v ; Q } } }" :=
  (□ ∀ Φ, P -∗ (▷ |NC={⊤∖Eo%I%I,∅}=> ∃ x1, .. (∃ xn, α ∗ (β -∗ |NC={∅,⊤∖Eo}=> ∀ z1, .. (∀ zn, Q -∗ Φ v%V) .. )) .. ) -∗
   WP e @ ⊤ {{ Φ }})%I
  (at level 20, x1 closed binder, xn closed binder, z1 closed binder, zn closed binder,
   format "'[hv' {{{  '[' P  ']' } } }  '/' '<<<'  '[' ∀∀  x1  ..  xn ,  '/' α  ']' '>>>'  '/  ' e  '/' @  Eo  '/' '<<<'  '[' β  ']' '>>>'  '/' {{{  '[' z1  ..  zn ,  RET  v ;  '/' Q  ']' } } } ']'")
  : bi_scope.
(* No ∃∃, no RET binders *)
Notation "'{{{' P } } } '<<<' ∀∀ x1 .. xn , α '>>>' e @ Eo '<<<' β '>>>' {{{ 'RET' v ; Q } } }" :=
  (□ ∀ Φ, P -∗ (▷ |NC={⊤∖Eo%I%I,∅}=> ∃ x1, .. (∃ xn, α ∗ (β -∗ |NC={∅,⊤∖Eo}=> Q -∗ Φ v%V)) .. ) -∗
   WP e @ ⊤ {{ Φ }})%I
  (at level 20, x1 closed binder, xn closed binder,
   format "'[hv' {{{  '[' P  ']' } } }  '/' '<<<'  '[' ∀∀  x1  ..  xn ,  '/' α  ']' '>>>'  '/  ' e  '/' @  Eo  '/' '<<<'  '[' β  ']' '>>>'  '/' {{{  '[' RET  v ;  '/' Q  ']' } } } ']'")
  : bi_scope.
(* No P *)
Notation "'<<<' ∀∀ x1 .. xn , α '>>>' e @ Eo '<<<' ∃∃ y1 .. yn , β '>>>' {{{ z1 .. zn , 'RET' v ; Q } } }" :=
  (□ ∀ Φ, (▷ |NC={⊤∖Eo%I%I%I%I,∅}=> ∃ x1, .. (∃ xn, α ∗ ∀ y1, .. (∀ yn, β -∗ |NC={∅,⊤∖Eo}=> ∀ z1, .. (∀ zn, Q -∗ Φ v%V) .. ) .. ) .. ) -∗
   WP e @ ⊤ {{ Φ }})%I
  (at level 20, x1 closed binder, xn closed binder, y1 closed binder, yn closed binder, z1 closed binder, zn closed binder,
   format "'[hv' '<<<'  '[' ∀∀  x1  ..  xn ,  '/' α  ']' '>>>'  '/  ' e  '/' @  Eo  '/' '<<<'  '[' ∃∃  y1  ..  yn ,  '/' β  ']' '>>>'  '/' {{{  '[' z1  ..  zn ,  RET  v ;  '/' Q  ']' } } } ']'")
  : bi_scope.
(* No P, no RET binders *)
Notation "'<<<' ∀∀ x1 .. xn , α '>>>' e @ Eo '<<<' ∃∃ y1 .. yn , β '>>>' {{{ 'RET' v ; Q } } }" :=
  (□ ∀ Φ, (▷ |NC={⊤∖Eo%I%I%I%I,∅}=> ∃ x1, .. (∃ xn, α ∗ ∀ y1, .. (∀ yn, β -∗ |NC={∅,⊤∖Eo}=> Q -∗ Φ v%V) .. ) .. ) -∗
   WP e @ ⊤ {{ Φ }})%I
  (at level 20, x1 closed binder, xn closed binder, y1 closed binder, yn closed binder,
   format "'[hv' '<<<'  '[' ∀∀  x1  ..  xn ,  '/' α  ']' '>>>'  '/  ' e  '/' @  Eo  '/' '<<<'  '[' ∃∃  y1  ..  yn ,  '/' β  ']' '>>>'  '/' {{{  '[' RET  v ;  '/' Q  ']' } } } ']'")
  : bi_scope.
(* No P, no ∃∃ *)
Notation "'<<<' ∀∀ x1 .. xn , α '>>>' e @ Eo '<<<' β '>>>' {{{ z1 .. zn , 'RET' v ; Q } } }" :=
  (□ ∀ Φ, (▷ |NC={⊤∖Eo%I%I,∅}=> ∃ x1, .. (∃ xn, α ∗ (β -∗ |NC={∅,⊤∖Eo}=> ∀ z1, .. (∀ zn, Q -∗ Φ v%V) .. )) .. ) -∗
   WP e @ ⊤ {{ Φ }})%I
  (at level 20, x1 closed binder, xn closed binder, z1 closed binder, zn closed binder,
   format "'[hv' '<<<'  '[' ∀∀  x1  ..  xn ,  α  ']' '>>>'  '/  ' e  '/' @  Eo  '/' '<<<'  '[' β  ']' '>>>'  '/' {{{  '[' z1  ..  zn ,  RET  v ;  '/' Q  ']' } } } ']'")
  : bi_scope.
(* No P, no ∃∃, no RET binders *)
Notation "'<<<' ∀∀ x1 .. xn , α '>>>' e @ Eo '<<<' β '>>>' {{{ 'RET' v ; Q } } }" :=
  (□ ∀ Φ, (▷ |NC={⊤∖Eo%I%I,∅}=> ∃ x1, .. (∃ xn, α ∗ (β -∗ |NC={∅,⊤∖Eo}=> Q -∗ Φ v%V )) .. ) -∗
   WP e @ ⊤ {{ Φ }})%I
  (at level 20, x1 closed binder, xn closed binder,
   format "'[hv' '<<<'  '[' ∀∀  x1  ..  xn ,  α  ']' '>>>'  '/  ' e  '/' @  Eo  '/' '<<<'  '[' β  ']' '>>>'  '/' {{{  '[' RET  v ;  '/' Q  ']' } } } ']'")
  : bi_scope.

(** Sugar for HoCAP-style logically atomic crash specs.
[Pa] is what the client *gets* right before the linearization point, and [Qa]
is what they have to prove to complete linearization.

We use [<<{] becazse [<<<] is already used in Iris for TaDa-style logically
atomic triples.

TODO: add versions without the ∀∀ binder.
And maybe versions with an ∃∃ binder in front of [Qa]? *)

(* Full variant *)
Notation "'{{{' P } } } '<<{' ∀∀ x1 .. xn , Pa '}>>' e @ E1 <<{ ∃∃ y1 .. yn , Qa '}>>' {{{ z1 .. zn , 'RET' pat ; Q } } } {{{ Qc } } }" :=
  (□ ∀ Φ Φc,
      P -∗
      (Qc%I%I%I%I -∗ Φc) (* crash condition before lin.point *) ∧
        ▷ (∀ x1, .. (∀ xn, Pa -∗ |NC={⊤∖E1}=> ∀ y1, .. (∀ yn, Qa ∗
          ((Qc -∗ Φc) (* crash condition after lin.point *) ∧
           ∀ z1, .. (∀ zn, Q -∗ Φ pat%V) .. )) .. ) .. ) -∗
      WPC e @ ⊤ {{ Φ }} {{ Φc }})%I
    (at level 20, x1 closed binder, xn closed binder, y1 closed binder, yn closed binder, z1 closed binder, zn closed binder,
     format "'[hv' {{{  '[' P  ']' } } }  '/'  <<{  '[' ∀∀  x1  ..  xn ,  '/' Pa  ']' }>>  '/  ' e  '/' @  '[' E1  ']' '/' <<{  '[' ∃∃  y1  ..  yn ,  '/' Qa ']' }>>  '/' {{{  '[' z1  ..  zn ,  RET  pat ;  '/' Q  ']' } } }  '/' {{{  '[' Qc  ']' } } } ']'") : bi_scope.
(* No binders before RET *)
Notation "'{{{' P } } } '<<{' ∀∀ x1 .. xn , Pa '}>>' e @ E1 <<{ ∃∃ y1 .. yn , Qa '}>>' {{{ 'RET' pat ; Q } } } {{{ Qc } } }" :=
  (□ ∀ Φ Φc,
      P -∗
      (Qc%I%I%I%I -∗ Φc) (* crash condition before lin.point *) ∧
        ▷ (∀ x1, .. (∀ xn, Pa -∗ |NC={⊤∖E1}=> ∀ y1, .. (∀ yn, Qa ∗
          ((Qc -∗ Φc) (* crash condition after lin.point *) ∧
           Q -∗ Φ pat%V)) .. ) .. ) -∗
      WPC e @ ⊤ {{ Φ }} {{ Φc }})%I
    (at level 20, x1 closed binder, xn closed binder, y1 closed binder, yn closed binder,
     format "'[hv' {{{  '[' P  ']' } } }  '/'  <<{  '[' ∀∀  x1  ..  xn ,  '/' Pa  ']' }>>  '/  ' e  '/' @  '[' E1  ']' '/' <<{  '[' ∃∃  y1  ..  yn ,  '/' Qa ']' }>>  '/' {{{  '[' RET  pat ;  '/' Q  ']' } } }  '/' {{{  '[' Qc  ']' } } } ']'") : bi_scope.
(* No ∃∃ *)
Notation "'{{{' P } } } '<<{' ∀∀ x1 .. xn , Pa '}>>' e @ E1 <<{ Qa '}>>' {{{ z1 .. zn , 'RET' pat ; Q } } } {{{ Qc } } }" :=
  (□ ∀ Φ Φc,
      P -∗
      (Qc%I%I -∗ Φc) (* crash condition before lin.point *) ∧
        ▷ (∀ x1, .. (∀ xn, Pa -∗ |NC={⊤∖E1}=> Qa ∗
          ((Qc -∗ Φc) (* crash condition after lin.point *) ∧
           ∀ z1, .. (∀ zn, Q -∗ Φ pat%V) .. )) .. ) -∗
      WPC e @ ⊤ {{ Φ }} {{ Φc }})%I
    (at level 20, x1 closed binder, xn closed binder, z1 closed binder, zn closed binder,
     format "'[hv' {{{  '[' P  ']' } } }  '/'  <<{  '[' ∀∀  x1  ..  xn ,  '/' Pa  ']' }>>  '/  ' e  '/' @  '[' E1  ']' '/' <<{  '[' Qa ']' }>>  '/' {{{  '[' z1  ..  zn ,  RET  pat ;  '/' Q  ']' } } }  '/' {{{  '[' Qc  ']' } } } ']'") : bi_scope.
(* No ∃∃, no binders before RET *)
Notation "'{{{' P } } } '<<{' ∀∀ x1 .. xn , Pa '}>>' e @ E1 <<{ Qa '}>>' {{{ 'RET' pat ; Q } } } {{{ Qc } } }" :=
  (□ ∀ Φ Φc,
      P -∗
      (Qc%I%I -∗ Φc) (* crash condition before lin.point *) ∧
        ▷ (∀ x1, .. (∀ xn, Pa -∗ |NC={⊤∖E1}=> Qa ∗
          ((Qc -∗ Φc) (* crash condition after lin.point *) ∧
          (Q -∗ Φ pat%V) )) .. ) -∗
      WPC e @ ⊤ {{ Φ }} {{ Φc }})%I
    (at level 20, x1 closed binder, xn closed binder,
     format "'[hv' {{{  '[' P  ']' } } }  '/'  <<{  '[' ∀∀  x1  ..  xn ,  '/' Pa  ']' }>>  '/  ' e  '/' @  '[' E1  ']' '/' <<{  '[' Qa ']' }>>  '/' {{{  '[' RET  pat ;  '/' Q  ']' } } }  '/' {{{  '[' Qc  ']' } } } ']'") : bi_scope.
