From Perennial.goose_lang Require Import prelude.
From Perennial.goose_lang Require Export ffi.grove_prelude.
From Perennial.program_proof Require Import proof_prelude.
From Perennial.goose_lang Require Export ffi.grove_filesys_axioms.
From Perennial.program_proof.ctrexample Require Import interface.
From Perennial.program_proof Require Import marshal_proof.
From Goose.github_com.mit_pdos.gokv.ctrexample Require Import server.
From Perennial.goose_lang Require Export crash_lock crash_borrow.
From Perennial.program_proof.ctrexample Require Import wpc_proofmode.
From Perennial.program_proof.grove_shared Require Import urpc_proof.
From Perennial.goose_lang Require Import persistent_readonly.

Section server_proof.

Context `{!heapGS Σ}.
Context `{!filesysG Σ}.
Context `{!inG Σ mono_natUR}.
Context `{stagedG Σ}.

Definition ctrname := "ctr".

Definition own_CtrServer_durable (c:u64) : iProp Σ :=
  ∃ l, ctrname f↦ l ∗
               (⌜l = []⌝ ∗ ⌜c = U64 0⌝ ∨ ⌜has_encoding l [EncUInt64 c]⌝)
.

Definition own_CtrServer_ghost γ (c:u64) : iProp Σ :=
  counter_own γ (int.nat c)
.

Definition own_CtrServer (s:loc) (c:u64) : iProp Σ :=
  "Hval" ∷ s ↦[CtrServer :: "val"] #c ∗
  "Hfilename" ∷ s ↦[CtrServer :: "filename"] #(str ctrname)
.

Definition ctrServerN := nroot .@ "ctrserver".

Definition is_CtrServer γ (s:loc) : iProp Σ :=
  ∃ mu,
  "#Hmu" ∷ readonly (s ↦[CtrServer :: "mu"] mu) ∗
  "#HmuInv" ∷ is_crash_lock ctrServerN mu
  (∃ c, own_CtrServer_ghost γ c ∗
        own_CtrServer_durable c ∗
        own_CtrServer s c
  )
  (∃ c, own_CtrServer_ghost γ c ∗
        own_CtrServer_durable c)
.

Lemma wpc_CtrServer__MakeDurable γ (s:loc) c c' Q {stk E}:
  {{{
       own_CtrServer_ghost γ c ∗ own_CtrServer_durable c ∗ own_CtrServer s c'
                           ∗ (own_CtrServer_ghost γ c ={E}=∗ own_CtrServer_ghost γ c' ∗ Q)
  }}}
    CtrServer__MakeDurable #s @ stk ; E
  {{{
       RET #(); own_CtrServer_ghost γ c' ∗ own_CtrServer_durable c' ∗ own_CtrServer s c' ∗ Q
  }}}
  {{{
       ∃ c'', own_CtrServer_ghost γ c'' ∗ own_CtrServer_durable c''
  }}}.
Proof.
  iIntros (Φ Φc) "Hpre HΦ".
  iDestruct "Hpre" as "(Hghost & Hdur & Hvol & Hfupd)".
  unfold CtrServer__MakeDurable.
  wpc_pures.
  { iLeft in "HΦ". iApply "HΦ". iExists _; iFrame. }
  iCache with "Hghost Hdur HΦ".
  {
    iLeft in "HΦ".
    iApply "HΦ".
    iExists _; iFrame.
  }

  wpc_wpapply (wp_new_enc).
  iIntros (enc) "Henc".
  iNamed 1.
  wpc_pures.
  iNamed "Hvol".
  wpc_loadField.
  wpc_wpapply (wp_Enc__PutInt with "[$Henc]").
  { done. }
  iIntros "Henc".
  iNamed 1.
  wpc_pures.

  wpc_wpapply (wp_Enc__Finish with "[$Henc]").
  iIntros (sl data) "(%Henc & %Hlen & Hslice)".
  iNamed 1.
  wpc_loadField.

  iDestruct "Hdur" as (old_data) "[Hdur %Hpure]".
  iApply wpc_cfupd.
  wpc_apply (wpc_Write with "[Hdur Hslice]").
  {
    iFrame.
  }
  iSplit.
  { (* crash-condition of Write implies our crash condition *)
    iLeft in "HΦ".
    iIntros "Hcrash".
    unfold cfupd.
    iIntros "_".
    iApply "HΦ".
    iDestruct "Hcrash" as "[Hdur|Hdur]".
    { (* write didn't go through *)
      iExists _. iFrame.
      iExists _; iFrame.
      done.
    }
    { (* write went through *)
      iExists _.
      iSplitR "Hdur"; last first.
      {
        iModIntro. iExists _; iFrame.
        iRight.
        done.
      }
      iMod ("Hfupd" with "Hghost") as "[$ _]".
      done.
    }
  }
  { (* proof after Write completes *)
    iNext.
    iIntros "[Hdur Hslice]".
    iMod ("Hfupd" with "Hghost") as "[Hghost HQ]".
    iCache with "Hdur Hghost HΦ".
    {
      iLeft in "HΦ".
      iModIntro.
      iApply "HΦ".
      iExists _; iFrame.
      iExists _; iFrame.
      iRight.
      done.
    }
    wpc_pures.
    iModIntro.
    iRight in "HΦ".
    iApply "HΦ".
    iFrame.
    iExists _; iFrame.
    iRight.
    done.
  }
Qed.

Lemma wp_CtrServer__FetchAndIncrement γ (s:loc) Post :
  {{{
       is_CtrServer γ s ∗
       FAISpec γ [] Post
  }}}
    CtrServer__FetchAndIncrement #s
  {{{
       (x:u64), RET #x; (∀ l, ⌜has_encoding l [EncUInt64 x]⌝ -∗ Post l)
  }}}
.
Proof.
  iIntros (Φ) "[#Hsrv Hpre] HΦ".
  wp_lam.
  iNamed "Hsrv".
  wp_loadField.
  wp_apply (acquire_spec with "HmuInv").
  { done. }
  iIntros "Hres".
  wp_pures.
  wp_apply wpc_wp.

  wpc_apply (use_crash_locked with "Hres").
  { done. }
  iSplit.
  { by instantiate (1:=True%I). }
  iIntros "H".
  iDestruct "H" as (c) "(Hghost&Hdur&Hvol)".

  iNamed "Hvol".
  iCache with "Hghost Hdur".
  {
    iSplitL ""; first done.
    iExists c; iFrame.
  }

  wpc_loadField.
  wpc_pures.
  wpc_loadField.
  wpc_pures.
  wpc_storeField.
  wpc_pures.
  wpc_apply (wpc_CtrServer__MakeDurable with "[$Hghost $Hdur $Hval $Hfilename Hpre]").
  {
    unfold FAISpec.
    simpl.
    iIntros "Hghost".
    iMod ("Hpre" with "Hghost") as "[Hghost HQ]".
    unfold own_CtrServer_ghost.
    replace ((int.nat c) + 1)%nat with (int.nat (word.add c 1)); last first.
    {
      admit.
    }
    iFrame "Hghost".
    iExact "HQ".
  }
  iSplit.
  { (* crash-condition of MakeDurable ==> our crash condition *)
    eauto.
  }
  iNext.
  iIntros "(Hghost & Hdur & Hvol & HQ)".
  iCache with "Hghost Hdur".
  { iSplitL ""; first done. iExists _; iFrame. }
  wpc_pures.
  wpc_loadField.

  wpc_apply (wpc_crash_borrow_inits _ _ _ _
  (∃ c, own_CtrServer_ghost γ c ∗ own_CtrServer_durable c ∗ own_CtrServer s c)
                                    (∃ c, own_CtrServer_ghost γ c ∗ own_CtrServer_durable c)
               with "[] [Hvol Hdur Hghost] []").
  { admit. (* FIXME: what is this about? *) }
  {
    iExists _; iFrame.
  }
  {
    iModIntro.
    iIntros "H".
    iDestruct "H" as (c2) "(H & H2 & _)".
    iExists _; iFrame.
  }
  iIntros "Hres".

  iApply (wpc_crash_mono _ _ _ _ _ (True) with "[]").
  {
    iIntros.
    iSplitL ""; first done.
    iFrame.
  }
  iApply wp_wpc.
  wp_apply (release_spec with "[Hres]").
  { done. }
  { unfold crash_locked.
    iFrame.
    unfold is_crash_lock.
    iFrame "HmuInv".
    (* FIXME: lost the lock.locked because of use_crash_locked binding too far *)
    admit.
  }

  wp_pures.
  iSplitL "HΦ".
  {
    iModIntro. iIntros.
    admit.
  }
Admitted.

Definition crash_cond γ : iProp Σ :=
 ∃ c, own_CtrServer_durable c ∗
 own_CtrServer_ghost γ c.

Context `{urpcregG Σ}.

Lemma wpc_ServerMain γurpc_gn (γ:gname) :
  is_CtrServer_urpc γurpc_gn γ -∗
  crash_cond γ -∗
        WPC main #() @ NotStuck; ⊤
  {{
      v, True
  }}
  {{
       crash_cond γ
  }}
.
Proof using Type*.
  iIntros "#[Hhandler Hdom] Hpre".
  unfold main.
  wpc_pures.
  {
    iFrame.
  }
  iDestruct "Hpre" as (c) "[Hdur Hghost]".
  iCache with "Hdur Hghost".
  { iExists _; iFrame. }

  wpc_wpapply (wp_allocStruct).
  {
    apply zero_val_ty'.
    eauto.
  }
  iIntros (s) "Hs".
  iNamed 1.
  iDestruct (struct_fields_split with "Hs") as "(Hmu & Hval & Hfilename & _)".
  simpl.

  wpc_pures.
  wpc_bind (lock.new #()).
  wpc_frame.
  (* This forces us to have NotStuck *)
  wp_apply (wp_new_free_crash_lock).
  iIntros (mu).
  iIntros "HmuInv".
  iNamed 1.

  wpc_storeField.
  wpc_pures.
  wpc_storeField.
  wpc_pures.

  wpc_loadField.

  iDestruct "Hdur" as (data) "[Hdur %Hpure]".
  wpc_apply (wpc_Read with "Hdur").
  iSplit.
  {
    iIntros.
    iExists _; iFrame.
    iExists data; iFrame.
    done.
  }
  iNext.
  iIntros (sl) "[Hsl Hdur]".

  iCache with "Hdur Hghost".
  { iExists _; iFrame. iExists _; iFrame. done. }

  wpc_pures.

  wpc_bind (@If _ _ _ _).
  wpc_frame.

  iDestruct (is_slice_sz with "Hsl") as %HslSize.
  wp_apply (wp_slice_len).
  wp_pures.
  wp_apply (wp_If_join ("Hval" ∷ s ↦[CtrServer :: "val"] #c)
                       with "[Hval Hsl]"
           ).
  {
    iSplit.
    {
      iIntros "%Hslice_empty".
      wp_storeField.
      assert (c = 0) as ->.
      {
        apply bool_decide_eq_true in Hslice_empty.
        replace (sl.(Slice.sz)) with (U64 0) in HslSize by naive_solver.
        destruct Hpure as [Hpure|Hbad].
        { naive_solver. }
        exfalso.
        replace (int.nat 0) with (0)%nat in HslSize by word.
        apply nil_length_inv in HslSize.
        rewrite HslSize in Hbad.
        apply has_encoding_length in Hbad.
        simpl in Hbad.
        lia.
      }
      iFrame.
      done.
    }
    {
      iIntros "%Hslice_nonEmpty".
      destruct Hpure as [Hbad|Hpure].
      { exfalso. apply bool_decide_eq_false in Hslice_nonEmpty.
        destruct Hbad as [Hbad _].
        rewrite Hbad in HslSize.
        simpl in HslSize.
        replace (sl.(Slice.sz)) with (U64 0) in Hslice_nonEmpty by word.
        done.
      }
      iDestruct (is_slice_to_small with "Hsl") as "Hsl".
      wp_apply (wp_new_dec with "Hsl").
      { done. }
      iIntros (dec) "Hdec".
      wp_apply (wp_Dec__GetInt with "Hdec").
      iIntros "_".
      wp_storeField.
      iFrame.
      done.
    }
  }
  iNamed 1.
  iNamed 1.

  wpc_pures.
  wpc_apply (alloc_crash_lock
               ctrServerN _ _ _ mu
               (∃ c, own_CtrServer_ghost γ c ∗
                                         own_CtrServer_durable c ∗
                                         own_CtrServer s c
               )
               (∃ c, own_CtrServer_ghost γ c ∗
                                         own_CtrServer_durable c)

               ).
  iSplitL "".
  {
    iModIntro.
    iDestruct 1 as (?) "(Hghost & Hdur & Hvol)".
    iExists _; iFrame.
  }

  iSplitL "Hdur Hghost Hfilename Hval".
  {
    iExists _.
    iFrame.
    iExists _; iFrame.
    done.
  }
  iFrame "HmuInv".
  iIntros "#HmuInv".

  iMod (readonly_alloc_1 with "Hmu") as "#Hmu".

  iApply (wpc_crash_mono _ _ _ _ _ (True) with "[]").
  {
    iIntros "_".
    iDestruct 1 as (?) "[Hghost Hdur]".
    iExists _; iFrame.
  }
  iApply wp_wpc.

  wp_apply (map.wp_NewMap).
  iIntros (handlers_ptr) "Hmap".
  wp_pures.

  wp_apply (map.wp_MapInsert with "Hmap").
  iIntros "Hmap".
  wp_pures.

  wp_apply (wp_MakeServer with "[$Hmap]").

  iIntros (rs) "Hsown".
  wp_pures.

  iAssert (is_CtrServer γ s)%I as "Hsrv".
  {
    iExists _; iFrame "#".
  }

  wp_apply (wp_StartServer with "[$Hsown]").
  { rewrite ?dom_insert_L; set_solver. }
  {
    iSplitL "".
    { rewrite /handlers_complete.
      rewrite ?dom_insert_L dom_empty_L. iExactEq "Hdom". f_equal. set_solver. }
    iApply (big_sepM_insert_2 with "").
    { (* FetchAndIncrement handler_is *)
      simpl. iExists _.
      iFrame "Hhandler".

      rewrite /impl_handler_spec.
      iIntros (??????) "!#".
      iIntros (Φ) "Hpre HΦ".
      iDestruct "Hpre" as "(Hreq_sl & Hrep & Hrep_sl & HFAISpec)".
      wp_pures.
      wp_apply (wp_CtrServer__FetchAndIncrement with "[$HFAISpec $Hsrv]").
      iIntros (x) "HPost".
      wp_pures.
      wp_apply (wp_new_enc).
      iIntros (enc) "Henc".
      wp_pures.
      wp_apply (wp_Enc__PutInt with "Henc").
      { done. }
      iIntros "Henc".
      wp_pures.
      wp_apply (wp_Enc__Finish with "Henc").
      iIntros (rep_sl data1) "(%Henc & %Hlen & Hsl)".
      wp_store.
      iApply "HΦ".
      iDestruct (is_slice_to_small with "Hsl") as "$".
      iFrame.
      iApply "HPost".
      done.
    }
    by iApply big_sepM_empty.
  }
  by wp_pures.
Qed.

End server_proof.
