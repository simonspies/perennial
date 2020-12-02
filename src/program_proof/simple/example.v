From RecordUpdate Require Import RecordSet.
Import RecordSetNotations.

From Perennial.algebra Require Import deletable_heap liftable auth_map.
From Perennial.Helpers Require Import Transitions.
From Perennial.program_proof Require Import proof_prelude.

From Goose.github_com.mit_pdos.goose_nfsd Require Import simple.
From Perennial.program_proof Require Import txn.txn_proof marshal_proof addr_proof crash_lockmap_proof addr.addr_proof buf.buf_proof.
From Perennial.program_proof Require Import buftxn.sep_buftxn_proof.
From Perennial.program_proof Require Import proof_prelude.
From Perennial.program_proof Require Import disk_lib.
From Perennial.Helpers Require Import NamedProps Map List range_set.
From Perennial.algebra Require Import log_heap.
From Perennial.program_logic Require Import spec_assert.
From Perennial.goose_lang.lib Require Import slice.typed_slice into_val.
From Perennial.program_proof.simple Require Import spec proofs.

Section heap.
Context `{!buftxnG Σ}.
Context `{!ghost_varG Σ (gmap u64 (list u8))}.
Context `{!mapG Σ u64 (list u8)}.
Implicit Types (stk:stuckness) (E: coPset).

Variable P : SimpleNFS.State -> iProp Σ.
Context `{Ptimeless : !forall σ, Timeless (P σ)}.
Opaque slice_val.

Theorem wpc_RecoverExample γ (d : loc) dinit logm klevel :
  {{{
    recovery_proof.is_txn_durable γ dinit ∗ txn_resources γ logm
  }}}
    RecoverExample #d @ S klevel; ⊤
  {{{ RET #(); True }}}
  {{{ True }}}.
Proof using Ptimeless.
  iIntros (Φ Φc) "(Htxndurable & Htxnres) HΦ".
  rewrite /RecoverExample.
  wpc_pures.
  { iDestruct "HΦ" as "[HΦc _]". iModIntro. iApply "HΦc". done. }

  wpc_apply (wpc_MkTxn with "[$Htxndurable $Htxnres]").

  iSplit.
  { iDestruct "HΦ" as "[HΦc _]". iModIntro. iIntros "H".
    iDestruct "H" as (γ' logm') "(%Hkinds & Htxndurable & Htxnres)".
    iApply "HΦc". done. }

  iModIntro.
  iIntros (l) "(#Histxn & Hmapsto)".

  wpc_pures.
  { iDestruct "HΦ" as "[HΦc _]". iModIntro. iApply "HΦc". done. }

  wpc_apply wpc_MkLockMap.
  { (* where to get old predicates? probably [Hlmcrash] from below.. *) admit. }

  iSplit.
  { iDestruct "HΦ" as "[HΦc _]". iModIntro. iIntros "H".
    iApply "HΦc". done. }

  iModIntro.
  iIntros (lm ghs) "[#Hlm Hlmcrash]".

  wpc_pures.
  { iDestruct "HΦ" as "[HΦc _]". iModIntro. iApply "HΦc". done. }

  admit.
Admitted.

Print Assumptions wpc_RecoverExample.

End heap.
