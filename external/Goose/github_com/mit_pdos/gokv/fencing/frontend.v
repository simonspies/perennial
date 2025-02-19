(* autogenerated from github.com/mit-pdos/gokv/fencing/frontend *)
From Perennial.goose_lang Require Import prelude.
From Goose Require github_com.goose_lang.std.
From Goose Require github_com.mit_pdos.gokv.fencing.config.
From Goose Require github_com.mit_pdos.gokv.fencing.ctr.
From Goose Require github_com.mit_pdos.gokv.urpc.
From Goose Require github_com.tchajed.marshal.

From Perennial.goose_lang Require Import ffi.grove_prelude.

(* client.go *)

Definition RPC_FAI : expr := #0.

Definition Clerk := struct.decl [
  "cl" :: ptrT
].

Definition Clerk__FetchAndIncrement: val :=
  rec: "Clerk__FetchAndIncrement" "ck" "key" "ret" :=
    let: "reply_ptr" := ref (zero_val (slice.T byteT)) in
    let: "enc" := marshal.NewEnc #8 in
    marshal.Enc__PutInt "enc" "key";;
    let: "err" := urpc.Client__Call (struct.loadF Clerk "cl" "ck") RPC_FAI (marshal.Enc__Finish "enc") "reply_ptr" #100 in
    (if: "err" ≠ #0
    then "err"
    else
      let: "dec" := marshal.NewDec (![slice.T byteT] "reply_ptr") in
      "ret" <-[uint64T] marshal.Dec__GetInt "dec";;
      #0).

Definition MakeClerk: val :=
  rec: "MakeClerk" "host" :=
    let: "ck" := struct.alloc Clerk (zero_val (struct.t Clerk)) in
    struct.storeF Clerk "cl" "ck" (urpc.MakeClient "host");;
    "ck".

(* server.go *)

Definition Server := struct.decl [
  "mu" :: ptrT;
  "epoch" :: uint64T;
  "ck1" :: ptrT;
  "ck2" :: ptrT
].

(* pre: key == 0 or key == 1 *)
Definition Server__FetchAndIncrement: val :=
  rec: "Server__FetchAndIncrement" "s" "key" :=
    lock.acquire (struct.loadF Server "mu" "s");;
    let: "ret" := ref (zero_val uint64T) in
    (if: ("key" = #0)
    then
      "ret" <-[uint64T] ctr.Clerk__Get (struct.loadF Server "ck1" "s") (struct.loadF Server "epoch" "s");;
      std.SumAssumeNoOverflow (![uint64T] "ret") #1;;
      ctr.Clerk__Put (struct.loadF Server "ck1" "s") (![uint64T] "ret" + #1) (struct.loadF Server "epoch" "s")
    else
      "ret" <-[uint64T] ctr.Clerk__Get (struct.loadF Server "ck2" "s") (struct.loadF Server "epoch" "s");;
      std.SumAssumeNoOverflow (![uint64T] "ret") #1;;
      ctr.Clerk__Put (struct.loadF Server "ck2" "s") (![uint64T] "ret" + #1) (struct.loadF Server "epoch" "s"));;
    lock.release (struct.loadF Server "mu" "s");;
    ![uint64T] "ret".

Definition StartServer: val :=
  rec: "StartServer" "me" "configHost" "host1" "host2" :=
    let: "s" := struct.alloc Server (zero_val (struct.t Server)) in
    let: "configCk" := config.MakeClerk "configHost" in
    struct.storeF Server "epoch" "s" (config.Clerk__AcquireEpoch "configCk" "me");;
    struct.storeF Server "mu" "s" (lock.new #());;
    struct.storeF Server "ck1" "s" (ctr.MakeClerk "host1");;
    struct.storeF Server "ck2" "s" (ctr.MakeClerk "host2");;
    let: "handlers" := NewMap ((slice.T byteT -> ptrT -> unitT)%ht) #() in
    MapInsert "handlers" RPC_FAI (λ: "args" "reply",
      let: "dec" := marshal.NewDec "args" in
      let: "enc" := marshal.NewEnc #8 in
      marshal.Enc__PutInt "enc" (Server__FetchAndIncrement "s" (marshal.Dec__GetInt "dec"));;
      "reply" <-[slice.T byteT] marshal.Enc__Finish "enc";;
      #()
      );;
    let: "r" := urpc.MakeServer "handlers" in
    urpc.Server__Serve "r" "me";;
    #().
