(* autogenerated from github.com/mit-pdos/perennial-examples/inode *)
From Perennial.goose_lang Require Import prelude.
From Goose Require github_com.mit_pdos.perennial_examples.alloc.
From Goose Require github_com.tchajed.marshal.

From Perennial.goose_lang Require Import ffi.disk_prelude.

Definition MaxBlocks : expr := #511.

Definition Inode := struct.decl [
  "d" :: disk.Disk;
  "m" :: ptrT;
  "addr" :: uint64T;
  "addrs" :: slice.T uint64T
].

Definition Open: val :=
  rec: "Open" "d" "addr" :=
    let: "b" := disk.Read "addr" in
    let: "dec" := marshal.NewDec "b" in
    let: "numAddrs" := marshal.Dec__GetInt "dec" in
    let: "addrs" := marshal.Dec__GetInts "dec" "numAddrs" in
    struct.new Inode [
      "d" ::= "d";
      "m" ::= lock.new #();
      "addr" ::= "addr";
      "addrs" ::= "addrs"
    ].

(* UsedBlocks returns the addresses allocated to the inode for the purposes
   of recovery. Assumes full ownership of the inode, so does not lock,
   and expects the caller to need only temporary access to the returned slice. *)
Definition Inode__UsedBlocks: val :=
  rec: "Inode__UsedBlocks" "i" :=
    struct.loadF Inode "addrs" "i".

Definition Inode__read: val :=
  rec: "Inode__read" "i" "off" :=
    (if: "off" ≥ slice.len (struct.loadF Inode "addrs" "i")
    then slice.nil
    else
      let: "a" := SliceGet uint64T (struct.loadF Inode "addrs" "i") "off" in
      disk.Read "a").

Definition Inode__Read: val :=
  rec: "Inode__Read" "i" "off" :=
    lock.acquire (struct.loadF Inode "m" "i");;
    let: "b" := Inode__read "i" "off" in
    lock.release (struct.loadF Inode "m" "i");;
    "b".

Definition Inode__Size: val :=
  rec: "Inode__Size" "i" :=
    lock.acquire (struct.loadF Inode "m" "i");;
    let: "sz" := slice.len (struct.loadF Inode "addrs" "i") in
    lock.release (struct.loadF Inode "m" "i");;
    "sz".

Definition Inode__mkHdr: val :=
  rec: "Inode__mkHdr" "i" :=
    let: "enc" := marshal.NewEnc disk.BlockSize in
    marshal.Enc__PutInt "enc" (slice.len (struct.loadF Inode "addrs" "i"));;
    marshal.Enc__PutInts "enc" (struct.loadF Inode "addrs" "i");;
    let: "hdr" := marshal.Enc__Finish "enc" in
    "hdr".

(* append adds address a (and whatever data is stored there) to the inode

   Requires the lock to be held.

   In this simple design with only direct blocks, appending never requires
   internal allocation, so we don't take an allocator.

   This method can only fail due to running out of space in the inode. In this
   case, append returns ownership of the allocated block. *)
Definition Inode__append: val :=
  rec: "Inode__append" "i" "a" :=
    (if: slice.len (struct.loadF Inode "addrs" "i") ≥ MaxBlocks
    then #false
    else
      struct.storeF Inode "addrs" "i" (SliceAppend uint64T (struct.loadF Inode "addrs" "i") "a");;
      let: "hdr" := Inode__mkHdr "i" in
      disk.Write (struct.loadF Inode "addr" "i") "hdr";;
      #true).

(* Append adds a block to the inode.

   Returns false on failure (if the allocator or inode are out of space) *)
Definition Inode__Append: val :=
  rec: "Inode__Append" "i" "b" "allocator" :=
    let: ("a", "ok") := alloc.Allocator__Reserve "allocator" in
    (if: ~ "ok"
    then #false
    else
      disk.Write "a" "b";;
      lock.acquire (struct.loadF Inode "m" "i");;
      let: "ok2" := Inode__append "i" "a" in
      lock.release (struct.loadF Inode "m" "i");;
      (if: ~ "ok2"
      then alloc.Allocator__Free "allocator" "a"
      else #());;
      "ok2").
