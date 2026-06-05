(** VOF JSON Encoding

    This module converts to/from [Yojson.Basic.t] compatible types without doing
    final string I/O. *)

type t = [
  `Null
  | `Bool of bool
  | `Int of int
  | `Float of float
  | `String of string
  | `Assoc of (string * t) list
  | `List of t list
] [@@ocamlformat "disable"]

(** [to_raw j] converts JSON [j] to VOF variant, ready to use with your [of_vof]
    functions.

    The returned value uses a small subset of the variant: [Null], [Bool],
    [Float], [Raw_tint], [Raw_tstr], [Raw_tlist]. *)
val to_raw : t -> Vof.t

(** [of_vof ctx v] converts VOF [v] to JSON with context [ctx]. *)
val of_vof : Vof.Context.t -> Vof.t -> t
