(** VOF CBOR Encoding

    Strict subset of the RFC 8949 CBOR specification necessary for VOF
    serialization. Features include:

    - Deterministic map ordering
    - Integers encoded in their smallest lossless form
    - Float encoded in the smallest lossless form (64, 32, 16 bits)
    - Optional magic tag prefix

    For convenience with non-VOF readers, Boolean values and maps are stored as
    such even if it is not strictly necessary. *)

(** [decode ?pos ?len s] decodes a VOF raw value from the CBOR-encoded string
    [s]. *)
val decode : ?pos:int -> ?len:int -> string -> (Vof.t * int) option

(** [encode_buf ctx ?magic ?buf v] encodes a VOF value [v] with context [ctx]
    into a CBOR string, with optional magic tag prefix if [magic] is true. If
    [buf] is provided, it is appended to, otherwise a new buffer is created. *)
val encode_buf :
  Vof.Context.t -> ?magic:bool -> ?buf:Buffer.t -> Vof.t -> Buffer.t

(** [encode_str ctx ?magic v] encodes a VOF value [v] with context [ctx] into a
    CBOR string, with optional magic tag prefix if [magic] is true. *)
val encode_str : Vof.Context.t -> ?magic:bool -> Vof.t -> string
