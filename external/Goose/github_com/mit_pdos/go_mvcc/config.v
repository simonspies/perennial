(* autogenerated from github.com/mit-pdos/go-mvcc/config *)
From Perennial.goose_lang Require Import prelude.

Section code.
Context `{ext_ty: ext_types}.
Local Coercion Var' s: expr := Var s.

Definition N_TXN_SITES : expr := #64.

Definition N_IDX_BUCKET : expr := #2048.

Definition TID_SENTINEL : expr := #18446744073709551615.

End code.
