From RecordUpdate Require Import RecordSet.

From Perennial.goose_lang Require Import crash_modality.
From Perennial.program_logic Require Import atomic.

From Goose.github_com.mit_pdos.perennial_examples Require Import async_mem_alloc_inode.

(* TODO: alloc_crash_proof must be imported early since otherwise it messes up a
bunch of things, like Z_scope, encode, and val *)
From Perennial.algebra Require Import own_discrete.
From Perennial.program_proof.examples Require Import alloc_crash_proof.
From Perennial.goose_lang.lib Require Import lock.crash_lock.
From Perennial.program_proof Require Import async_disk_prelude.
From Perennial.goose_lang.lib Require Import into_val typed_slice.
From Perennial.goose_lang Require Import crash_borrow.

From Perennial.program_proof Require Import async_marshal_block async_disk_lib.

Definition InodeMaxBlocks: Z := 511.

Module inode.
  Record t :=
    mk { (* addresses consumed by this inode *)
         addrs: gset u64;
         blocks: list Block; }.
  Global Instance _eta: Settable _ := settable! mk <addrs; blocks>.
  Global Instance _witness: Inhabited t := populate!.

  Definition wf σ := length σ.(blocks) ≤ InodeMaxBlocks.
  Definition size σ := length σ.(blocks).
End inode.

Hint Unfold inode.wf InodeMaxBlocks : word.

Section goose.
Context `{!heapGS Σ}.
Context `{!stagedG Σ}.
Context `{!allocG Σ}.

(* The client picks the namespaces that we use for everything. *)
Context (inodeN allocN: namespace).

Implicit Types (σ: inode.t) (addr: u64).
Implicit Types (l:loc) (γ:gname) (P: inode.t → iProp Σ) (Pcrash : ∀ (H: heapGS Σ), inode.t → iProp Σ).

Definition is_inode_durable addr σ (addrs: list u64) : iProp Σ :=
  ∃ (hdr: Block),
    "%Hwf" ∷ ⌜inode.wf σ⌝ ∗
    "%Hencoded" ∷ ⌜block_encodes hdr ([EncUInt64 (length addrs)] ++ (EncUInt64 <$> addrs))⌝ ∗
    "%Haddrs_set" ∷ ⌜list_to_set addrs = σ.(inode.addrs)⌝ ∗
    "Hhdr" ∷ int.Z addr d↦[∅] hdr ∗
    (* TODO: this does not support reading lock-free; we could make it [∃ q,
    int.Z a d↦{q} b], but that wouldn't support lock-free writes if we
    implemented those *)
    "Hdata" ∷ [∗ list] a;b ∈ addrs;σ.(inode.blocks), int.Z a d↦[∅] b
.
Local Hint Extern 1 (environments.envs_entails _ (is_inode_durable _ _ _)) => unfold is_inode_durable : core.

Theorem is_inode_durable_read addr σ addrs :
  is_inode_durable addr σ addrs -∗
    ∃ hdr,
      "%Hwf" ∷ ⌜inode.wf σ⌝ ∗
      "%Hencoded" ∷ ⌜block_encodes hdr ([EncUInt64 (length addrs)] ++ (EncUInt64 <$> addrs))⌝ ∗
      "%Haddrs_set" ∷ ⌜list_to_set addrs = σ.(inode.addrs)⌝ ∗
      "Hhdr" ∷ int.Z addr d↦[∅] hdr ∗
      "Hdata" ∷ ([∗ list] a;b ∈ addrs;σ.(inode.blocks), int.Z a d↦[∅] b) ∗
      "Hdurable" ∷ □(int.Z addr d↦[∅] hdr -∗
                    ([∗ list] a;b ∈ addrs;σ.(inode.blocks), int.Z a d↦[∅] b) -∗
                   is_inode_durable addr σ addrs).
Proof.
  iNamed 1.
  iExists _; iFrame "∗ %".
  iIntros "!> Hhdr Hdata".
  iExists _; iFrame "∗ %".
Qed.

Definition inode_linv (l:loc) (addr:u64) σ : iProp Σ :=
  ∃ (addr_s: Slice.t) (addrs: list u64),
    "%Hwf" ∷ ⌜inode.wf σ⌝ ∗
    "Hdurable" ∷ is_inode_durable addr σ addrs ∗
    "addrs" ∷ l ↦[Inode :: "addrs"] (slice_val addr_s) ∗
    "Haddrs" ∷ is_slice addr_s uint64T 1 addrs
.
Local Hint Extern 1 (environments.envs_entails _ (inode_linv _ _ _)) => unfold inode_linv : core.

Definition inode_cinv addr σ: iProp Σ :=
  ∃ addrs, is_inode_durable addr σ addrs.
Local Hint Extern 1 (environments.envs_entails _ (inode_cinv _ _)) => unfold inode_cinv : core.

Existing Instance persistent_discretizable.

Definition inode_state l d (lref: loc) addr : iProp Σ :=
  "#d" ∷ readonly (l ↦[Inode :: "d"] (disk_val d)) ∗
  "#m" ∷ readonly (l ↦[Inode :: "m"] #lref) ∗
  "#addr" ∷ readonly (l ↦[Inode :: "addr"] #addr).

Definition is_inode l P Pcrash (addr: u64) : iProp Σ :=
  ∃ d (lref: loc),
    "Hro_state" ∷ inode_state l d lref addr ∗
    "#Hlock" ∷ is_crash_lock inodeN #lref
                (∃ σ, "Hlockinv" ∷ inode_linv l addr σ ∗ "HP" ∷ P σ ∗
                     "HPcrash" ∷ (∀ σ, P σ -∗ post_crash (λ H, Pcrash H σ)))
                (post_crash (λ H, ∃ σ, "Hlockcinv" ∷ inode_cinv addr σ ∗ "HP" ∷ Pcrash H σ)).

Definition pre_inode l addr σ : iProp Σ :=
  ∃ d (lref: loc),
    "Hro_state" ∷ inode_state l d lref addr ∗
    "Hfree_lock" ∷ is_free_crash_lock lref ∗
    "Hlockinv" ∷ inode_linv l addr σ.

Global Instance is_inode_durable_crash addr σ addrs:
  IntoCrash (is_inode_durable addr σ addrs) (λ _, is_inode_durable addr σ addrs)%I.
Proof.
  hnf; iIntros "Hinv".
  iFrame.
  auto.
Qed.

Global Instance is_inode_crash l addr σ :
  IntoCrash (inode_linv l addr σ) (λ _, ∃ addrs, is_inode_durable addr σ addrs)%I.
Proof.
  hnf; iIntros "Hinv".
  iNamed "Hinv".
  iExists addrs.
  iFrame.
  auto.
Qed.

Theorem inode_linv_to_cinv l addr σ :
  inode_linv l addr σ -∗ inode_cinv addr σ.
Proof.
  iNamed 1.
  iExists _; iFrame.
Qed.

Theorem pre_inode_to_cinv l addr σ :
  pre_inode l addr σ -∗ inode_cinv addr σ.
Proof.
  iNamed 1.
  iApply inode_linv_to_cinv; iFrame.
Qed.

Global Instance is_inode_Persistent l P Pcrash addr :
  Persistent (is_inode l P Pcrash addr).
Proof. apply _. Qed.

(* to initialize the system, we use this theorem to turn a zero block into a
valid post-crash inode state, which we can then recover with the usual [Open]
recovery procedure. *)
Theorem init_inode addr :
  int.Z addr d↦[∅] block0 -∗ inode_cinv addr (inode.mk ∅ []).
Proof.
  iIntros "Hhdr".
  iExists [], block0.
  cbv [inode.blocks big_sepL2].
  iFrame "Hhdr".
  iPureIntro.
  split_and!.
  - rewrite /inode.wf /=.
    cbv; congruence.
  - reflexivity.
  - reflexivity.
Qed.

Theorem is_inode_alloc l P Pcrash (HPcrash: ∀ σ, IntoCrash (P σ) (λ H, Pcrash H σ))  addr σ :
  P σ -∗
  pre_inode l addr σ ==∗
  init_cancel (is_inode l P Pcrash addr)
             (post_crash (λ H, ∃ σ', inode_cinv addr σ' ∗ Pcrash H σ')).
Proof.
  iIntros "HP Hinode"; iNamed "Hinode".
  iDestruct (alloc_crash_lock_init_cancel inodeN _
                           (∃ σ, "Hlockinv" ∷ inode_linv l addr σ ∗ "HP" ∷ P σ ∗
                                 "Hcrash" ∷ (∀ σ, P σ -∗ post_crash (λ H, Pcrash H σ)))%I
                           (post_crash (λ hGS, ∃ σ, "Hlockcinv" ∷ inode_cinv addr σ ∗ "HP" ∷ Pcrash hGS σ))%I
            with "[$Hfree_lock Hlockinv HP]") as "H".
  { iSplitL "".
    * iModIntro. iIntros "H". iNamed "H".
      iCrash.
      iExists _; iFrame.
    * iExists _. iFrame. iIntros (?) "HP". iCrash. eauto.
  }
  iApply (init_cancel_wand with "H [Hro_state]").
  { iIntros "H". iExists _, _; iFrame. }
  { eauto with iFrame. }
Qed.

Theorem wpc_Open {d} {addr σ} :
  {{{ inode_cinv addr σ }}}
    async_mem_alloc_inode.Open (disk_val d) #addr @ ⊤
  {{{ l, RET #l; pre_inode l addr σ }}}
  {{{ inode_cinv addr σ }}}.
Proof.
  iIntros (Φ Φc) "Hinode HΦ"; iNamed "Hinode".
  iAssert (□ (int.Z addr d↦[∅] hdr ∗
              ([∗ list] a;b ∈ addrs;σ.(inode.blocks), int.Z a d↦[∅] b) -∗
              inode_cinv addr σ))%I as "#Hinode".
  { eauto 10 with iFrame. }
  iDestruct (big_sepL2_length with "Hdata") as %Hblocklen.
  rewrite /Open.
  wpc_pures.
  { iLeft in "HΦ". iApply "HΦ". iApply ("Hinode" with "[$]"). }
  iCache with "HΦ Hhdr Hdata".
  { crash_case. iApply ("Hinode" with "[$]"). }
  wpc_pures.
  wpc_apply (wpc_Read with "Hhdr").
  iSplit; [ | iNext ].
  { iLeft in "HΦ". iIntros "Hhdr". iApply "HΦ". iApply ("Hinode" with "[$]"). }
  iIntros (s) "(Hhdr&Hs)".
  wpc_frame.
  wp_pures.
  iDestruct (slice.is_slice_to_small with "Hs") as "Hs".
  wp_apply (wp_new_dec with "Hs"); first eauto.
  iIntros (dec) "Hdec".
  wp_apply (wp_Dec__GetInt with "Hdec"); iIntros "Hdec".
  wp_pures.
  wp_apply (wp_Dec__GetInts _ _ _ addrs [] with "[Hdec]").
  { rewrite Hblocklen. word. }
  { rewrite app_nil_r; iFrame. }
  iIntros (addr_s) "[_ Haddrs]".
  wp_pures.
  rewrite -wp_fupd.
  wp_apply wp_new_free_crash_lock.
  iIntros (lref) "Hlock".
  wp_apply wp_allocStruct; auto.
  iIntros (l) "inode".
  iDestruct (struct_fields_split with "inode") as "(d&m&addr&addrs&_)".
  iMod (readonly_alloc_1 with "d") as "#d".
  iMod (readonly_alloc_1 with "m") as "#m".
  iMod (readonly_alloc_1 with "addr") as "#addr".
  iModIntro.
  iNamed 1.
  iApply "HΦ".
  iExists _, _; iFrame.
  iSplitR.
  { iFrame "#". }
  iExists _, _; iFrame "% ∗".
  iExists _; iFrame "% ∗".
Qed.

Theorem is_inode_durable_addrs addr σ addrs :
  is_inode_durable addr σ addrs -∗
  ⌜list_to_set addrs = σ.(inode.addrs)⌝.
Proof.
  iNamed 1.
  iFrame "%".
Qed.

Theorem is_inode_durable_size addr σ addrs :
  is_inode_durable addr σ addrs -∗ ⌜length addrs = length σ.(inode.blocks)⌝.
Proof.
  iNamed 1.
  iDestruct (big_sepL2_length with "Hdata") as "$".
Qed.

Definition used_blocks_pre l σ addrs: iProp Σ :=
  ∃ addr_s,
    "%Haddr_set" ∷ ⌜list_to_set addrs = σ.(inode.addrs)⌝ ∗
    "addrs" ∷ l ↦[Inode :: "addrs"] (slice_val addr_s) ∗
    "Haddrs" ∷ is_slice addr_s uint64T 1 addrs.

(* this lets the caller frame out the durable state for the crash invariant and
the memory state for UsedBlocks *)
Theorem pre_inode_read_addrs l addr σ :
  pre_inode l addr σ -∗
  ∃ addrs, used_blocks_pre l σ addrs ∗
           is_inode_durable addr σ addrs ∗
           (used_blocks_pre l σ addrs -∗
            is_inode_durable addr σ addrs -∗
            pre_inode l addr σ).
Proof.
  iNamed 1.
  iNamed "Hlockinv".
  iDestruct (is_inode_durable_addrs with "Hdurable") as "%Haddr_set".
  iExists addrs.
  iSplitL "addrs Haddrs".
  { iExists _; iFrame "% ∗". }
  iFrame.
  iNamed 1.
  iIntros "Hdurable".
  iExists _, _; iFrame.
  iExists _, _; iFrame "∗ %".
Qed.

Theorem wp_Inode__UsedBlocks {l σ addrs} :
  {{{ used_blocks_pre l σ addrs }}}
    Inode__UsedBlocks #l
  {{{ (s:Slice.t), RET (slice_val s);
      is_slice s uint64T 1 addrs ∗
      ⌜list_to_set addrs = σ.(inode.addrs)⌝ ∗
      (is_slice s uint64T 1 addrs -∗ used_blocks_pre l σ addrs) }}}.
Proof.
  iIntros (Φ) "Hinode HΦ"; iNamed "Hinode".
  wp_call.
  wp_loadField.
  iApply "HΦ".
  iFrame "∗ %".
  iIntros "Haddrs".
  iExists _; iFrame.
Qed.

Theorem wpc_Inode__UsedBlocks {l σ addr} :
  {{{ pre_inode l addr σ  }}}
    Inode__UsedBlocks #l @ ⊤
  {{{ (s:Slice.t) (addrs: list u64), RET (slice_val s);
      is_slice s uint64T 1 addrs ∗
      ⌜list_to_set addrs = σ.(inode.addrs)⌝ ∗
      (is_slice s uint64T 1 addrs -∗ pre_inode l addr σ) ∧ inode_cinv addr σ }}}
  {{{ inode_cinv addr σ }}}.
Proof.
  iIntros (Φ Φc) "Hinode HΦ"; iNamed "Hinode".
  (* TODO: wpc_call is broken here (maybe because the only redex is an App) *)
  rewrite /Inode__UsedBlocks.
  wpc_pures.
  { iLeft in "HΦ". iApply "HΦ". iApply inode_linv_to_cinv; eauto. }
  iNamed "Hlockinv".
  wpc_frame "HΦ Hdurable".
  { crash_case. eauto with iFrame. }
  wp_loadField.
  iNamed 1.
  iApply "HΦ".
  iFrame "Haddrs".
  iDestruct (is_inode_durable_addrs with "Hdurable") as "%Haddr_set".
  iSplitR; first auto.
  iSplit.
  - iIntros "Haddrs".
    iExists _, _; iFrame.
    iExists _, _; iFrame "∗ %".
  - iExists _; eauto.
Qed.

Ltac crash_lock_open H :=
  lazymatch goal with
  | [ |- envs_entails _ (wpc _ _ _ _ _) ] =>
    match iTypeOf H with
    | Some (_, crash_locked _ _ _ _) =>
      iApply (use_crash_locked with H);
      [ try eauto
      | iSplit; [ try iFromCache | ]
      ]
    | Some (_, _) => fail 1 "crash_lock_open:" H "is not a crash_locked fact"
    | None => fail 1 "crash_lock_open:" H "not found"
    end
  | _ => fail 1 "crash_lock_open: not a wpc"
  end.

Theorem wpc_Inode__Read {l P Pcrash addr} {off: u64} :
  ⊢ {{{ "Hinode" ∷ is_inode l P Pcrash addr }}}
    <<{ ∀∀ σ mb, ⌜mb = σ.(inode.blocks) !! int.nat off⌝ ∗ P σ }>>
      Inode__Read #l #off @ ∅
    <<{ P σ }>>
    {{{ s, RET (slice_val s); match mb with Some b => is_block s 1 b | None => ⌜s = Slice.nil⌝ end }}}
    {{{ True }}}.
Proof.
  iIntros (Φ Φc) "!# Hpre Hfupd"; iNamed "Hpre".
  iNamed "Hinode". iNamed "Hro_state".
  wpc_call; [done..|].
  iCache with "Hfupd"; first by crash_case.
  wpc_pures.
  wpc_bind_seq.
  wpc_frame.
  wp_loadField.
  wp_apply (crash_lock.acquire_spec with "Hlock"); first by set_solver.
  iIntros "His_locked".
  iNamed 1.
  wpc_pures.
  wpc_bind_seq.
  crash_lock_open "His_locked".
  iIntros "H". iNamed "H".

  iEval (rewrite ->(left_id True bi_wand)%I) in "Hfupd".
  iCache with "Hfupd Hlockinv HP HPcrash".
  { iLeft in "Hfupd". iFrame. iDestruct ("HPcrash" with "HP") as "HP".
    iCrash. iExists _. iFrame. }
  wpc_call.
  wpc_bind (_ ≥ _)%E.
  iNamed "Hlockinv".
  iCache with "Hfupd HP Hdurable HPcrash".
  { iLeft in "Hfupd". iFrame. iDestruct ("HPcrash" with "HP") as "HP".
    iCrash. iExists _. iFrame. iExists _. iFrame. }
  iDestruct (is_inode_durable_size with "Hdurable") as %Hlen1.
  wpc_frame.
  wp_loadField.
  iDestruct (is_slice_sz with "Haddrs") as %Hlen2.
  autorewrite with len in Hlen2.
  wp_apply wp_slice_len.
  wp_pures. iModIntro.
  iNamed 1.
  wpc_if_destruct.
  - iApply ncfupd_wpc.
    iSplit.
    { iLeft in "Hfupd". iFrame. iModIntro.
      iDestruct ("HPcrash" with "HP") as "HP". iCrash.
      eauto 12 with iFrame. }
    iRight in "Hfupd".

    rewrite difference_empty_L.
    iMod ("Hfupd" $! σ None with "[$HP]") as "[HP HQ]".
    { iPureIntro.
      rewrite lookup_ge_None_2 //.
      lia. }
    iModIntro.
    iEval (rewrite ->(left_id True bi_wand)%I) in "HQ".
    wpc_pures.
    { iLeft in "HQ". iFrame.
      iDestruct ("HPcrash" with "HP") as "HP". iCrash.
      eauto 12 with iFrame. }
    iModIntro.
    iSplitR "HP HPcrash addrs Haddrs Hdurable"; last first.
    { eauto 10 with iFrame. }
    iIntros "His_locked".
    iSplit; first by iLeft in "HQ". (* TODO(Ralf): can we avoid this double-proof? *)
    iCache with "HQ"; first by iLeft in "HQ".
    wpc_pures.
    wpc_frame "HQ".
    wp_loadField.
    wp_apply (crash_lock.release_spec with "His_locked"); auto.
    wp_pures. iModIntro.
    iNamed 1.
    iRight in "HQ".
    change slice.nil with (slice_val Slice.nil).
    iApply "HQ"; by iFrame.
  - destruct (list_lookup_lt _ addrs (int.nat off)) as [addr' Hlookup].
    { word. }
    iDestruct (is_slice_split with "Haddrs") as "[Haddrs_small Haddrs]".
    wpc_pures.
    wpc_frame_seq.
    wp_loadField.
    wp_apply (wp_SliceGet _ _ _ _ _ addrs with "[$Haddrs_small //]").
    iIntros "Haddrs_small"; iNamed 1.
    wpc_pures.
    iApply ncfupd_wpc.
    iSplit.
    { iLeft in "Hfupd". iFrame. iModIntro.
      iDestruct ("HPcrash" with "HP") as "HP". iCrash.
      eauto 12 with iFrame. }
    iDestruct (is_inode_durable_read with "Hdurable") as "H"; iNamed "H".
    iDestruct (big_sepL2_lookup_1_some with "Hdata") as "%Hblock_lookup"; eauto.
    destruct Hblock_lookup as [b0 Hlookup2].
    iDestruct (is_slice_split with "[$Haddrs_small $Haddrs]") as "Haddrs".
    iDestruct (big_sepL2_lookup_acc with "Hdata") as "[Hb Hdata]"; eauto.
    iRight in "Hfupd".
    rewrite difference_empty_L.
    iMod ("Hfupd" $! σ with "[$HP]") as "[HP HQ]".
    { iPureIntro; eauto. }
    iEval (rewrite ->(left_id True bi_wand)%I) in "HQ".
    iApply wpc_fupd. iModIntro.
    wpc_apply (wpc_Read with "Hb").
    iSplit.
    { iLeft in "HQ". iIntros "Hda".
      iSpecialize ("Hdata" with "Hda").
      iSpecialize ("Hdurable" with "Hhdr Hdata").
      iDestruct ("HPcrash" with "HP") as "HP". iFrame. iCrash.
      eauto 10 with iFrame. }
    iIntros "!>" (s) "[Hda Hb]".
    iSpecialize ("Hdata" with "Hda").
    iSpecialize ("Hdurable" with "Hhdr Hdata").
    iSplitR "Hdurable addrs Haddrs HP HPcrash"; last first.
    { eauto 10 with iFrame. }
    iModIntro.
    iIntros "His_locked".
    iSplit; first by iLeft in "HQ". (* TODO(Ralf): can we avoid this double-proof? *)
    iCache with "HQ"; first by iLeft in "HQ".
    wpc_frame.
    wp_loadField.
    wp_apply (crash_lock.release_spec with "His_locked"); auto.
    wp_pures. iModIntro.
    iNamed 1.
    iApply "HQ".
    iFrame.
    rewrite Hlookup2.
    iDestruct (slice.is_slice_to_small with "Hb") as "Hb".
    by iFrame.
Qed.

Theorem wpc_Inode__Read_triple {l P Pcrash addr} {off: u64} Q :
  {{{ "Hinode" ∷ is_inode l P Pcrash addr ∗
      "Hfupd" ∷ (∀ σ σ' mb,
        ⌜σ' = σ ∧ mb = σ.(inode.blocks) !! int.nat off⌝ ∗
        P σ ={⊤}=∗ P σ' ∗ Q mb)
  }}}
    Inode__Read #l #off @ ⊤
  {{{ s mb, RET slice_val s;
      (match mb with
       | Some b => is_block s 1 b
       | None => ⌜s = Slice.nil⌝
       end) ∗ Q mb }}}
  {{{ True }}}.
Proof.
  iIntros (Φ Φc) "Hpre HΦ"; iNamed "Hpre".
  iApply (wpc_step_strong_mono _ _ _ _ _
         (λ v, (∃ s mb, ⌜ v = slice_val s ⌝ ∗
                match mb with
                | Some b => is_block s 1 b
                | None => ⌜s = Slice.nil⌝
                end ∗ Q mb))%I _ True with "[-HΦ] [HΦ]"); auto.
  2: { iSplit.
       * iNext. iIntros (?) "H". iDestruct "H" as (??) "(%&?)". subst.
         iModIntro. iRight in "HΦ". by iApply "HΦ".
       * iLeft in "HΦ". iIntros. iModIntro. by iApply "HΦ". }
  iApply (wpc_Inode__Read with "Hinode").
  iSplit; first done.
  rewrite difference_empty_L.
  iNext. iIntros (σ mb) "[%Hσ HP]". iMod ("Hfupd" with "[$HP //]") as "[HP HQ]".
  iModIntro.  iFrame "HP". iSplit.
  { eauto. }
  iIntros (s) "Hblock". iExists _, _; iSplit; first done. iFrame; iApply "Hblock".
Qed.

Theorem wpc_Inode__Size {l P Pcrash addr}:
  ⊢ {{{ "Hinode" ∷ is_inode l P Pcrash addr }}}
    <<{ ∀∀ σ (sz: u64), ⌜int.nat sz = inode.size σ⌝ ∗ P σ }>>
      Inode__Size #l @ ∅
    <<{ P σ }>>
    {{{ RET #sz; True }}}
    {{{ True }}}.
Proof.
  iIntros (Φ Φc) "!# Hpre Hfupd"; iNamed "Hpre".
  iNamed "Hinode". iNamed "Hro_state".
  iEval (rewrite ->(left_id True bi_wand)%I) in "Hfupd".
  rewrite /Inode__Size.
  wpc_pures; first by iLeft in "Hfupd".
  iCache with "Hfupd"; first by iLeft in "Hfupd".
  wpc_frame_seq.
  wp_loadField.
  wp_apply (crash_lock.acquire_spec with "Hlock"); auto.
  iIntros "His_locked".
  iNamed 1.
  wpc_pures.
  wpc_bind_seq.
  crash_lock_open "His_locked".
  iDestruct 1 as (σ) "(Hlockinv&HP)".
  iNamed "HP".
  iApply ncfupd_wpc.
  iSplit.
  { iLeft in "Hfupd". iModIntro. iFrame.
    iDestruct ("HPcrash" with "HP") as "HP". iCrash.
    eauto 12 with iFrame. }
  iEval (rewrite /named) in "HP".
  iNamed "Hlockinv".
  iNamed "Hlockinv".
  iDestruct (is_slice_sz with "Haddrs") as %Haddrs_sz.
  iDestruct (is_inode_durable_size with "Hdurable") as %Hblocks_length.

  iRight in "Hfupd".
  rewrite difference_empty_L.
  iMod ("Hfupd" $! σ addr_s.(Slice.sz) with "[$HP]") as "[HP HQ]".
  { iPureIntro.
    rewrite /inode.size.
    autorewrite with len in Haddrs_sz.
    rewrite -Haddrs_sz //. }

  iModIntro.
  iEval (rewrite ->!(left_id True bi_wand)%I) in "HQ".
  iCache with "HQ Hdurable HP HPcrash".
  { iLeft in "HQ". iFrame.
    iDestruct ("HPcrash" with "HP") as "HP". iCrash.
    eauto 12 with iFrame. }
  iApply wpc_fupd.
  wpc_frame.
  wp_loadField.
  wp_apply wp_slice_len.
  iNamed 1.
  iSplitR "HP HPcrash addrs Haddrs Hdurable"; last first.
  { eauto 10 with iFrame.  }
  iIntros "!> His_locked".
  iSplit; first by iLeft in "HQ".
  iCache with "HQ"; first by iLeft in "HQ".
  wpc_pures.
  wpc_frame.
  wp_loadField.
  wp_apply (crash_lock.release_spec with "His_locked"); auto.
  wp_pures.
  iModIntro. iNamed 1.
  iRight in "HQ". by iApply "HQ".
Qed.

Theorem wpc_Inode__Size_triple {l P Pcrash addr} (Q: u64 -> iProp Σ) (Qc: iProp Σ) :
  {{{ "Hinode" ∷ is_inode l P Pcrash addr ∗
      "HQc" ∷ (∀ a, Q a -∗ Qc) ∗
      "Hfupd" ∷ (Qc ∧ (∀ σ σ' sz,
          ⌜σ' = σ ∧ int.nat sz = inode.size σ⌝ ∗
          P σ ={⊤}=∗ P σ' ∗ Q sz))
  }}}
    Inode__Size #l @ ⊤
  {{{ sz, RET #sz; Q sz }}}
  {{{ Qc }}}.
Proof.
  iIntros (Φ Φc) "Hpre HΦ"; iNamed "Hpre".
  iApply (wpc_step_strong_mono _ _ _ _ _
         (λ v, ∃ (sz : u64), ⌜ v = #sz ⌝ ∗ Q sz)%I _ Qc with "[-HΦ] [HΦ]"); auto.
  2: { iSplit.
       * iNext. iIntros (?) "H". iDestruct "H" as (?) "(%&?)". subst.
         iModIntro. iRight in "HΦ". by iApply "HΦ".
       * iLeft in "HΦ". iIntros. iModIntro. by iApply "HΦ". }
  iApply (wpc_Inode__Size with "Hinode").
  iSplit.
  { iLeft in "Hfupd". iIntros "_". eauto. }
  rewrite difference_empty_L.
  iNext. iIntros (σ mb) "[%Hσ HP]". iMod ("Hfupd" with "[$HP //]") as "[HP HQ]".
  iModIntro. iFrame "HP". iSplit.
  { iSpecialize ("HQc" with "[$]"). iIntros "_". eauto. }
  iIntros "_". eauto.
Qed.

Theorem wp_Inode__mkHdr {stk} l addr_s addrs :
  length addrs ≤ InodeMaxBlocks ->
  {{{ "addrs" ∷ l ↦[Inode :: "addrs"] (slice_val addr_s) ∗
      "Haddrs" ∷ is_slice addr_s uint64T 1 addrs
  }}}
    Inode__mkHdr #l @ stk
  {{{ s b, RET (slice_val s);
      is_block s 1 b ∗
      ⌜block_encodes b ([EncUInt64 (U64 $ length addrs)] ++ (EncUInt64 <$> addrs))⌝ ∗
      "addrs" ∷ l ↦[Inode :: "addrs"] (slice_val addr_s) ∗
      "Haddrs" ∷ is_slice addr_s uint64T 1 addrs
  }}}.
Proof.
  iIntros (Hbound Φ) "Hpre HΦ"; iNamed "Hpre".
  wp_call.
  wp_apply wp_new_enc; iIntros (enc) "Henc".
  wp_pures.
  wp_loadField.
  iDestruct (is_slice_sz with "Haddrs") as %Hlen.
  wp_apply wp_slice_len.
  wp_apply (wp_Enc__PutInt with "Henc").
  { word. }
  iIntros "Henc".
  wp_loadField.
  iDestruct (is_slice_split with "Haddrs") as "[Haddrs Hcap]".
  wp_apply (wp_Enc__PutInts with "[$Henc $Haddrs]").
  { word. }
  iIntros "[Henc Haddrs]".
  iDestruct (is_slice_split with "[$Haddrs $Hcap]") as "Haddrs".
  wp_apply (wp_Enc__Finish with "Henc").
  iIntros (??) "(%Henc&Hs)".
  wp_pures.
  iApply "HΦ".
  iFrame.
  iPureIntro.
  eapply block_encodes_eq; eauto.
  rewrite app_nil_l.
  repeat (f_equal; try word).
Qed.

Theorem wlog_assume_l {PROP:bi} (φ: Prop) (P: PROP) :
  φ →
  (⌜φ⌝ -∗ P) -∗
  ⌜φ⌝ ∗ P.
Proof.
  iIntros (H) "Himpl".
  iSplitR; auto.
  iApply ("Himpl" with "[//]").
Qed.

Lemma is_inode_durable_wf addr σ addrs :
  is_inode_durable addr σ addrs -∗
  ⌜inode.wf σ⌝.
Proof.
  iNamed 1.
  iFrame "%".
Qed.

Definition reserve_fupd E (Palloc: alloc.t → iProp Σ) : iProp Σ :=
  ∀ (σ σ': alloc.t) ma,
    ⌜match ma with
     | Some a => a ∈ alloc.free σ ∧ σ' = <[a:=block_reserved]> σ
     | None => σ' = σ ∧ alloc.free σ = ∅
     end⌝ -∗
  ▷ Palloc σ ={E}=∗ ▷ Palloc σ'.

(* free really means unreserve (we don't have a way to unallocate something
marked used) *)
Definition free_fupd E (Palloc: alloc.t → iProp Σ) (a:u64) : iProp Σ :=
  ∀ (σ: alloc.t),
    ⌜σ !! a = Some block_reserved⌝ -∗
  ▷ Palloc σ ={E}=∗ ▷ Palloc (<[a:=block_free]> σ).

(* This is useless because you need to do this together with some other action. *)
Definition use_fupd E (Palloc: alloc.t → iProp Σ) (a: u64): iProp Σ :=
  (∀ σ : alloc.t,
      ⌜σ !! a = Some block_reserved⌝ -∗
      ▷ Palloc σ ={E}=∗ ▷ Palloc (<[a:=block_used]> σ)).

Let Ψ (a: u64) := (∃ aset b, int.Z a d↦[aset] b)%I.

Opaque crash_borrow.

(* This does not fit the "atomic triple" pattern because of the possibility to
return [#false] without actually performing the commit.
It should be possible to phrase it as a "commit that does not change
anything", but that still requires atomic triples with an ∃∃ quantifier
in the atomic postcondition. *)
Theorem wpc_Inode__Append
        {l P Pcrash addr}
        (* allocator stuff *)
        {Palloc γalloc domain}
        (alloc_ref: loc) q (b_s: Slice.t) (b0: Block) :
  inodeN ## allocN →
  ∀ Φ Φc,
      "Hinode" ∷ is_inode l P Pcrash addr ∗
      "Hbdata" ∷ is_block b_s q b0 ∗
      "#Halloc" ∷ is_allocator Palloc Ψ allocN alloc_ref domain γalloc ∗
      "#Halloc_fupd" ∷ □ reserve_fupd (⊤ ∖ ↑allocN) Palloc ∗
      "#Hfree_fupd" ∷ □ (∀ a, free_fupd (⊤ ∖ ↑allocN) Palloc a) ∗
      (* TODO: Hfupd needs to capture the following alternatives:
         (1) Crash before write to header
         (2) Crash after write to header but before barrier
         (3) No crash/crash after barrier to header

         The key subtlety is that 3 is a definite linearization point for the
         operation, but a crash in case 2 is a possible linearization point
         based on whether the header block actually made it to disk or not.
         Thus we have to potentially execute the fupd *under* the post_crash
         modality

      *)
      "Hfupd" ∷ (Φc ∧ ▷ (Φ #false ∧ ∀ σ σ' addr',
        ⌜σ' = set inode.blocks (λ bs, bs ++ [b0])
                              (set inode.addrs ({[addr']} ∪.) σ)⌝ -∗
        ⌜inode.wf σ⌝ -∗
        ∀ s,
        ⌜s !! addr' = Some block_reserved⌝ -∗
         P σ ∗ ▷ Palloc s -∗ |={⊤ ∖ ↑allocN}=>
         P σ' ∗ ▷ Palloc (<[addr' := block_used]> s) ∗ (Φc ∧ Φ #true))) -∗
    WPC Inode__Append #l (slice_val b_s) #alloc_ref @ ⊤ {{ Φ }} {{ Φc }}.
Proof.
  iIntros (? Φ Φc) "Hpre"; iNamed "Hpre".
  iNamed "Hinode". iNamed "Hro_state".
  wpc_call.
  iCache with "Hfupd"; first by crash_case.
  wpc_pures.
  wpc_frame_seq.
  wp_apply (wp_Reserve _ _ _ (λ ma, emp)%I with "[$Halloc]"); auto.
  { (* Reserve fupd *)
    iIntros (σ σ' ma Htrans) "HP".
    iMod ("Halloc_fupd" with "[] HP"); eauto. }
  iIntros (a ok) "Hblock".
  iNamed 1.
  wpc_pures.
  wpc_if_destruct.
  - wpc_pures.
    iRight in "Hfupd".
    by iLeft in "Hfupd".
  - iDestruct "Hblock" as "[_ Hb]".
    wpc_pures.
    wpc_bind_seq.
    iApply (prepare_reserved_block_reuse with "Hb"); auto.
    iSplit; first by iFromCache.
    iIntros "Hb Hreserved".
    iDeexHyp "Hb".
    iAssert (□ ∀ aset0 b0, int.Z a d↦[aset0] b0 ∗
                      (Φc) -∗
                      (Φc ∗ block_cinv Ψ γalloc a))%I as "#Hbc".
    { iIntros "!>" (aset' b') "(Hb & Hfupd)".
      iSplitL "Hfupd"; first done.
      iApply block_cinv_free_pred.
      iExists _, _; iFrame. }

    iCache with "Hfupd Hb".
    {  iLeft in "Hfupd". iDestruct ("Hbc" with "[$]") as "($&$)". }
    wpc_apply (wpc_Write' with "[$Hb $Hbdata]").
    iSplit.
    { iLeft in "Hfupd". iIntros "[Hb|Hb]".
      - iDestruct ("Hbc" with "[$]") as "($&$)".
      - iDestruct ("Hbc" with "[$]") as "($&$)".
    }
    iIntros "!> [Hda _]".
    iFrame "Hreserved".
    iSplitR "Hda"; last first.
    { instantiate (1:=λ _, (∃ aset', int.Z a d↦[aset'] b0)%I); simpl.
      iSplitL.
      { iExists _. iExact "Hda". }
      iModIntro.
      iIntros "Hda". iDestruct "Hda" as (?) "Hda".
      iApply block_cinv_free_pred. iExists _, _; iFrame. }

    iIntros "Hreserved".
    iSplit; first iFromCache.
    wpc_pures.
    wpc_bind_seq.
    iApply (prepare_reserved_block_reuse with "Hreserved"); auto.
    iSplit.
    { iLeft in "Hfupd". eauto. }
    iIntros "Hb Hreserved".
    iDeexHyp "Hb".
    wpc_apply (wpc_Barrier1 with "[$Hb]").
    iSplit.
    { iLeft in "Hfupd". iIntros "[Hb|Hb]".
      - iDestruct ("Hbc" with "[$]") as "($&$)".
      - iDestruct ("Hbc" with "[$]") as "($&$)".
    }
    iIntros "!> Hda".
    iFrame "Hreserved".
    iSplitR "Hda"; last first.
    { instantiate (1:=λ _, (int.Z a d↦[∅] b0)%I); simpl.
      iSplitL.
      { iExact "Hda". }
      iModIntro.
      iIntros "Hda".
      iApply block_cinv_free_pred. iExists _, _; iFrame. }

    iIntros "Hreserved".
    iSplit; first iFromCache.

    wpc_pures.
    wpc_frame_seq.
    wp_loadField.
    wp_apply (crash_lock.acquire_spec with "Hlock"); auto.
    iIntros "His_locked". iNamed 1.
    wpc_pures.
    wpc_bind_seq.
    crash_lock_open "His_locked".
    iDestruct 1 as (σ) "(Hlockinv&HP)".
    iApply wpc_fupd.
    iNamed "HP".
    do 2 iNamed "Hlockinv".
    iCache with "Hfupd HP HPcrash Hdurable".
    { iLeft in "Hfupd". iFrame.
      iDestruct ("HPcrash" with "HP") as "HP".
      iCrash. iExists _. iFrame; eauto. }
    iDestruct (is_slice_sz with "Haddrs") as %Hlen1.
    autorewrite with len in Hlen1.
    iDestruct (is_inode_durable_size with "Hdurable") as %Hlen2.
    wpc_call.
    wpc_bind (slice.len _ ≥ _)%E.
    wpc_frame.
    wp_loadField.
    wp_apply wp_slice_len; wp_pures.
    iModIntro. iNamed 1.
    wpc_if_destruct.
    + wpc_pures.
      iSplitR "HP HPcrash Hdurable addrs Haddrs"; last first.
      { iExists _; iFrame.
        do 1 iModIntro.
        iFrame. iExists _, _; iFrame "∗ %". }
      iModIntro.
      iIntros "His_locked".
      iSplit; first iFromCache.
      wpc_pures.
      wpc_frame_seq.
      wp_loadField.
      wp_apply (crash_lock.release_spec with "His_locked"); auto.
      iNamed 1.
      wpc_pures.
      wpc_frame_seq.
      wp_apply (wp_Free _ _ _ emp with "[$Halloc Hreserved]").
      { auto. }
      { iSplitL "Hreserved".
        { iApply (reserved_block_weaken with "[] [] Hreserved").
          { rewrite /Ψ. eauto. }
          { rewrite /Ψ/block_cinv. eauto. }
        }
        iIntros (σ' Hreserved) "HP".
        iMod ("Hfree_fupd" with "[//] HP") as "$".
        auto. }
      iIntros "_".
      wp_pures.
      iNamed 1.
      wpc_pures.
      iRight in "Hfupd".
      by iLeft in "Hfupd".
    + wpc_pures.
      wpc_frame_seq.
      wp_loadField.
      wp_apply (wp_SliceAppend (V:=u64) with "[$Haddrs]").
      iIntros (addr_s') "Haddrs".
      Transparent slice.T.
      wp_storeField.
      Opaque slice.T.
      iNamed 1.
      wpc_pures.
      wpc_frame_seq.
      wp_apply (wp_Inode__mkHdr with "[$addrs $Haddrs]").
      { autorewrite with len; simpl.
        word. }
      iIntros (s b') "(Hb&%Hencoded'&?&?)"; iNamed.
      iNamed 1.
      wpc_pures.
      wpc_loadField.

      iApply (prepare_reserved_block with "Hreserved"); auto; try lia.
      iSplit; first iFromCache.
      iIntros "Hda Hreserved".
      wpc_bind (Write _ _).
      (* hide this horrible postcondition for now *)
      match goal with
      | |- envs_entails _ (wpc _ _ _ ?Φ0 _) => set (Φ':=Φ0)
      end.
      iNamed "Hdurable".
      wpc_apply (wpc_Write with "[$Hb Hhdr]").
      { iExists _, _. iFrame. }
      iSplit.
      { iIntros "H".
        iNamed 1.
 iNamed 1. iNext. iIntros "H". iNamed 1.
      iIntros.



      wpc_apply (wpc_Write_ncfupd with "[$Hb]").
      iSplit.
      { iLeft in "Hfupd". iSplitR "Hda".
        * iFrame. iExists _; iFrame. iExists _; iFrame.
        * iApply block_cinv_free_pred. iExists _, _; iFrame. }
      iNamed "Hdurable".
      iRight in "Hfupd".
      set (σ':=set inode.blocks (λ bs : list Block, bs ++ [b0])
                   (set inode.addrs (union {[a]}) σ)).
      iRight in "Hfupd".
      iSpecialize ("Hfupd" $! σ σ' a with "[% //] [% //]").

      iMod (mark_used _ _ _ _ _ (P σ' ∗ (Φc ∧ Φ #true))%I with "Hreserved [HP Hfupd]") as "Hget_used".
      { solve_ndisj. }
      { clear.
        iIntros (s Hreserved) "HPalloc".
        iMod ("Hfupd" with "[% //] [$HP $HPalloc]") as "(HP&HPalloc&HQ)".
        iFrame. eauto. }

      iModIntro.
      iExists _, _; iFrame.
      iNext.
      iIntros "Hhdr".
      iMod "Hget_used" as "[ (HP&HQ) Hused]".
      (*
      iAssert (is_inode_durable addr
                 (set inode.blocks (λ bs : list Block, bs ++ [b0])
                      (set inode.addrs (union {[a]}) σ))
                 (addrs ++ [a]))
              with "[Hhdr Hdata Hda]" as "Hdurable".
      { iExists _; iFrame "∗ %".
        iSplitR.
        { iPureIntro.
          rewrite /inode.wf /=.
          autorewrite with len; simpl.
          word. }
        iSplitR.
        { iPureIntro.
          simpl.
          rewrite list_to_set_app_L.
          simpl.
          set_solver. }
        simpl; auto. }
      iDestruct (is_inode_durable_wf with "Hdurable") as %Hwf'.
       *)
      iCache (Φc)%I with "HQ".
      { by iLeft in "HQ". }
      iModIntro.
      match goal with
      | |- envs_entails _ ((?P ∗ _) ∧ _) =>
        iCache (P)%I with "HQ HP Hhdr Hdata Hda"
      end.
      { iLeft in "HQ". iFrame. iExists _; iFrame.
        iExists _; iFrame. }
      iCache (block_cinv Ψ γalloc a) with "Hused".
      { iApply block_cinv_from_used; iFrame. }
      iSplit.
      { iLeft in "HQ". iFrame. iExists _. iFrame. iExists _; iFrame. }
      iIntros "Hb".
      subst Φ'; cbv beta.
      (* done applying wpc_Write_fupd *)

      wpc_pures.
      { iLeft in "HQ". iFrame. iExists _. iFrame. iExists _; iFrame. }
      iModIntro. iSplitR "Hused"; last (iFromCache).
      iSplit.
      { iLeft in "HQ". iFrame. iExists _. iFrame. iExists _; iFrame. }
      iSplitR "HP Haddrs addrs Hdurable"; last first.
      { iExists _; iFrame. iModIntro.
        iExists _, _; iFrame "∗ %". }
      iModIntro.
      iIntros "His_locked".
      iSplit; first iFromCache.
      wpc_pures.
      wpc_frame_seq.
      wp_loadField.
      wp_apply (crash_lock.release_spec with "His_locked"); auto.
      iNamed 1.
      wpc_pures.
      (* RALF: we are throwing away an [is_block] here. *)
      by iRight in "HQ".
Qed.

(* Note that this spec is a lot weaker than the one above because in case of
failure, the resources put into "Hfupd" are lost! *)
Theorem wpc_Inode__Append_triple
        {l P addr}
        (* allocator stuff *)
        {Palloc γalloc domain}
        (Q: iProp Σ) (Qc: iProp Σ)
        (alloc_ref: loc) q (b_s: Slice.t) (b0: Block) :
  inodeN ## allocN →
  {{{ "Hinode" ∷ is_inode l P addr ∗
      "Hbdata" ∷ is_block b_s q b0 ∗
      "HQc" ∷ (Q -∗ Qc) ∗
      "#Halloc" ∷ is_allocator Palloc Ψ allocN alloc_ref domain γalloc ∗
      "#Halloc_fupd" ∷ □ reserve_fupd (⊤ ∖ ↑allocN) Palloc ∗
      "#Hfree_fupd" ∷ □ (∀ a, free_fupd (⊤ ∖ ↑allocN) Palloc a) ∗
      "Hfupd" ∷ (Qc ∧ (∀ σ σ' addr',
        ⌜σ' = set inode.blocks (λ bs, bs ++ [b0])
                              (set inode.addrs ({[addr']} ∪.) σ)⌝ -∗
        ⌜inode.wf σ⌝ -∗
        ∀ s,
        ⌜s !! addr' = Some block_reserved⌝ -∗
         P σ ∗ ▷ Palloc s ={⊤ ∖ ↑allocN}=∗
         P σ' ∗ ▷ Palloc (<[addr' := block_used]> s) ∗ Q))
  }}}
    Inode__Append #l (slice_val b_s) #alloc_ref @ ⊤
  {{{ (ok: bool), RET #ok; if ok then Q else emp }}}
  {{{ Qc }}}.
Proof.
  iIntros (? Φ Φc) "Hpre HΦ"; iNamed "Hpre".
  iApply (wpc_step_strong_mono _ _ _ _ _
         (λ v, ∃ (ok: bool), ⌜ v = #ok ⌝ ∗ if ok then Q else emp)%I _ Qc with "[-HΦ] [HΦ]"); auto.
  2: { iSplit.
       * iNext. iIntros (?) "H". iDestruct "H" as (?) "(%&?)". subst.
         iModIntro. iRight in "HΦ". by iApply "HΦ".
       * iLeft in "HΦ".  iIntros. iModIntro. by iApply "HΦ". }
  iApply (wpc_Inode__Append); try assumption.
  iFrame "Hinode Hbdata Halloc_fupd Hfree_fupd Halloc".
  iSplit.
  { by iLeft in "Hfupd".  }
  iSplit.
  { iClear "Hfupd". (* This is where resources are lost. *)
    iNext. iExists _; iSplit; first eauto. done. }
  iIntros "!>" (σ σ' addr' Hσ' Hσ s Hs) "HPs".
  iRight in "Hfupd".
  iMod ("Hfupd" $! _ _ _ Hσ' Hσ _ Hs with "HPs") as "($ & $ & HQ)".
  iIntros "!>". iSplit.
  { iDestruct ("HQc" with "[$]") as "$". }
  iExists _; iSplit; first auto. iFrame.
Qed.
End goose.

Section goose.
Context `{!heapGS Σ}.
Context `{!allocG Σ}.

Context (P: inode.t → iProp Σ).

Instance inode_cinv_stable addr σ :
  IntoCrash (inode_cinv addr σ) (λ _, inode_cinv addr σ).
Proof.
  intros.
  hnf; iNamed 1.
  rewrite ?big_sepL2_alt.
  iDestruct "Hdata" as "(%Heq&Hl)".
  iCrash.
  iExists _, _. iFrame.
  rewrite ?big_sepL2_alt.
  iFrame. eauto.
Qed.

End goose.
