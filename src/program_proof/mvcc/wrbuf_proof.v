From Perennial.program_proof.mvcc Require Import wrbuf_prelude wrbuf_repr.

Section heap.
Context `{!heapGS Σ, !mvcc_ghostG Σ}.

(*****************************************************************)
(* func MkWrBuf() *WrBuf                                         *)
(*****************************************************************)
Theorem wp_MkWrBuf :
  {{{ True }}}
    MkWrBuf #()
  {{{ (wrbuf : loc), RET #wrbuf; own_wrbuf_xtpls wrbuf ∅ }}}.
Proof.
  iIntros (Φ) "_ HΦ".
  wp_call.
  
  (***********************************************************)
  (* wrbuf := new(WrBuf)                                     *)
  (***********************************************************)
  wp_apply (wp_allocStruct); first auto 10.
  iIntros (wrbuf) "Hwrbuf".
  wp_pures.

  (***********************************************************)
  (* wrbuf.ents = make([]WrEnt, 0, 16)                       *)
  (***********************************************************)
  iDestruct (struct_fields_split with "Hwrbuf") as "Hwrbuf".
  iNamed "Hwrbuf".
  simpl.
  wp_pures.
  wp_apply (wp_new_slice_cap); [done | word |].
  iIntros (ents) "HentsS".
  wp_storeField.

  (***********************************************************)
  (* return wrbuf                                            *)
  (***********************************************************)
  iModIntro.
  iApply "HΦ".
  iExists _, [].
  change (int.nat 0) with 0%nat.
  rewrite replicate_0.
  iFrame.
  iPureIntro.
  split; [apply NoDup_nil_2 | done].
Qed.

Definition spec_search (key : u64) (ents : list wrent) (pos : u64) (found : bool) :=
  match found with
  | false => key ∉ ents.*1.*1.*1
  | true  => (∃ ent, ents !! (int.nat pos) = Some ent ∧ ent.1.1.1 = key)
  end.

(*****************************************************************)
(* func search(ents []WrEnt, key uint64) (uint64, bool)          *)
(*****************************************************************)
Local Lemma wp_search (key : u64) (entsS : Slice.t) (ents : list wrent) :
  {{{ slice.is_slice entsS (structTy WrEnt) 1 (wrent_to_val <$> ents) }}}
    search (to_val entsS) #key
  {{{ (pos : u64) (found : bool), RET (#pos, #found);
      slice.is_slice entsS (structTy WrEnt) 1 (wrent_to_val <$> ents) ∗
      ⌜spec_search key ents pos found⌝
  }}}.
Proof.
  iIntros (Φ) "HentsS HΦ".
  wp_call.
  
  (***********************************************************)
  (* var pos uint64 = 0                                      *)
  (***********************************************************)
  wp_apply (wp_ref_to); first auto.
  iIntros (posR) "HposR".
  wp_pures.
  
  (***********************************************************)
  (* for pos < uint64(len(ents)) && key != ents[pos].key {   *)
  (*     pos++                                               *)
  (* }                                                       *)
  (***********************************************************)
  set P := (λ (b : bool), ∃ (pos : u64),
               "HentsS" ∷ (slice.is_slice entsS (struct.t WrEnt) 1 (wrent_to_val <$> ents)) ∗
               "HposR" ∷ posR ↦[uint64T] #pos ∗
               "%Hexit" ∷ (⌜if b then True
                            else (∃ (ent : wrent), ents !! (int.nat pos) = Some ent ∧ ent.1.1.1 = key) ∨
                                 (int.Z entsS.(Slice.sz)) ≤ (int.Z pos)⌝) ∗
               "%Hnotin" ∷ (⌜key ∉ (take (int.nat pos) ents.*1.*1.*1)⌝))%I.
  wp_apply (wp_forBreak_cond P with "[] [$HentsS HposR]").
  { clear Φ.
    iIntros (Φ) "!> HP HΦ".
    iNamed "HP".
    wp_pures.
    (* Evaluate the first condition: `pos < uint64(len(ents))`. *)
    wp_load.
    wp_apply (wp_slice_len).
    wp_pures.
    (* Bind the inner if. *)
    wp_bind (If #(bool_decide _) _ _).
    (**
     * Note on why [wp_and] won't work here:
     * The proof state evolves as follows:
     * 1. [wp_and] creates an evar for `key != ents[pos].key`.
     * 2. after the first condition, i.e. `pos < uint64(len(ents))`,
     * we know the access to `ents` at index `pos` is safe, and hence
     * we can get the entry at that index.
     *
     * Problem: the evar is created *before* that entry is created.
     *)
    wp_if_destruct; last first.
    { (* Exit the loop due to the first condition. *)
      wp_if_false.
      iApply "HΦ".
      iExists _.
      iFrame "∗ %".
      iPureIntro. right.
      by apply Znot_lt_ge, Z.ge_le in Heqb.
    }
    (* Evaluate the second condition: `key != ents[pos].key`. *)
    iDestruct (slice.is_slice_small_acc with "HentsS") as "[HentsS HentsC]".
    iDestruct (slice.is_slice_small_sz with "[$HentsS]") as "%HentsSz".
    wp_load.
    destruct (list_lookup_lt _ (wrent_to_val <$> ents) (int.nat pos)) as [ent Hlookup]; first word.
    wp_apply (slice.wp_SliceGet with "[$HentsS]"); first done.
    iIntros "[HentsS %HentsT]".
    iDestruct ("HentsC" with "HentsS") as "HentsS".
    simpl in HentsT.
    destruct (val_to_wrent_with_val_ty _ HentsT) as (k & v & w & t & Hent).
    subst ent.
    wp_pures.
    wp_if_destruct; last first.
    { (* Exit the loop due to the second condition. *)
      iApply "HΦ".
      iExists _.
      iFrame "∗ %".
      iPureIntro. left.
      exists (k, v, w, t).
      split; last done.
      rewrite list_lookup_fmap in Hlookup.
      apply fmap_Some in Hlookup as [ent [Hlookup H]].
      rewrite Hlookup.
      f_equal. inversion H.
      by rewrite -(surjective_pairing ent.1.1) -(surjective_pairing ent.1) -(surjective_pairing ent).
    }
    (* Evaluate the loop body. *)
    wp_load.
    wp_store.
    iApply "HΦ".
    iExists _.
    iFrame "∗ %".
    iPureIntro.
    (* Show preservation of the loop invariant after one iteration. *)
    replace (int.nat (word.add pos 1)) with (S (int.nat pos)) by word.
    intros Helem.
    rewrite (take_S_r _ _ k) in Helem; last first.
    { rewrite list_lookup_fmap in Hlookup.
      apply fmap_Some in Hlookup as [ent [Hlookup H]].
      do 3 rewrite list_lookup_fmap.
      rewrite Hlookup.
      simpl. by inversion H.
    }
    rewrite elem_of_app in Helem.
    destruct Helem; first by auto.
    rewrite elem_of_list_singleton in H. by rewrite H in Heqb0.
  }
  { iExists _.
    iFrame.
    iPureIntro.
    split; first done.
    change (int.nat 0) with 0%nat.
    rewrite take_0.
    set_solver.
  }
  iIntros "HP".
  iNamed "HP".
  wp_pures.
  
  (***********************************************************)
  (* found := pos < uint64(len(wset))                        *)
  (* return pos, found                                       *)
  (***********************************************************)
  wp_load.
  wp_apply (wp_slice_len).
  wp_pures.
  wp_load.
  iDestruct (is_slice_sz with "HentsS") as "%Hsz".
  rewrite fmap_length in Hsz.
  case_bool_decide; (wp_pures; iModIntro; iApply "HΦ"; iFrame; iPureIntro; unfold spec_search).
  { (* Write entry found. *)
    destruct Hexit; [done | word].
  }
  { (* Write entry not found. *)
    apply Z.nlt_ge in H.
    rewrite take_ge in Hnotin; first done.
    do 3 rewrite fmap_length.
    rewrite Hsz.
    word.
  }
Qed.

Local Lemma NoDup_wrent_to_key_dbval (ents : list wrent) :
  NoDup ents.*1.*1.*1 ->
  NoDup (wrent_to_key_dbval <$> ents).*1.
Proof.
  intros H.
  replace (wrent_to_key_dbval <$> _).*1 with ents.*1.*1.*1; last first.
  { do 3 rewrite -list_fmap_compose. f_equal. }
  done.
Qed.

Local Lemma wrent_to_key_dbval_key_fmap (ents : list wrent) :
  (wrent_to_key_dbval <$> ents).*1 = ents.*1.*1.*1.
Proof.
  do 3 rewrite -list_fmap_compose.
  by apply list_fmap_ext; last done.
Qed.

(* TODO: Return values first or others first? Make it consistent. *)
Definition spec_wrbuf__Lookup (v : u64) (b ok : bool) (key : u64) (m : gmap u64 dbval) :=
  if ok then m !! key = Some (to_dbval b v) else m !! key = None.

(*****************************************************************)
(* func (wrbuf *WrBuf) Lookup(key uint64) (uint64, bool, bool)   *)
(*****************************************************************)
Theorem wp_wrbuf__Lookup wrbuf (key : u64) m :
  {{{ own_wrbuf_xtpls wrbuf m }}}
    WrBuf__Lookup #wrbuf #key
  {{{ (v : u64) (b ok : bool), RET (#v, #b, #ok);
      own_wrbuf_xtpls wrbuf m ∗ ⌜spec_wrbuf__Lookup v b ok key m⌝
  }}}.
Proof.
  iIntros (Φ) "Hwrbuf HΦ".
  wp_call.
  iNamed "Hwrbuf".
  
  (***********************************************************)
  (* pos, found := search(wrbuf.ents, key)                   *)
  (***********************************************************)
  wp_loadField.
  wp_apply (wp_search with "HentsS").
  iIntros (pos found) "[HentsS %Hsearch]".
  wp_pures.
  
  (***********************************************************)
  (* if found {                                              *)
  (*     ent := wrbuf.ents[pos]                              *)
  (*     return ent.val, ent.del, true                       *)
  (* }                                                       *)
  (* return 0, false, false                                  *)
  (***********************************************************)
  iDestruct (is_slice_small_acc with "HentsS") as "[HentsS HentsC]".
  wp_if_destruct.
  { (* cache hit *)
    wp_loadField.
    unfold spec_search in Hsearch.
    destruct Hsearch as (ent & Hlookup & Hkey).
    wp_apply (wp_SliceGet with "[HentsS]").
    { iFrame.
      iPureIntro.
      by rewrite list_lookup_fmap Hlookup.
    }
    iIntros "[HentsS %Hty]".
    iDestruct ("HentsC" with "HentsS") as "HentsS".
    wp_pures.
    iApply "HΦ".
    iModIntro.
    iSplit; first eauto with iFrame.
    iPureIntro.
    unfold spec_wrbuf__Lookup.
    rewrite Hmods.
    rewrite -elem_of_list_to_map; last by apply NoDup_wrent_to_key_dbval.
    apply elem_of_list_fmap_1_alt with ent.
    { by apply elem_of_list_lookup_2 with (int.nat pos). }
    { rewrite -Hkey. auto using surjective_pairing. }
  }
  (* cache miss *)
  iDestruct ("HentsC" with "HentsS") as "HentsS".
  wp_pures.
  iApply "HΦ".
  iModIntro.
  iSplit; first eauto with iFrame.
  iPureIntro.
  unfold spec_search in Hsearch.
  unfold spec_wrbuf__Lookup.
  rewrite Hmods.
  apply not_elem_of_list_to_map.
  by rewrite wrent_to_key_dbval_key_fmap.
Qed.

(*****************************************************************)
(* func (wrbuf *WrBuf) Put(key, val uint64)                      *)
(*****************************************************************)
Theorem wp_wrbuf__Put wrbuf (key : u64) (val : u64) m :
  {{{ own_wrbuf_xtpls wrbuf m }}}
    WrBuf__Put #wrbuf #key #val
  {{{ RET #(); own_wrbuf_xtpls wrbuf (<[ key := Value val ]> m) }}}.
Proof.
  iIntros (Φ) "Hwrbuf HΦ".
  wp_call.
  iNamed "Hwrbuf".

  (***********************************************************)
  (* pos, found := search(wrbuf.ents, key)                   *)
  (***********************************************************)
  wp_loadField.
  wp_apply (wp_search with "HentsS").
  iIntros (pos found) "[HentsS %Hsearch]".
  wp_pures.

  (***********************************************************)
  (* if found {                                              *)
  (*     ent := &wrbuf.ents[pos]                             *)
  (*     ent.val = val                                       *)
  (*     ent.wr  = true                                      *)
  (*     return                                              *)
  (* }                                                       *)
  (***********************************************************)
  iDestruct (is_slice_small_acc with "HentsS") as "[HentsS HentsC]".
  wp_if_destruct.
  { (* cache hit *)
    wp_loadField.
    (* Handling [SliceRef]; a spec would help. *)
    wp_lam.
    wp_pures.
    unfold spec_search in Hsearch.
    destruct Hsearch as (ent & Hlookup & Hkey).
    wp_apply (wp_slice_len).
    iDestruct (is_slice_small_sz with "HentsS") as "%HentsSz".
    rewrite fmap_length in HentsSz.
    wp_if_destruct; first last.
    { destruct Heqb0.
      apply lookup_lt_Some in Hlookup.
      rewrite HentsSz in Hlookup. word.
    }
    wp_apply (wp_slice_ptr).
    wp_pures.
    unfold is_slice_small.
    iDestruct "HentsS" as "[HentsA [%HentsLen %HentsCap]]".
    iDestruct (update_array (off:=int.nat pos) with "HentsA") as "[HentsP HentsA]".
    { by rewrite list_lookup_fmap Hlookup. }
    iDestruct (struct_fields_split with "HentsP") as "HentsP".
    iNamed "HentsP".
    (* update [val] *)
    wp_apply (wp_storeField with "[val]"); first auto.
    { iNext.
      iExactEq "val".
      do 3 f_equal.
      word.
    }
    iIntros "val".
    wp_pures.
    (* update [wr] *)
    wp_apply (wp_storeField with "[wr]"); first auto.
    { iNext.
      iExactEq "wr".
      do 3 f_equal.
      word.
    }
    iIntros "wr".
    word_cleanup.
    set entR := (entsS.(Slice.ptr) +ₗ[_] (int.Z pos)).
    set ent' := (ent.1.1.1, val, true, ent.2).
    iDestruct (struct_fields_split entR 1%Qp WrEnt (wrent_to_val ent')
                with "[key val wr tpl]") as "HentsP".
    { rewrite /struct_fields. by iFrame. }
    iDestruct ("HentsA" with "HentsP") as "HentsA".
    iDestruct ("HentsC" with "[HentsA]") as "HentsS".
    { iFrame.
      iPureIntro.
      by rewrite -HentsLen insert_length.
    }
    wp_pures.
    iApply "HΦ".
    iModIntro.
    unfold own_wrbuf_xtpls.
    do 2 iExists _.
    iFrame.
    iSplit; first by rewrite -list_fmap_insert.
    iPureIntro.
    split.
    { (* prove [NoDup] *)
      do 3 rewrite list_fmap_insert.
      subst ent'.
      simpl.
      replace (<[ _ := _ ]> ents.*1.*1.*1) with ents.*1.*1.*1; first done.
      symmetry.
      apply list_insert_id.
      do 3 rewrite list_lookup_fmap.
      by rewrite Hlookup.
    }
    { (* prove insertion to list -> insertion to map representation *)
      rewrite Hmods.
      rewrite list_fmap_insert.
      subst ent' key. unfold wrent_to_key_dbval. simpl.
      apply list_to_map_insert with (to_dbval ent.1.2 ent.1.1.2); first by apply NoDup_wrent_to_key_dbval.
      by rewrite list_lookup_fmap Hlookup.
    }
  }
    
  (***********************************************************)
  (* ent := WrEnt {                                          *)
  (*     key : key,                                          *)
  (*     val : val,                                          *)
  (*     wr  : true,                                         *)
  (* }                                                       *)
  (* wrbuf.ents = append(wrbuf.ents, ent)                    *)
  (***********************************************************)
  wp_pures.
  wp_loadField.
  iDestruct ("HentsC" with "HentsS") as "HentsS".
  wp_apply (wp_SliceAppend' with "[HentsS]"); [by auto 10 | by auto 10 | iFrame |].
  iIntros (entsS') "HentsS".
  wp_storeField.
  
  (* return, cache hit *)
  iModIntro.
  iApply "HΦ".
  unfold spec_search in Hsearch.
  set ents' := (ents ++ [(key, val, true, null)]).
  unfold own_wrbuf_xtpls.

  iExists _, ents'.
  iFrame.
  iSplit; first by rewrite fmap_app.
  iPureIntro.
  split.
  { (* prove [NoDup] *)
    do 3 rewrite fmap_app.
    simpl.
    apply NoDup_app_comm.
    apply NoDup_app.
    split; first by apply NoDup_singleton.
    split; last done.
    intros x H.
    apply elem_of_list_singleton in H.
    by subst x.
  }
  { (* prove insertion to list -> insertion to map representation *)
    symmetry.
    rewrite Hmods.
    subst ents'.
    rewrite fmap_app.
    apply list_to_map_snoc.
    by rewrite wrent_to_key_dbval_key_fmap.
  }
Qed.

(*****************************************************************)
(* func (wrbuf *WrBuf) Delete(key uint64)                        *)
(*****************************************************************)
Theorem wp_wrbuf__Delete wrbuf (key : u64) m :
  {{{ own_wrbuf_xtpls wrbuf m }}}
    WrBuf__Delete #wrbuf #key
  {{{ RET #(); own_wrbuf_xtpls wrbuf (<[ key := Nil ]> m) }}}.
Proof.
  iIntros (Φ) "Hwrbuf HΦ".
  wp_call.
  iNamed "Hwrbuf".

  (***********************************************************)
  (* pos, found := search(wrbuf.ents, key)                   *)
  (***********************************************************)
  wp_loadField.
  wp_apply (wp_search with "HentsS").
  iIntros (pos found) "[HentsS %Hsearch]".
  wp_pures.

  (***********************************************************)
  (* if found {                                              *)
  (*     ent := &wrbuf.ents[pos]                             *)
  (*     ent.wr = false                                      *)
  (*     return                                              *)
  (* }                                                       *)
  (***********************************************************)
  iDestruct (is_slice_small_acc with "HentsS") as "[HentsS HentsC]".
  wp_if_destruct.
  { (* cache hit *)
    wp_loadField.
    (* Handling [SliceRef]; a spec would help. *)
    wp_lam.
    wp_pures.
    unfold spec_search in Hsearch.
    destruct Hsearch as (ent & Hlookup & Hkey).
    wp_apply (wp_slice_len).
    iDestruct (is_slice_small_sz with "HentsS") as "%HentsSz".
    rewrite fmap_length in HentsSz.
    wp_if_destruct; first last.
    { destruct Heqb0.
      apply lookup_lt_Some in Hlookup.
      rewrite HentsSz in Hlookup. word.
    }
    wp_apply (wp_slice_ptr).
    wp_pures.
    unfold is_slice_small.
    iDestruct "HentsS" as "[HentsA [%HentsLen %HentsCap]]".
    iDestruct (update_array (off:=int.nat pos) with "HentsA") as "[HentsP HentsA]".
    { by rewrite list_lookup_fmap Hlookup. }
    iDestruct (struct_fields_split with "HentsP") as "HentsP".
    iNamed "HentsP".
    (* update [wr] *)
    wp_apply (wp_storeField with "[wr]"); first auto.
    { iNext.
      iExactEq "wr".
      do 3 f_equal.
      word.
    }
    iIntros "wr".
    word_cleanup.
    set entR := (entsS.(Slice.ptr) +ₗ[_] (int.Z pos)).
    set ent' := (ent.1.1.1, ent.1.1.2, false, ent.2).
    iDestruct (struct_fields_split entR 1%Qp WrEnt (wrent_to_val ent')
                with "[key val wr tpl]") as "HentsP".
    { rewrite /struct_fields. by iFrame. }
    iDestruct ("HentsA" with "HentsP") as "HentsA".
    iDestruct ("HentsC" with "[HentsA]") as "HentsS".
    { iFrame.
      iPureIntro.
      by rewrite -HentsLen insert_length.
    }
    wp_pures.
    iApply "HΦ".
    iModIntro.
    unfold own_wrbuf_xtpls.
    do 2 iExists _.
    iFrame.
    iSplit; first by rewrite -list_fmap_insert.
    iPureIntro.
    split.
    { (* prove [NoDup] *)
      do 3 rewrite list_fmap_insert.
      subst ent'.
      simpl.
      replace (<[ _ := _ ]> ents.*1.*1.*1) with ents.*1.*1.*1; first done.
      symmetry.
      apply list_insert_id.
      do 3 rewrite list_lookup_fmap.
      by rewrite Hlookup.
    }
    { (* prove insertion to list -> insertion to map representation *)
      rewrite Hmods.
      rewrite list_fmap_insert.
      subst ent' key. unfold wrent_to_key_dbval. simpl.
      apply list_to_map_insert with (to_dbval ent.1.2 ent.1.1.2); first by apply NoDup_wrent_to_key_dbval.
      by rewrite list_lookup_fmap Hlookup.
    }
  }
    
  (***********************************************************)
  (* ent := WrEnt {                                          *)
  (*     key : key,                                          *)
  (*     del : true,                                         *)
  (* }                                                       *)
  (* wrbuf.ents = append(wrbuf.ents, ent)                    *)
  (***********************************************************)
  wp_pures.
  wp_loadField.
  iDestruct ("HentsC" with "HentsS") as "HentsS".
  wp_apply (wp_SliceAppend' with "[HentsS]"); [auto 10 | auto 10 | iFrame |].
  iIntros (entsS') "HentsS".
  wp_storeField.
  
  (* return, cache hit *)
  iModIntro.
  iApply "HΦ".
  unfold spec_search in Hsearch.
  (* [(U64 0)] is the zero-value of [u64]. *)
  set ents' := (ents ++ [(key, (U64 0), false, null)]).
  unfold own_wrbuf_xtpls.

  iExists _, ents'.
  iFrame.
  iSplit; first by rewrite fmap_app.
  iPureIntro.
  split.
  { (* prove [NoDup] *)
    do 3 rewrite fmap_app.
    simpl.
    apply NoDup_app_comm.
    apply NoDup_app.
    split; first by apply NoDup_singleton.
    split; last done.
    intros x H.
    apply elem_of_list_singleton in H.
    by subst x.
  }
  { (* prove insertion to list -> insertion to map representation *)
    symmetry.
    rewrite Hmods.
    subst ents'.
    rewrite fmap_app.
    apply list_to_map_snoc.
    by rewrite wrent_to_key_dbval_key_fmap.
  }
Qed.

(*****************************************************************)
(* func (wrbuf *WrBuf) Clear()                                   *)
(*****************************************************************)
Theorem wp_wrbuf__Clear wrbuf m :
  {{{ own_wrbuf_xtpls wrbuf m }}}
    WrBuf__Clear #wrbuf
  {{{ RET #(); own_wrbuf_xtpls wrbuf ∅ }}}.
Proof.
  iIntros (Φ) "Hwrbuf HΦ".
  wp_call.
  iNamed "Hwrbuf".

  (***********************************************************)
  (* wrbuf.ents = wrbuf.ents[ : 0]                           *)
  (***********************************************************)
  wp_loadField.
  wp_apply (wp_SliceTake); first word.
  wp_apply (wp_storeField with "Hents"); first eauto.
  iIntros "Hents".
  wp_pures.

  iApply "HΦ".
  iModIntro.
  iExists _, [].
  iDestruct (is_slice_take_cap _ _ _ (U64 0) with "HentsS") as "HentsS"; first word.
  change (int.nat 0) with 0%nat.
  rewrite take_0.
  do 2 rewrite fmap_nil.
  iFrame.
  iPureIntro.
  split; [apply NoDup_nil_2 | done].
Qed.

End heap.
