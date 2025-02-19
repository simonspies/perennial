From iris.algebra Require Import dfrac_agree mono_list.
From Perennial.program_proof Require Import grove_prelude.

(*
  "Gauge-invariant" part of the proof
 *)
Local Definition configR := gmapR u64 (dfrac_agreeR (leibnizO (list u64))).
Local Definition logR := mono_listR (leibnizO u8).
Local Definition cn_logR := gmapR u64 logR.
Local Definition cn_rep_logR := gmapR (u64*u64) logR.
Class pb_ghostG Σ :=
  { pb_ghost_configG :> inG Σ configR;
    pb_ghost_logG :> inG Σ logR;
    pb_ghost_cn_logG :> inG Σ cn_logR;
    pb_ghost_cn_rep_logG :> inG Σ cn_rep_logR }.

Definition pb_ghostΣ := #[GFunctor configR; GFunctor logR; GFunctor cn_logR; GFunctor cn_rep_logR].

Global Instance subG_pb_ghostG {Σ} :
  subG pb_ghostΣ Σ → pb_ghostG Σ.
Proof. solve_inG. Qed.

Record pb_names :=
  {
  pb_config_gn : gname;
  pb_proposal_gn : gname;
  pb_accepted_gn : gname;
  pb_commit_gn : gname;
  }.

Definition Log := list u8.

Definition log_po (lhs rhs:Log) : Prop :=
  prefix lhs rhs.

Notation "lhs ⪯ rhs" := (log_po lhs rhs)
(at level 20, format "lhs ⪯ rhs") : stdpp_scope.

Section definitions.

Context `{!gooseGlobalGS Σ, !pb_ghostG Σ}.

Implicit Type γ : pb_names.

Definition config_ptsto γ (cn:u64) (conf:list u64): iProp Σ :=
  own γ.(pb_config_gn) {[cn := to_dfrac_agree DfracDiscarded (conf : (leibnizO _))]} ∗
  ⌜length conf > 0⌝.
Definition config_unset γ (cn:u64) : iProp Σ :=
  own γ.(pb_config_gn) {[cn := to_dfrac_agree (DfracOwn 1) ([] : (leibnizO _))]}.

Definition proposal_ptsto γ (cn:u64) (l:Log): iProp Σ :=
  own γ.(pb_proposal_gn) {[cn := ●ML (l : list (leibnizO u8))]}.
Definition proposal_ptsto_ro γ (cn:u64) (l:Log): iProp Σ :=
  own γ.(pb_proposal_gn) {[cn := ●ML□ (l : list (leibnizO u8))]}.
Definition proposal_lb γ (cn:u64) (l:Log): iProp Σ :=
  own γ.(pb_proposal_gn) {[cn := ◯ML (l : list (leibnizO u8))]}.

Definition accepted_ptsto γ (cn:u64) (r:u64) (l:Log): iProp Σ :=
  own γ.(pb_accepted_gn) {[(cn,r) := ●ML (l : list (leibnizO u8))]}.
Definition accepted_ptsto_ro γ (cn:u64) (r:u64) (l:Log): iProp Σ :=
  own γ.(pb_accepted_gn) {[(cn,r) := ●ML□ (l : list (leibnizO u8))]}.
Definition accepted_lb γ (cn:u64) (r:u64) (l:Log): iProp Σ :=
  own γ.(pb_accepted_gn) {[(cn,r) := ◯ML (l : list (leibnizO u8))]}.

Definition commit_ptsto γ (l:Log): iProp Σ :=
  own γ.(pb_commit_gn) (●ML (l : list (leibnizO u8))).
Definition commit_lb γ (l:Log): iProp Σ :=
  own γ.(pb_commit_gn) (◯ML (l : list (leibnizO u8))).

Global Instance config_ptsto_pers γ cn conf :
  Persistent (config_ptsto γ cn conf).
Proof. apply _. Qed.

Global Instance proposal_lb_pers γ cn l :
  Persistent (proposal_lb γ cn l).
Proof. apply _. Qed.

Global Instance accepted_lb_pers γ cn r l :
  Persistent (accepted_lb γ cn r l).
Proof. apply _. Qed.

Global Instance committed_lb_pers γ l :
  Persistent (commit_lb γ l).
Proof. apply _. Qed.

Definition accepted_by γ cn l : iProp Σ := (* persistent *)
  ∃ conf, config_ptsto γ cn conf ∗
      ∀ (r:u64), ⌜r ∈ conf⌝ → accepted_lb γ cn r l.

Definition oldConfMax γ (cn:u64) log : iProp Σ := (* persistent *)
  □(∀ cn_old log_old ,
   ⌜int.Z cn_old < int.Z cn⌝ →
   accepted_by γ cn_old log_old → ⌜log_old ⪯ log⌝).

Definition commit_lb_by γ (cn:u64) l : iProp Σ := (* persistent *)
  commit_lb γ l ∗ (∃ cn_old, ⌜int.Z cn_old <= int.Z cn⌝ ∗ accepted_by γ cn_old l).

(* Want better name *)
Definition proposal_ptsto_fancy γ cn log : iProp Σ :=
  proposal_ptsto γ cn log ∗
  oldConfMax γ cn log.

Definition proposal_lb_fancy γ cn log : iProp Σ := (* persistent *)
  proposal_lb γ cn log ∗
  oldConfMax γ cn log.

(* System-wide invariant for primary/backup replication with many replicas with
   configuration changes *)
Definition pb_invariant γ : iProp Σ :=
  ∃ cn_committed l_committed,
  "Hcommit" ∷ commit_ptsto γ l_committed ∗
  "Haccepted" ∷ accepted_by γ cn_committed l_committed ∗ oldConfMax γ cn_committed l_committed
.

Definition pbN := nroot .@ "pb_inv".

Definition pb_inv γ : iProp Σ :=
  inv pbN (pb_invariant γ).

Lemma config_ptsto_agree γ cn conf conf' :
  config_ptsto γ cn conf -∗ config_ptsto γ cn conf' -∗ ⌜conf = conf'⌝.
Proof.
  iIntros "[Hconf _] [Hconf' _]".
  iDestruct (own_valid_2 with "Hconf Hconf'") as %Hval. iPureIntro. revert Hval.
  rewrite singleton_op singleton_valid dfrac_agree_op_valid_L.
  naive_solver.
Qed.

Lemma config_ptsto_nonempty γ cn conf :
  config_ptsto γ cn conf -∗ ⌜∃ r, r ∈ conf⌝.
Proof.
  iIntros "[_ %Hconf]". iPureIntro.
  destruct conf as [|r rs]; first done.
  exists r. constructor.
Qed.

Lemma config_ptsto_set γ cn conf :
  length conf > 0 →
  config_unset γ cn ==∗ config_ptsto γ cn conf.
Proof.
  iIntros (?) "Hconf".
  iMod (own_update with "Hconf") as "$"; last done.
  apply singleton_update. apply cmra_update_exclusive.
  done.
Qed.

Lemma accepted_update {γ cn r l} l' :
  (l ⪯ l') → accepted_ptsto γ cn r l ==∗ accepted_ptsto γ cn r l'.
Proof.
  iIntros (Hll'). iApply own_update.
  apply singleton_update, mono_list_update.
  done.
Qed.

Lemma accepted_witness γ cn r l :
  accepted_ptsto γ cn r l -∗ accepted_lb γ cn r l.
Proof.
  iApply own_mono.
  apply singleton_mono, mono_list_included.
Qed.

Lemma accepted_lb_monotonic γ cn r l l':
  l ⪯ l' → accepted_lb γ cn r l' -∗ accepted_lb γ cn r l.
Proof.
  iIntros (Hll'). iApply own_mono.
  apply singleton_mono, mono_list_lb_mono.
  done.
Qed.

Lemma accepted_lb_le γ cn r l l' :
  accepted_ptsto γ cn r l' -∗ accepted_lb γ cn r l -∗ ⌜l ⪯ l'⌝.
Proof.
  iIntros "Hl Hl'".
  iDestruct (own_valid_2 with "Hl Hl'") as %Hval.
  iPureIntro. revert Hval.
  rewrite singleton_op singleton_valid.
  rewrite mono_list_both_valid_L.
  done.
Qed.

Lemma accepted_lb_comparable γ cn r l l' :
  accepted_lb γ cn r l -∗ accepted_lb γ cn r l' -∗ ⌜l ⪯ l' ∨  l' ⪯ l⌝.
Proof.
  iIntros "Hl Hl'".
  iDestruct (own_valid_2 with "Hl Hl'") as %Hval.
  iPureIntro. revert Hval.
  rewrite singleton_op singleton_valid => /mono_list_lb_op_valid_L.
  done.
Qed.

Lemma proposal_lb_monotonic γ cn l l' :
  l ⪯ l' →
  proposal_lb γ cn l' -∗ proposal_lb γ cn l.
Proof.
  intros Hle.
  iApply own_mono.
  apply singleton_mono. apply mono_list_lb_mono.
  done.
Qed.

Lemma oldConfMax_monotonic γ cn l l' :
  (l ⪯ l') → oldConfMax γ cn l -∗ oldConfMax γ cn l'.
Proof.
  iIntros (Hll') "#Hocm".
  iIntros "!# %cn_old %log_old % Hacc".
  iAssert (⌜log_old⪯l⌝)%I as %?.
  2:{ iPureIntro. by etrans. }
  iApply "Hocm"; done.
Qed.

Lemma proposal_lb_le γ cn l l' :
  proposal_ptsto γ cn l' -∗ proposal_lb γ cn l -∗ ⌜l ⪯ l'⌝.
Proof.
  iIntros "Hl Hl'".
  iDestruct (own_valid_2 with "Hl Hl'") as %Hval.
  iPureIntro. revert Hval.
  rewrite singleton_op singleton_valid mono_list_both_valid_L.
  done.
Qed.

Lemma proposal_lb_comparable γ cn l l' :
  proposal_lb γ cn l -∗ proposal_lb γ cn l' -∗ ⌜l ⪯ l' ∨  l' ⪯ l⌝.
Proof.
  iIntros "Hl Hl'".
  iDestruct (own_valid_2 with "Hl Hl'") as %Hval.
  iPureIntro. revert Hval.
  rewrite singleton_op singleton_valid => /mono_list_lb_op_valid_L.
  done.
Qed.

Lemma commit_update {γ l} l' :
  (l ⪯ l') → commit_ptsto γ l ==∗ commit_ptsto γ l'.
Proof.
  iIntros (Hll'). iApply own_update.
  apply mono_list_update.
  done.
Qed.

Lemma commit_witness γ l :
  commit_ptsto γ l -∗ commit_lb γ l.
Proof.
  iApply own_mono.
  apply mono_list_included.
Qed.

Lemma commit_lb_monotonic γ l l':
  l ⪯ l' → commit_lb γ l' -∗ commit_lb γ l.
Proof.
  iIntros (Hll'). iApply own_mono.
  apply mono_list_lb_mono.
  done.
Qed.

Lemma proposal_lb_fancy_comparable γ cn l l' :
  proposal_lb_fancy γ cn l -∗ proposal_lb_fancy γ cn l' -∗ ⌜l ⪯ l' ∨  l' ⪯ l⌝.
Proof.
  iIntros "[Hl _] [Hl' _]". iApply (proposal_lb_comparable with "Hl Hl'").
Qed.

Lemma accepted_by_monotonic γ cn l l' :
  (l ⪯ l') → accepted_by γ cn l' -∗ accepted_by γ cn l.
Proof.
  iIntros (Hll') "[%conf [Hconf Hacc]]".
  iExists conf. iFrame "Hconf".
  iIntros (r Hr). iApply accepted_lb_monotonic; first done.
  by iApply "Hacc".
Qed.

(* commit_lb_by is covariant in cn, contravariant in l *)
Lemma commit_lb_by_monotonic γ cn cn' l l' :
  int.Z cn' <= int.Z cn → (l ⪯ l') → commit_lb_by γ cn' l' -∗ commit_lb_by γ cn l.
Proof.
  iIntros (Hcn Hl) "[Hcomm [%cn_old [%Hcn_old Hacc]]]".
  iSplitL "Hcomm".
  { by iApply commit_lb_monotonic. }
  iExists cn_old. iSplit.
  - iPureIntro. lia.
  - by iApply accepted_by_monotonic.
Qed.

Lemma oldConfMax_commit_lb_by γ cn l cn_old l_old :
  int.Z cn_old < int.Z cn → proposal_lb_fancy γ cn l -∗ commit_lb_by γ cn_old l_old -∗ ⌜l_old ⪯ l⌝.
Proof.
  iIntros (?) "#Hφ [_ #Hcommit]".
  iDestruct "Hφ" as "[_ Hφ]".
  iDestruct "Hcommit" as (? ?) "Haccepted_by".
  iApply ("Hφ" $! cn_old0).
  { iPureIntro. word. }
  iFrame "#".
Qed.

Lemma do_commit γ cn l :
  pb_inv γ -∗
  proposal_lb_fancy γ cn l -∗
  accepted_by γ cn l
  ={⊤}=∗
  commit_lb_by γ cn l.
Proof.
  iIntros "#Hinv #Hprop #Hacc".
  iInv "Hinv" as ">Hpb" "HpbClose".
  iDestruct "Hpb" as "[%cn_comitted [%l_committed (Hcomm & #Hcomm_acc & #Holdconf)]]".
  rewrite /named.
  destruct (Z_dec (int.Z cn) (int.Z cn_comitted)) as [[Hcn|Hcn]|Hcn].
  - (* [cn] is older than [cn_comitted]. *)
    iDestruct ("Holdconf" with "[//] Hacc") as %Hlog.
    iDestruct (commit_witness with "Hcomm") as "#Hwit".
    iMod ("HpbClose" with "[Hcomm]") as "_".
    { iExists _, _. by eauto with iFrame. }
    iDestruct (commit_lb_monotonic with "Hwit") as "$".
    { done. }
    iExists _. iFrame "Hacc". done.
  - (* [cn] is greater than [cn_committed]. *)
    iClear "Holdconf". (* the one from the invariant, now useless *)
    iDestruct "Hprop" as "[Hprop #Holdconf]".
    iDestruct ("Holdconf" with "[] Hcomm_acc") as %Hlog.
    { iPureIntro. lia. }
    iMod (commit_update l with "Hcomm") as "Hcomm"; first done.
    iDestruct (commit_witness with "Hcomm") as "#Hwit".
    iMod ("HpbClose" with "[Hcomm]") as "_".
    {
      iExists _, _. iFrame "Hcomm". iSplitR.
      * iApply accepted_by_monotonic; done.
      * done.
    }
    iSplitR; first done.
    iExists _. iFrame "Hacc". done.
  - (* [cn] is equal to [cn_committed]. *)
    assert (cn = cn_comitted) by word. subst cn. clear Hcn.
    iPoseProof "Hacc" as (conf) "[#Hconf Hacc_lb]".
    iPoseProof "Hcomm_acc" as (comm_conf) "[#Hcomm_conf Hcomm_acc_lb]".
    iDestruct (config_ptsto_agree with "Hconf Hcomm_conf") as %<-.
    iClear "Hcomm_conf".
    iDestruct (config_ptsto_nonempty with "Hconf") as %[r Hr].
    iSpecialize ("Hacc_lb" with "[//]").
    iSpecialize ("Hcomm_acc_lb" with "[//]").
    iDestruct (accepted_lb_comparable with "Hacc_lb Hcomm_acc_lb") as "[%Hl|%Hl]".
    + (* [l] is already committed. *)
      iDestruct (commit_witness with "Hcomm") as "#Hwit".
      iMod ("HpbClose" with "[Hcomm]") as "_".
      { iExists _, _. by eauto with iFrame. }
      iSplitR; first by iApply commit_lb_monotonic.
      iExists _. iFrame "Hacc". done.
    + (* we can commit [l] now. *)
      iMod (commit_update l with "Hcomm") as "Hcomm"; first done.
      iDestruct (commit_witness with "Hcomm") as "#Hwit".
      iMod ("HpbClose" with "[Hcomm]") as "_".
      {
        iExists _, _. iFrame "Hcomm". iSplitR.
        -- iApply accepted_by_monotonic; done.
        -- iApply oldConfMax_monotonic; done.
      }
      iSplitR; first done.
      iExists _. iFrame "Hacc". done.
Qed.

End definitions.

Typeclasses Opaque config_ptsto config_unset proposal_ptsto proposal_ptsto_ro proposal_lb accepted_ptsto accepted_ptsto_ro accepted_lb commit_ptsto commit_lb.
