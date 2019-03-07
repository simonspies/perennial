From iris.algebra Require Import auth gmap list.
Require Export CSL.Refinement.
From RecoveryRefinement.Examples.Logging Require Import LogAPI LogImpl.
From RecoveryRefinement.Examples Require Import ExMach.WeakestPre ExMach.RefinementAdequacy.
Require AtomicPair.Helpers.

Unset Implicit Arguments.

(* TODO: move this out *)
Existing Instance AtomicPair.Helpers.from_exist_left_sep.

Canonical Structure BufStateC := leibnizC BufState.

Set Default Proof Using "Type".
Section refinement_triples.
  Context `{!exmachG Σ, lockG Σ, !@cfgG (Log.Op) (Log.l) Σ,
            !inG Σ (authR (optionUR (exclR (prodC natC natC)))),
            !inG Σ (authR (optionUR (exclR (listC (prodC natC natC))))),
            !inG Σ (authR (optionUR (exclR (listC natC)))),
            !inG Σ (authR (optionUR (exclR natC))),
            !inG Σ (authR (optionUR (exclR BufStateC)))}.
  Import ExMach.

  (* Definition ptr_map (ptr_val : nat) (pcurr: nat * nat) (pother: nat * nat) :=
    (ptr_addr d↦ ptr_val ∗
     (read_addrs ptr_val).1 d↦ pcurr.1 ∗
     (read_addrs ptr_val).2 d↦ pcurr.2 ∗
     (write_addrs ptr_val).1 d↦ pother.1 ∗
     (write_addrs ptr_val).2 d↦ pother.2)%I. *)

  Definition txn_map start (txn: nat * nat) :=
    (start m↦ txn.1 ∗ (1+start) m↦ txn.2)%I.

  Definition buffer_map (s:BufState) (txns: list (nat*nat)) :=
    (state m↦ enc_state s ∗
           match s with
           | Empty => emp
           | Txn1 => (∃ txn, ⌜txns = [txn]⌝ ∗
                                         txn_map txn1_start txn)
           | Txn2 => (∃ txn, ⌜txns = [txn]⌝ ∗
                                         txn_map txn2_start txn)
           | Txn12 => (∃ txn1 txn2, ⌜txns = [txn1; txn2]⌝ ∗
                                                       txn_map txn1_start txn1 ∗
                                                       txn_map txn2_start txn2)
           | Txn21 => ∃ txn1 txn2, ⌜txns = [txn1; txn2]⌝ ∗
                                                      txn_map txn2_start txn1 ∗
                                                      txn_map txn1_start txn2
     end)%I.

  Definition txn_free start :=
    (∃ txn, txn_map start txn)%I.

  Definition free_buffer_map (s:BufState) :=
    (match s with
     | Empty => txn_free txn1_start ∗ txn_free txn2_start
     | Txn1 => txn_free txn2_start
     | Txn2 => txn_free txn1_start
     | Txn12 => emp
     | Txn21 => emp
     end)%I.

  Record ghost_names :=
    { γslock : gname;
      γstate : gname;
      γtxns : gname;
      γdlock : gname;
      γlog : gname; }.

  Fixpoint flatten_txns (txns: list (nat*nat)) : list nat :=
    match txns with
    | nil => nil
    | (v1, v2) :: txns' => v1 :: v2 :: flatten_txns txns'
    end.

  Definition ExecInner names :=
    (∃ (s:BufState) (txns: list (nat*nat)) (log: list nat),
        own (names.(γstate)) (● Excl' s) ∗
            own (names.(γtxns)) (● Excl' txns) ∗
            own (names.(γlog)) (● Excl' log) ∗
            buffer_map s txns ∗ free_buffer_map s ∗
            source_state {| Log.mem_buf := flatten_txns txns;
                            Log.disk_log := log; |}
    )%I.

  Definition StateLockInv names :=
    (∃ s txns,
        buffer_map s txns ∗ free_buffer_map s ∗
                   own (names.(γtxns)) (◯ Excl' txns))%I.

  Fixpoint log_map (i: nat) log :=
    (match log with
     | nil => emp
     | x::log' => log_idx i d↦ x ∗ log_map (1+i) log'
     end)%I.

  Instance log_map_timeless i log : Timeless (log_map i log).
  Proof.
    generalize dependent i.
    induction log; intros; simpl; apply _.
  Qed.

  Definition ExecDiskInv names :=
    (∃ (log: list nat),
        log_len d↦ length log ∗
                log_map 0 log ∗
                own (names.(γlog)) (● Excl' log))%I.

  Definition DiskLockInv names :=
    (∃ (log: list nat),
        own (names.(γlog)) (◯ Excl' log))%I.

  Definition CrashInner :=
    (∃ (log: list nat),
        source_state {| Log.mem_buf := nil;
                        Log.disk_log := log; |} ∗
                     free_buffer_map Empty ∗
                     state_lock m↦ 0)%I.

  Definition lN : namespace := nroot.@"lock".
  Definition ldN : namespace := nroot.@"dlock".
  Definition iN : namespace := nroot.@"inner".

  Definition ExecInv :=
    (source_ctx ∗ ∃ (names:ghost_names),
          is_lock lN (names.(γslock)) state_lock (StateLockInv names) ∗
                  is_lock ldN (names.(γdlock)) disk_lock (DiskLockInv names) ∗
                  inv iN (ExecInner names ∗ ExecDiskInv names))%I.

  Definition CrashInv :=
    (source_ctx ∗ inv iN CrashInner)%I.

  Lemma log_map_extract_general log : forall k i,
    i < length log ->
    log_map k log -∗
            (log_idx (k+i) d↦ (nth i log 0) ∗
                     (log_idx (k+i) d↦ (nth i log 0) -∗
                              log_map k log)).
  Proof.
    induction log; intros; simpl in *.
    - exfalso; inversion H1.
    - destruct i; simpl.
      replace (k + 0) with k by lia.
      iIntros "(Hlogk & Hlogrest)".
      iFrame; auto.

      iIntros "(Hlogk & Hlogrest)".
      iPoseProof (IHlog _ i with "Hlogrest") as "(IHlogidx & IHlogrest)".
      lia.
      replace (k + S i) with (S k + i) by lia.
      iFrame.
      iFrame.
  Qed.

  Lemma log_map_extract i : forall log,
      i < length log ->
      log_map 0 log -∗
            (log_idx i d↦ (nth i log 0) ∗
                     (log_idx i d↦ (nth i log 0) -∗
                              log_map 0 log)).
  Proof.
    intros.
    apply (log_map_extract_general log 0 i); auto.
  Qed.

  Lemma get_log_refinement j `{LanguageCtx Log.Op _ T Log.l K} i:
    {{{ j ⤇ K (Call (Log.GetLog i)) ∗ Registered ∗ ExecInv }}}
      get_log i
    {{{ v, RET v; j ⤇ K (Ret v) ∗ Registered }}}.
  Proof.
    iIntros (Φ) "(Hj&Href&#Hsource_inv&Hinv) HΦ".
    iDestruct "Hinv" as (γnames) "#(Hslock&Hdlock&Hinv)".
    wp_bind. iApply (wp_lock with "[$]").

    iIntros "!> (Hlocked&Hlinv)".
    iDestruct "Hlinv" as (log) "Hownlog".

    wp_bind.
    iInv "Hinv" as "(Hexec&Hdisk)".
    iDestruct "Hdisk" as (log') ">(Hlog_len&Hlog_data&Hownlog_auth)".
    AtomicPair.Helpers.unify_ghost.
    clear log'.

    wp_step.
    iFrame.
    unfold ExecDiskInv.
    iModIntro; iExists _; iFrame.

    destruct matches; wp_bind.
    wp_bind.
    iInv "Hinv" as "(Hexec&Hdisk)".
    iDestruct "Hdisk" as (log') ">(Hlog_len&Hlog_data&Hownlog_auth)".
    AtomicPair.Helpers.unify_ghost.
    clear log'.
    iPoseProof (log_map_extract i with "Hlog_data") as "(Hi&Hlog_rest)"; auto.

    wp_step.

    iFrame.
    iSpecialize ("Hlog_rest" with "Hi").
    iModIntro; iExists _; iFrame.
    wp_step.
    wp_bind.
    iApply (wp_unlock with "[Hownlog Hlocked]").
    iFrame "Hdlock Hlocked".
    iExists _; iFrame.
    iIntros "!> _".
    wp_step.
    iApply "HΦ".
    iFrame.
  Abort.

End refinement_triples.
