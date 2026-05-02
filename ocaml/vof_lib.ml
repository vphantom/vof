let ( let| ) = Option.bind

module Decimal = struct
  let[@inline] optimize (value, dec) =
    let rec loop v d =
      if d > 0 && v mod 10 = 0 then loop (v / 10) (d - 1) else v, d
    in
    loop value dec
  ;;

  let pack (value, dec) =
    let value, dec = optimize (value, dec) in
    match dec with
    | 0 -> value lsl 2
    | 1 -> ((value * 10) lsl 2) lor 1
    | 2 -> (value lsl 2) lor 1
    | 3 -> ((value * 10) lsl 2) lor 2
    | 4 -> (value lsl 2) lor 2
    | 5 -> ((value * 10000) lsl 2) lor 3
    | 6 -> ((value * 1000) lsl 2) lor 3
    | 7 -> ((value * 100) lsl 2) lor 3
    | 8 -> ((value * 10) lsl 2) lor 3
    | 9 -> (value lsl 2) lor 3
    | _ -> invalid_arg "Vof.Decimal.pack: unsupported decimal places"
  ;;

  let unpack n =
    let value = n asr 2 in
    match n land 3 with
    | 0 -> value, 0
    | 1 -> optimize (value, 2)
    | 2 -> optimize (value, 4)
    | 3 -> optimize (value, 9)
    | _ -> failwith "Vof.Decimal.unpack: impossible"
  ;;

  let to_n (value, dec) =
    if dec < 0 || dec > 9
    then invalid_arg "Vof.Decimal.to_n: unsupported decimal places";
    let value, dec = optimize (value, dec) in
    if value < 0 then (value * 10) - dec else (value * 10) + dec
  ;;

  let of_n n =
    let sign = if n < 0 then -1 else 1 in
    match abs n with
    | 0 -> Some (0, 0)
    | a when a < 10 -> None
    | a -> Some (optimize (sign * (a / 10), a mod 10))
  ;;

  let of_string ?(shift = 0) s =
    let module B = Buffer in
    let buf = B.create (String.length s) in
    let int_chars = ref (-1) in
    let last_nonzero = ref 0 in
    let check_char c =
      match c with
      | '-' | '0' -> B.add_char buf c
      | '1' .. '9' ->
        B.add_char buf c;
        last_nonzero := B.length buf
      | '.' ->
        int_chars := B.length buf;
        last_nonzero := B.length buf
      | _ -> ()
    in
    String.iter check_char s;
    if !int_chars >= 0
    then B.truncate buf !last_nonzero
    else int_chars := B.length buf;
    let| i = int_of_string_opt (B.contents buf) in
    Some (optimize (i, B.length buf - !int_chars + shift))
  ;;

  let to_string (value, dec) =
    let build scale =
      let i = value / scale in
      let f = abs (value mod scale) in
      if f = 0
      then Int.to_string i
      else (
        let prefix = if value < 0 && i = 0 then "-0" else Int.to_string i in
        let s = Printf.sprintf "%s.%0*d" prefix dec f in
        let len = ref (String.length s) in
        while !len > 1 && s.[!len - 1] = '0' do
          decr len
        done;
        String.sub s 0 !len
      )
    in
    match dec with
    | 0 -> Int.to_string value
    | 1 -> build 10
    | 2 -> build 100
    | 3 -> build 1000
    | 4 -> build 10000
    | 5 -> build 100000
    | 6 -> build 1000000
    | 7 -> build 10000000
    | 8 -> build 100000000
    | 9 -> build 1000000000
    | _ -> invalid_arg "Decimal.to_string: unsupported decimal places"
  ;;
end

module Ratio = struct
  let of_string s =
    match String.split_on_char '/' s with
    | [ num; den ] -> (
      match int_of_string_opt num, int_of_string_opt den with
      | Some n, Some d when d > 0 -> Some (n, d)
      | Some _, Some _ -> None
      | _ -> None
    )
    | _ -> None
  ;;

  let to_string (n, d) = Printf.sprintf "%d/%d" n d
end

module Date = struct
  let pack (y, m, d) = ((y - 1900) lsl 9) lor (m lsl 5) lor d

  let unpack i =
    let y = (i lsr 9) + 1900
    and m = (i lsr 5) land 15
    and d = i land 31 in
    if m >= 1 && m <= 12 && d >= 1 && d <= 31 then Some (y, m, d) else None
  ;;

  let of_tm tm = Unix.(tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday)

  let to_tm (y, m, d) =
    Unix.
      {
        tm_year = y - 1900;
        tm_mon = m - 1;
        tm_mday = d;
        tm_hour = 0;
        tm_min = 0;
        tm_sec = 0;
        tm_wday = 0;
        tm_yday = 0;
        tm_isdst = false;
      }
  ;;

  let to_human (y, m, d) = (y * 10000) + (m * 100) + d

  let of_human n =
    let y = n / 10000
    and m = n mod 10000 / 100
    and d = n mod 100 in
    if y >= 1000 && y <= 9999 && m >= 1 && m <= 12 && d >= 1 && d <= 31
    then Some (y, m, d)
    else None
  ;;
end

module Datetime = struct
  let pack (y, m, d, hh, mm) =
    ((y - 1900) lsl 20) lor (m lsl 16) lor (d lsl 11) lor (hh lsl 6) lor mm
  ;;

  let unpack i =
    let y = (i lsr 20) + 1900
    and m = (i lsr 16) land 15
    and d = (i lsr 11) land 31
    and hh = (i lsr 6) land 63
    and mm = i land 63 in
    if m >= 1 && m <= 12 && d >= 1 && d <= 31 && hh <= 23 && mm <= 59
    then Some (y, m, d, hh, mm)
    else None
  ;;

  let of_tm tm =
    Unix.(tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday, tm.tm_hour, tm.tm_min)
  ;;

  let to_tm (y, m, d, hh, mm) =
    Unix.
      {
        tm_year = y - 1900;
        tm_mon = m - 1;
        tm_mday = d;
        tm_hour = hh;
        tm_min = mm;
        tm_sec = 0;
        tm_wday = 0;
        tm_yday = 0;
        tm_isdst = false;
      }
  ;;

  let to_human (y, m, d, hh, mm) =
    (y * 100000000) + (m * 1000000) + (d * 10000) + (hh * 100) + mm
  ;;

  let of_human n =
    let y = n / 100_000_000
    and m = n / 1_000_000 mod 100
    and d = n / 10_000 mod 100
    and hh = n / 100 mod 100
    and mm = n mod 100 in
    if
      y >= 1000
      && y <= 9999
      && m >= 1
      && m <= 12
      && d >= 1
      && d <= 31
      && hh <= 23
      && mm <= 59
    then Some (y, m, d, hh, mm)
    else None
  ;;
end

module Timestamp = struct
  type t = int

  let offset = 1_750_750_750
  let pack ts = ts - offset
  let unpack p = p + offset
end
