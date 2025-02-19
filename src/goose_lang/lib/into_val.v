From Perennial.goose_lang Require Import notation typing.
From Perennial.goose_lang.lib Require Import typed_mem slice.slice struct.struct.
Set Default Proof Using "Type".

Class IntoVal {ext: ffi_syntax} V :=
  { to_val: V → val;
    from_val: val → option V;
    IntoVal_def: V;
    IntoVal_inj' v : from_val (to_val v) = Some v ;
  }.
#[global]
Hint Mode IntoVal - ! : typeclass_instances.

Arguments IntoVal_def {_} V {_}.

Global Instance IntoVal_inj `{IntoVal V} :
  Inj (A:=V) eq eq to_val.
Proof.
  intros ?? Heq.
  assert (from_val (V:=V) (to_val x) = from_val (to_val y)) as Heq' by by f_equal.
  rewrite !IntoVal_inj' in Heq'. congruence.
Qed.

(* IntoVal for a particular GooseLang type *)
Class IntoValForType {ext} V {H: @IntoVal ext V} {ext_ty: ext_types ext} (t:ty) :=
    { def_is_zero: to_val (IntoVal_def V) = zero_val t;
      to_val_has_zero: has_zero t;
      (* TODO: this isn't necessary, but it seems reasonable *)
      to_val_ty: forall v:V, val_ty (to_val v) t; }.
(* Require [V] or [ty] to not be an evar before doing TC search *)
#[global]
Hint Mode IntoValForType - - - - ! : typeclass_instances.
#[global]
Hint Mode IntoValForType - ! - - - : typeclass_instances.

#[global]
Instance Permutation_inj_list_fmap {A B} (f: A -> B) `{!Inj eq eq f} :
  Inj (≡ₚ) (≡ₚ) (fmap (M:=list) f).
Proof.
  intros l.
  induction l as [|x l IHl]; intros l' H.
  - destruct l'; simpl in H; auto.
    apply Permutation_nil_cons in H; contradiction.
  - rewrite fmap_cons in H. symmetry in H.
    eapply Permutation_cons_inv_r in H as (l0' & l1' & [Hfl Hfl']).
    eapply fmap_app_inv in Hfl as (l0 & l1 & (->&Hfl&->)).
    destruct l1; first by simpl in *; congruence.
    rewrite fmap_cons in Hfl. inversion Hfl; clear Hfl.
    apply (inj f) in H0; subst.
    eapply Permutation_cons_app.
    eapply IHl. rewrite fmap_app. eauto.
Qed.

Theorem IntoVal_eq_fmap_prod_permutation {ext V} (H: @IntoVal ext V) {K} :
  Inj (≡ₚ) (≡ₚ) (fmap (prod_map (@id K) (to_val (V:=V)))).
Proof.
  apply _.
Qed.

#[global]
Instance Inj_fmap_map {K} `{!EqDecision K} `{!Countable K} {A B} (f: A → B) `{!Inj eq eq f} :
  Inj eq eq (fmap (M:=gmap K) f).
Proof.
  intros m m' H.
  rewrite <- (list_to_map_to_list m) in *.
  rewrite <- (list_to_map_to_list m') in *.
  pose proof (NoDup_fst_map_to_list m).
  pose proof (NoDup_fst_map_to_list m').
  generalize dependent (map_to_list m).
  generalize dependent (map_to_list m').
  intros.
  eapply list_to_map_proper; eauto.
  rewrite -!list_to_map_fmap in H.
  apply (inj (fmap (prod_map id f))).
  eapply list_to_map_inj in H; eauto.
  { rewrite -list_fmap_compose /compose /prod_map /=. eauto. }
  { rewrite -list_fmap_compose /compose /prod_map /=. eauto. }
Qed.

(** instances for IntoVal *)
Section instances.
  Context {ext: ffi_syntax} {ext_ty: ext_types ext}.

  Definition u64val (x:u64) : val := #x.
  Global Instance u64_IntoVal : IntoVal u64.
  Proof.
    refine {| to_val := λ (x: u64), #x;
              from_val := λ v, match v with #(LitInt x) => Some x | _ => None end;
              IntoVal_def := U64 0; |}; done.
  Defined.
  Global Instance u64_IntoVal_uint64T : IntoValForType u64 uint64T.
  Proof.
    constructor; auto.
  Qed.

  Global Instance u8_IntoVal : IntoVal u8.
  Proof.
    refine {| to_val := λ (x: u8), #x;
              from_val := λ v, match v with #(LitByte x) => Some x | _ => None end;
              IntoVal_def := U8 0; |}; done.
  Defined.
  Global Instance u8_IntoVal_byteT : IntoValForType u8 byteT.
  Proof.
    constructor; eauto.
  Qed.

  Global Instance loc_IntoVal : IntoVal loc.
  Proof.
    refine {| to_val := λ (l: loc), #l;
              from_val := λ v, match v with #(LitLoc x) => Some x | _ => None end;
              IntoVal_def := null; |}; done.
  Defined.
  Global Instance loc_IntoVal_struct_ptr t : IntoValForType loc (struct.ptrT t).
  Proof.
    constructor; auto.
  Qed.
  Global Instance loc_IntoVal_ref t : IntoValForType loc (refT t).
  Proof.
    constructor; auto.
  Qed.
  Global Instance loc_IntoVal_ptr : IntoValForType loc ptrT.
  Proof.
    constructor; auto.
  Qed.

  Global Instance slice_IntoVal : IntoVal Slice.t.
    refine
    {| to_val := slice_val;
       from_val := val_slice;
       IntoVal_def := Slice.nil;
    |}.
    intros []. auto.
  Defined.
  Global Instance slice_IntoVal_ref t : IntoValForType Slice.t (slice.T t).
  Proof.
    constructor; auto.
    intros.
    apply slice_val_ty.
  Qed.


  Global Instance bool_IntoVal : IntoVal bool.
  Proof.
    refine {| into_val.to_val := λ (x: bool), #x;
              from_val := λ v, match v with #(LitBool x) => Some x | _ => None end;
              IntoVal_def := false; |}; done.
  Defined.
  Global Instance bool_IntoVal_boolT : IntoValForType bool boolT.
  Proof. constructor; auto. Qed.

  Global Instance unit_IntoVal : IntoVal ().
  Proof.
    refine {| to_val := λ _, #();
              from_val := λ v, match v with #(LitUnit) => Some () | _ => None end;
              IntoVal_def := ();
           |}.
    intros []; auto.
  Defined.
  Global Instance unit_IntoValForType : IntoValForType () unitT.
  Proof. constructor; auto. Qed.

End instances.
