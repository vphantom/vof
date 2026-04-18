type t = int

let float_of_bits bits =
  let sign = (bits lsr 15) land 1 in
  let exp = (bits lsr 10) land 0x1F in
  let mant = bits land 0x3FF in
  let v =
    if exp = 0
    then if mant = 0 then 0.0 else ldexp (float_of_int mant) (-24)
    else if exp = 31
    then if mant = 0 then infinity else nan
    else ldexp (float_of_int (mant lor 0x400)) (exp - 25)
  in
  if sign = 1 then -.v else v
;;

let bits_of_float_opt f =
  let bits = Int64.bits_of_float f in
  let sign = Int64.to_int (Int64.shift_right_logical bits 63) in
  let exp64 = Int64.to_int (Int64.shift_right_logical bits 52) land 0x7FF in
  let mant64 = Int64.logand bits 0xF_FFFF_FFFF_FFFFL in
  if exp64 = 0x7FF
  then
    if mant64 = 0L
    then Some ((sign lsl 15) lor 0x7C00)
    else Some ((sign lsl 15) lor 0x7E00)
  else if exp64 = 0
  then if mant64 = 0L then Some (sign lsl 15) else None
  else (
    let unbiased = exp64 - 1023 in
    if unbiased > 15 || unbiased < -24
    then None
    else if unbiased >= -14
    then
      if Int64.logand mant64 0x3FF_FFFF_FFFFL <> 0L
      then None
      else (
        let e = unbiased + 15 in
        let m = Int64.to_int (Int64.shift_right_logical mant64 42) in
        Some ((sign lsl 15) lor (e lsl 10) lor m)
      )
    else (
      let shift = 1051 - exp64 in
      let full = Int64.logor mant64 0x10_0000_0000_0000L in
      let mask = Int64.sub (Int64.shift_left 1L shift) 1L in
      if Int64.logand full mask <> 0L
      then None
      else (
        let m = Int64.to_int (Int64.shift_right full shift) in
        if m < 1 || m > 0x3FF then None else Some ((sign lsl 15) lor m)
      )
    )
  )
;;

let bits_of_float f = bits_of_float_opt f |> Option.get
