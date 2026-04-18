(** 16-bit floating point *)

type t = int

val float_of_bits : t -> float
val bits_of_float : float -> t
val bits_of_float_opt : float -> t option
