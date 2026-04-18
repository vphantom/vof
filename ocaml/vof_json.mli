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

(** [to_input j] converts JSON [j] to VOF input, ready to use with your [of_vof]
    functions. *)
val to_input : t -> Vof.input

(** [of_vof ctx v] converts VOF [v] to JSON with context [ctx]. *)
val of_vof : Vof.Context.t -> Vof.t -> t
