(** VOF Binary Encoding

    Implements the VOF Binary format described in BINARY.md, a compact binary
    serialization simpler than CBOR. All integers are unsigned on the wire with
    a PrefixVarint-like encoding, and signed types use ZigZag encoding.

    Little Endian byte order is used throughout. *)

(** [decode ?pos ?len s] decodes a VOF raw value from the binary-encoded string
    [s]. Returns the decoded input and the number of bytes consumed. *)
val decode : ?pos:int -> ?len:int -> string -> (Vof.t * int) option

(** [encode_buf ctx ?buf v] encodes a VOF value [v] with context [ctx] into a
    VOF Binary buffer. If [buf] is provided, it is appended to, otherwise a new
    buffer is created. *)
val encode_buf : Vof.Context.t -> ?buf:Buffer.t -> Vof.t -> Buffer.t

(** [encode_str ctx v] encodes a VOF value [v] with context [ctx] into a VOF
    Binary string. *)
val encode_str : Vof.Context.t -> Vof.t -> string
