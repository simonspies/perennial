Require Import Tactical.Propositional.
Require Import Helpers.RelationAlgebra.

Import RelationNotations.

(* attempt to make rewriting across monad associativity a bit easier; instead
     of massaging the goal to have [r1] appear, instead generalize the
     hypothesis to apply to apply to [forall rx, r1; rx] *)
Lemma rimpl_rx A B T (r1 r2: relation A B T) :
  r1 ---> r2 ->
  (forall C T2 (rx: T -> relation B C T2),
      and_then r1 rx ---> and_then r2 rx).
Proof.
  intros.
  rel_congruence; auto.
Qed.

Tactic Notation "pose" "unfolded" constr(pf) tactic(t) :=
  let H := fresh in
  pose proof pf as H; t H; destruct_ands.

Create HintDb relation_rewriting.

Ltac with_hyp H tac :=
  let H' := fresh "Htmp" in
  pose proof H as H';
  tac H';
  clear H'.

Tactic Notation "with" "hyp" constr(H) tactic(t) := with_hyp H t.

Tactic Notation "rew" constr(pf) :=
  with hyp pf
       (fun H => autounfold with relation_rewriting in H;
              setoid_rewrite -> H;
              norm_goal).
Tactic Notation "rew<-" constr(pf) :=
  with hyp pf
       (fun H => autounfold with relation_rewriting in H;
              setoid_rewrite <- H;
              norm_goal).
Tactic Notation "rew" "->" uconstr(pf) "in" ident(H) :=
  with hyp pf
       (fun H' => autounfold with relation_rewriting in H';
               setoid_rewrite -> H' in H at 1;
               norm_hyp H).
Tactic Notation "rew" "<-" uconstr(pf) "in" ident(H) :=
  with hyp pf
       (fun H' => autounfold with relation_rewriting in H';
               setoid_rewrite <- H' in H at 1;
               norm_hyp H).

Ltac Split := match goal with
              | |- (_ + _ ---> _) =>
                apply rel_or_elim; norm
              | |- ?g ---> _ =>
                match g with
                | context[_ + _] =>
                  repeat (setoid_rewrite bind_dist_l ||
                          setoid_rewrite bind_dist_r);
                  apply rel_or_elim; norm
                end
              end.

Ltac Left := match goal with
             | |- _ ---> ?g =>
               match g with
               | context[_ + _] =>
                 rewrite <- rel_or_introl; norm
               end
             end.

Ltac Right := match goal with
              | |- _ ---> ?g =>
                match g with
                | context[_ + _] =>
                  rewrite <- rel_or_intror; norm
                end
              end.

Ltac left_associate H :=
  try rewrite <- ?bind_assoc in H;
  rewrite <- ?bind_assoc;
  repeat setoid_rewrite <- bind_assoc;
  try repeat setoid_rewrite <- bind_assoc in H.

Tactic Notation "left" "assoc" "rew" constr(H) :=
  with hyp H
       (fun H => autounfold with relation_rewriting in H;
             left_associate H;
             setoid_rewrite H;
             norm_goal).

Tactic Notation "left" "assoc" "rew" "<-" constr(H) :=
  with hyp H
       (fun H => autounfold with relation_rewriting in H;
             left_associate H;
             setoid_rewrite <- H;
             norm_goal).
