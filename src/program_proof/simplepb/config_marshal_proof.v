From Perennial.program_proof Require Import grove_prelude.
From Goose.github_com.mit_pdos.gokv.simplepb Require Export config.
From Perennial.program_proof Require Import marshal_stateless_proof.
From coqutil.Datatypes Require Import List.

Module Config.
Section Config.

Definition C := list u64.

Definition has_encoding (encoded:list u8) (args:C) : Prop :=
  encoded = u64_le (length args) ++ concat (u64_le <$> args).

Context `{!heapGS Σ}.

Definition own conf_sl (conf:list u64) : iProp Σ :=
  "Hargs_state_sl" ∷ is_slice_small conf_sl uint64T 1 conf.

Lemma wp_Encode conf_sl (conf:C) :
  {{{
        own conf_sl conf
  }}}
    config.EncodeConfig (slice_val conf_sl)
  {{{
        enc enc_sl, RET (slice_val enc_sl);
        ⌜has_encoding enc conf⌝ ∗
        own conf_sl conf ∗
        is_slice enc_sl byteT 1 enc
  }}}.
Proof.
  iIntros (Φ) "Hconf HΦ".
  wp_call.
  iDestruct (is_slice_small_sz with "Hconf") as %Hsz.
  wp_apply (wp_slice_len).
  wp_pures.
  wp_apply (wp_NewSliceWithCap).
  { apply encoding.unsigned_64_nonneg. }
  iIntros (enc_ptr) "Henc_sl".
  simpl.
  replace (int.nat 0) with (0%nat) by word.
  simpl.

  wp_apply (wp_ref_to).
  { done. }
  iIntros (enc) "Henc".
  wp_pures.
  wp_apply (wp_slice_len).
  wp_load.
  wp_apply (wp_WriteInt with "Henc_sl").
  iIntros (enc_sl) "Henc_sl".
  wp_store.
  simpl.

  replace (conf_sl.(Slice.sz)) with (U64 (length conf)) by word.
  set (P:=(λ (i:u64),
      ∃ enc_sl,
      "Henc_sl" ∷ is_slice enc_sl byteT 1 ((u64_le (length conf)) ++ concat (u64_le <$> (take (int.nat i) conf))) ∗
      "Henc" ∷ enc ↦[slice.T byteT] (slice_val enc_sl)
    )%I)
  .
  wp_apply (wp_forSlice P with "[] [$Hconf Henc Henc_sl]").
  {
    iIntros (i srv).
    clear Φ.
    iIntros (Φ) "!# (HP & %Hi_bound & %Hlookup) HΦ".
    iNamed "HP".

    wp_pures.
    wp_load.
    wp_apply (wp_WriteInt with "Henc_sl").
    iIntros (enc_sl') "Henc_sl".
    wp_store.
    iModIntro.
    iApply "HΦ".
    unfold P.
    iExists _; iFrame "Henc".
    iApply to_named.
    iExactEq "Henc_sl".
    f_equal.

    (* Start pure proof *)
    (* prove that appending the encoded next entry results in a concatenation of
       the first (i+1) entries *)
    rewrite -app_assoc.
    f_equal.
    replace (u64_le srv) with (concat (u64_le <$> [srv])) by done.
    rewrite -concat_app.
    rewrite -fmap_app.
    replace (int.nat (word.add i 1)) with (int.nat i + 1)%nat by word.
    f_equal.
    f_equal.
    (* TODO: list_solver *)
    rewrite take_more; last word.
    f_equal.
    apply list_eq.
    intros.
    destruct i0.
    {
      simpl.
      rewrite lookup_take; last lia.
      rewrite lookup_drop.
      rewrite -Hlookup.
      f_equal.
      word.
    }
    {
      simpl.
      rewrite lookup_nil.
      rewrite lookup_take_ge; last word.
      done.
    }
    (* End pure proof *)
  }
  {
    unfold P.
    iExists _; iFrame.
  }
  iIntros "[HP Hconf_sl]".
  iNamed "HP".
  wp_pures.
  wp_load.
  iApply "HΦ".
  iModIntro.
  iFrame.
  rewrite -Hsz.
  iPureIntro.
  unfold has_encoding.
  rewrite firstn_all.
  done.
Qed.

Lemma list_copy_one_more_element {A} (l:list A) i e d:
  l !! i = Some e →
  <[i := e]> (take i l ++ replicate (length (l) - i) d)
    =
  (take (i + 1) l) ++ replicate (length (l) - i - 1) d.
Proof.
  intros Hlookup.
  apply list_eq.
  intros j.
  destruct (decide (j = i)) as [Heq|Hneq].
  {
    rewrite Heq.
    rewrite list_lookup_insert; last first.
    {
      rewrite app_length.
      rewrite replicate_length.
      apply lookup_lt_Some in Hlookup.
      rewrite take_length_le.
      { lia. }
      lia.
    }
    {
      rewrite lookup_app_l; last first.
      {
        rewrite take_length_le.
        { word. }
        apply lookup_lt_Some in Hlookup.
        word.
      }
      rewrite lookup_take; last word.
      done.
    }
  }
  {
    rewrite list_lookup_insert_ne; last done.
    admit.
  }
Admitted.

Lemma wp_Decode enc enc_sl (conf:C) :
  {{{
        ⌜has_encoding enc conf⌝ ∗
        is_slice_small enc_sl byteT 1 enc
  }}}
    config.DecodeConfig (slice_val enc_sl)
  {{{
        conf_sl, RET (slice_val conf_sl); own conf_sl conf
  }}}.
Proof.
  iIntros (Φ) "[%Henc Henc_sl] HΦ".
  wp_call.
  wp_apply (wp_ref_to).
  { done. }
  iIntros (enc_ptr) "Henc".
  wp_pures.
  wp_apply (wp_ref_of_zero).
  { done. }
  iIntros (configLen_ptr) "HconfigLen".
  wp_pures.
  wp_load.
  rewrite Henc.
  wp_apply (wp_ReadInt with "[$Henc_sl]").
  iIntros (enc_sl') "Henc_sl".
  wp_store.
  wp_store.

  wp_load.
  wp_apply (wp_NewSlice).
  iIntros (conf_sl) "Hconf_sl".
  wp_pures.

  iDestruct (is_slice_small_sz with "Henc_sl") as %Henc_sz.
  (* prove that conf's length is below U64_MAX *)
  assert (int.nat (length conf) = length conf) as Hlen_no_overflow.
  {
    assert (length (concat (u64_le <$> conf)) ≥ length conf).
    {
      rewrite (length_concat_same_length 8).
      {
        rewrite fmap_length.
        word.
      }
      rewrite Forall_fmap.
      apply Forall_true.
      intros.
      done.
    }
    word.
  }
  rewrite Hlen_no_overflow.

  iDestruct (is_slice_to_small with "Hconf_sl") as "Hconf_sl".
  set (P:=(λ (i:u64),
      ∃ enc_sl,
      "Henc_sl" ∷ is_slice_small enc_sl byteT 1 (concat (u64_le <$> (drop (int.nat i) conf))) ∗
      "Henc" ∷ enc_ptr ↦[slice.T byteT] (slice_val enc_sl) ∗
      "Hconf_sl" ∷ is_slice_small conf_sl uint64T 1 ((take (int.nat i) conf) ++
                                                replicate (length conf - int.nat i) (U64 0))
    )%I)
  .
  wp_apply (wp_ref_to).
  { repeat econstructor. }
  iIntros (i_ptr) "Hi".
  wp_pures.

  iAssert (∃ (i:u64),
              "Hi" ∷ i_ptr ↦[uint64T] #i ∗
              "%Hi_bound" ∷  ⌜int.nat i ≤ length conf⌝ ∗
              P i)%I with "[Henc Henc_sl Hi Hconf_sl]" as "HP".
  {
    iExists _.
    iFrame.
    iSplitR; first iPureIntro.
    { word. }
    iExists _; iFrame.
    replace (int.nat 0) with 0%nat by word.
    rewrite Nat.sub_0_r.
    iFrame.
  }

  wp_forBreak_cond.
  iNamed "HP".
  iNamed "HP".

  wp_pures.
  wp_load.
  iDestruct (is_slice_small_sz with "Hconf_sl") as %Hconf_sz.

  (* Show that int.nat conf_sl.(Slice.sz) == int.nat (length conf) *)
  rewrite app_length in Hconf_sz.
  rewrite replicate_length in Hconf_sz.
  rewrite take_length_le in Hconf_sz; last first.
  { word. }
  assert (int.nat conf_sl.(Slice.sz) = length conf) as Hconf_sz_eq.
  { word. }

  wp_apply (wp_slice_len).
  wp_pures.

  wp_if_destruct.
  { (* continue with the loop *)
    assert (int.nat i < length conf) as Hi_bound_lt.
    {
      assert (int.nat i < int.nat conf_sl.(Slice.sz)) as Heqb_nat by word.
      rewrite Hconf_sz_eq in Heqb_nat.
      done.
    }

    wp_pures.
    wp_load.
    destruct (drop (int.nat i) conf) as [|] eqn:Hdrop.
    { (* contradiction with i < length *)
      exfalso.
      apply (f_equal length) in Hdrop.
      simpl in Hdrop.
      rewrite drop_length in Hdrop.
      word.
    }
    rewrite fmap_cons.
    rewrite concat_cons.
    wp_apply (wp_ReadInt with "[$Henc_sl]").
    iIntros (enc_sl1) "Henc_sl".
    wp_pures.
    wp_load.
    wp_apply (wp_SliceSet with "[$Hconf_sl]").
    {
      iPureIntro.
      apply lookup_lt_is_Some_2.
      rewrite app_length.
      rewrite take_length_le; last word.
      rewrite replicate_length.
      word.
    }
    iIntros "Hconf_sl".
    wp_pures.
    wp_store.
    wp_load.
    wp_store.

    iLeft.
    iModIntro.
    iSplitR; first done.
    iFrame "∗".
    iExists _; iFrame "∗".
    iSplitR.
    {
      iPureIntro. word.
    }
    unfold P.
    iExists _; iFrame "∗".
    replace (int.nat (word.add i 1)) with (int.nat i + 1)%nat by word.
    iSplitL "Henc_sl".
    {
      iApply to_named.
      iExactEq "Henc_sl".
      f_equal.
      rewrite -drop_drop.
      rewrite Hdrop.
      simpl.
      done.
    }
    {
      iApply to_named.
      iExactEq "Hconf_sl".
      f_equal.
      rewrite list_copy_one_more_element.
      {
        f_equal.
        f_equal.
        word.
      }
      Check lookup_drop.
      replace (int.nat i) with (int.nat i + 0)%nat by word.
      rewrite -(lookup_drop _ _ 0).
      rewrite Hdrop.
      done.
    }
  }
  (* done with loop *)

  iRight.
  iModIntro.
  iSplitR; first done.
  wp_pures.
  iApply "HΦ".

  replace (length conf - int.nat i)%nat with (0)%nat by word.
  replace (int.nat i) with (length conf) by word.
  simpl.
  rewrite app_nil_r.
  rewrite firstn_all.
  iFrame.
  done.
Qed.

End Config.
End Config.
