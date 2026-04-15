module StringMap = Map.Make (String)
module IntMap = Map.Make (Int)

type schema = { path: string; keys: string list }

let make_schema ?(keys = []) path = { path; keys }

let both_opt = function
  | Some a, Some b -> Some a, b
  | _ -> None
;;

let three_opt = function
  | Some a, Some b, Some c -> Some a, b, c
  | _ -> None
;;

module Context = struct
  type index = {
    mutable sym_ids: int StringMap.t;
    mutable id_syms: string array;
  }

  type t = {
    update: bool;
    mutable modified: bool;
    root: string;
    mutable registry: index StringMap.t;
  }

  let idx_make () = { sym_ids = StringMap.empty; id_syms = [||] }

  let idx_id ctx idx s =
    match ctx.update, StringMap.find_opt s idx.sym_ids with
    | false, None -> assert false
    | true, None ->
      let id = Array.length idx.id_syms in
      idx.id_syms <- Array.append idx.id_syms [| s |];
      idx.sym_ids <- StringMap.add s id idx.sym_ids;
      id
    | _, Some id -> id
  ;;

  let idx_sym ctx idx id =
    if id < 0 || id >= Array.length idx.id_syms
    then None
    else Some (Array.unsafe_get idx.id_syms id)
  ;;

  let make root path =
    { update; modified = false; root; registry = StringMap.empty }
  ;;

  let add ctx path =
    if not ctx.update then assert false;
    let idx = idx_make () in
    ctx.registry <- StringMap.add path idx ctx.registry;
    idx
  ;;

  let lookup ctx path =
    match StringMap.find_opt path ctx.registry with
    | None -> add ctx path
    | Some idx -> idx
  ;;

  let lookup_id ctx path s =
    let idx = lookup ctx path in
    idx_id ctx idx s
  ;;

  (* Remember to strip the root and '.' from each namespace. *)
  let load ?(update = false) root path = failwith "unimplemented"

  (* Remember to prepend the root to each namespace. *)
  let save ctx =
    if not ctx.update then assert false;
    if ctx.modified then failwith "unimplemented"
  ;;
end

module Decimal = struct
  type t = int * int

  let[@inline] optimize (value, dec) =
    let value, dec = ref value, ref dec in
    while !dec > 0 && !value mod 10 = 0 do
      value := !value / 10;
      decr dec
    done;
    !value, !dec
  ;;

  let pack (value, dec) =
    let value, dec = optimize (value, dec) in
    match dec with
    | 0 .. 6 -> (value lsl 3) lor dec
    | 7 -> ((value * 100) lsl 3) lor 7
    | 8 -> ((value * 10) lsl 3) lor 7
    | 9 -> (value lsl 3) lor 7
    | _ -> failwith "Vof.Decimal.pack: unsupported decimal places"
  ;;

  let unpack n =
    let dec = n land 7 in
    let value = n asr 3 in
    let value, dec = if dec <= 6 then value, dec else value, 9 in
    optimize (value, dec)
  ;;

  let of_string s =
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
    match int_of_string_opt (B.contents buf) with
    | Some i -> Some (i, B.length buf - !int_chars)
    | None -> None
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
    | _ -> failwith "decimals must be 0..9"
  ;;
end

module Ratio = struct
  type t = int * int

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
  type t = { year: int; month: int; day: int }

  let pack d = ((d.year - 1900) lsl 9) lor (d.month lsl 5) lor d.day

  let unpack i =
    let d =
      { year = (i lsr 9) + 1900; month = (i lsr 5) land 15; day = i land 31 }
    in
    if d.month >= 1 && d.month <= 12 && d.day >= 1 && d.day <= 31
    then Some d
    else None
  ;;

  let of_tm tm =
    { year = tm.tm_year + 1900; month = tm.tm_mon + 1; day = tm.tm_mday }
  ;;

  let to_tm { year; month; day } =
    { tm_year = year - 1900; tm_mon = month - 1; tm_mday = day }
  ;;

  let to_human d = (d.year * 10000) + (d.month * 100) + d.day

  let of_human n =
    let y = n / 10000
    and m = n mod 10000 / 100
    and d = n mod 100 in
    if y >= 1000 && y <= 9999 && m >= 1 && m <= 12 && d >= 1 && d <= 31
    then Some { year = y; month = m; day = d }
    else None
  ;;
end

module Datetime = struct
  type t = { year: int; month: int; day: int; hour: int; minute: int }

  let pack dt =
    ((dt.year - 1900) lsl 20)
    lor (dt.month lsl 16)
    lor (dt.day lsl 11)
    lor (dt.hour lsl 6)
    lor dt.minute
  ;;

  let unpack i =
    let dt =
      {
        year = (i lsr 20) + 1900;
        month = (i lsr 16) land 15;
        day = (i lsr 11) land 31;
        hour = (i lsr 6) land 63;
        minute = i land 63;
      }
    in
    if
      dt.month >= 1
      && dt.month <= 12
      && dt.day >= 1
      && dt.day <= 31
      && dt.hour <= 23
      && dt.minute <= 59
    then Some dt
    else None
  ;;

  let of_tm tm =
    {
      year = Unix.tm.tm_year + 1900;
      month = tm.tm_mon + 1;
      day = tm.tm_mday;
      hour = tm.tm_hour;
      minute = tm.tm_min;
    }
  ;;

  let to_tm { year; month; day; hour; minute } =
    {
      Uinx.tm_year = year - 1900;
      tm_mon = month - 1;
      tm_mday = day;
      tm_hour = hour;
      tm_min = minute;
    }
  ;;

  let to_human dt =
    (dt.year * 100000000)
    + (dt.month * 1000000)
    + (dt.day * 10000)
    + (dt.hour * 100)
    + dt.minute
  ;;

  let of_human n =
    let y = n / 100_000_000
    and m = n / 1_000_000 mod 100
    and d = n / 10_000 mod 100
    and h = n / 100 mod 100
    and min = n mod 100 in
    if
      y >= 1000
      && y <= 9999
      && m >= 1
      && m <= 12
      && d >= 1
      && d <= 31
      && h <= 23
      && min <= 59
    then Some { year = y; month = m; day = d; hour = h; minute = min }
    else None
  ;;
end

module Timestamp = struct
  type t = int

  let offset = 1_750_750_750
  let pack ts = ts - offset
  let unpack p = p + offset
end

type record = [ `Record of schema * t StringMap.t ]

type t = [
  `Null
  | `Bool of bool
  | `Int of int
  | `Uint of int
  | `Float of float
  | `String of string
  | `Data of bytes
  | `Enum of schema * string
  | `Variant of schema * string * t list
  | `Decimal of Decimal.t
  | `Ratio of Ratio.t
  | `Percent of Decimal.t
  | `Timestamp of int
  | `Date of Date.t
  | `Datetime of Datetime.t
  | `Timespan of int * int * int
  | `Code of string
  | `Language of string
  | `Country of string
  | `Subdivision of string
  | `Currency of string
  | `Tax_code of string
  | `Unit of string
  | `Text of string StringMap.t
  | `Amount of Decimal.t * string option
  | `Tax of Decimal.t * string option * string option
  | `Quantity of Decimal.t * string option
  | `Ip of bytes
  | `Subnet of bytes * int
  | `Coords of float * float
  | `Strmap of t StringMap.t
  | `Intmap of t IntMap.t
  | `List of t list
  | `Ndarray of int list * t array
  | record
  | `Series of record list
] [@@ocamlformat "disable"]

type input = [
  t
  | `Bin_int of int
  | `Bin_str of string
  | `Bin_list of input list
  | `Txt_int of int
  | `Txt_str of string
  | `Txt_list of input list
  | `Gap of int
  | `Vof_int of int
] [@@ocamlformat "disable"]

type 'k cache = ('k, t) Hashtbl.t

let make_cache () = Hashtbl.create 32

let cached cache key f =
  match Hashtbl.find_opt cache key with
  | Some v -> v
  | None ->
    let v = f () in
    Hashtbl.add cache key v; v
;;

module Reader = struct
  (* NOTE: Null not useful here *)

  let int = function
    | `Vof_int n -> (n lsr 1) lxor ~-(n land 1)
    | `Bin_int n | `Txt_int n | `Int n | `Uint n -> Some n
    | `Txt_str s | `Int_str s | `String s -> int_of_string_opt s
    | _ -> None
  ;;

  let uint = function
    | `Vof_int n | `Bin_int n | `Txt_int n | `Uint n -> Some n
    | `Txt_str s | `Int_str s -> int_of_string_opt s
    | _ -> None
  ;;

  let bool = function
    | `Bool b -> Some b
    | _ -> None
  ;;

  let float = function
    | `Float f -> Some f
    | `Bin_int n | `Txt_int n | `Int n | `Uint n -> Some (Float.of_int n)
    | `Txt_str s | `String s -> float_of_string_opt s
    | _ -> None
  ;;

  let string = function
    | `Txt_str s | `Bin_str s | `String s -> Some s
    | `Txt_int n | `Bin_int n | `Int n | `Uint n -> Some (Int.to_string n)
    | _ -> None
  ;;

  let code = string
  let language = string
  let country = string
  let subdivision = string
  let currency = string
  let tax_code = string
  let unit_ = string

  let data = function
    | `Txt_str s | `Bin_str s | `String s -> Some (Bytes.of_string s)
    | `Data d -> Some d
    | _ -> None
  ;;

  let decimal = function
    | `Decimal d -> Some d
    | `Bin_int n | `Vof_int n -> Some (Decimal.unpack n)
    | `Bin_str s | `Txt_str s | `String s -> Decimal.of_string s
    | _ -> None
  ;;

  let ratio = function
    | `Ratio r -> Some r
    | `Bin_list [ n; d ] | `Txt_list [ n; d ] | `List [ n; d ] ->
      both_opt (int n, uint d)
    | `Bin_str s | `Txt_str s | `String s -> Ratio.of_string s
    | _ -> None
  ;;

  let percent = function
    | `Percent d -> Some d
    | `Bin_int n | `Vof_int n -> Some (Decimal.unpack n)
    | `Txt_int i | `Int i | `Uint i -> Some (i, 2)
    | `Txt_str s | `String s ->
      let len = String.length s in
      if len > 1 && s.[len - 1] = '%'
      then (
        match Decimal.of_string s with
        | Some (v, p) -> Some (v / 100, p)
        | None -> None
      )
      else None
    | _ -> None
  ;;

  let timestamp = function
    | `Timestamp ts -> Some ts
    | `Bin_int n | `Vof_int n -> Some (Timestamp.unpack n)
    | `Txt_int n | `Int n -> Some n
    | `Txt_str s | `String s -> int_of_string_opt s
    | _ -> None
  ;;

  let date = function
    | `Date d -> Some d
    | `Bin_int n | `Vof_int n | `Int n | `Uint n -> Some (Date.unpack n)
    | `Txt_int n -> Date.of_human n
    | `Txt_str s -> (
      match int_of_string_opt s with
      | Some n -> Date.of_human n
      | None -> None
    )
    | _ -> None
  ;;

  let datetime = function
    | `Datetime dt -> Some dt
    | `Bin_int n | `Vof_int n | `Int n | `Uint n -> Some (Datetime.unpack n)
    | `Txt_int n -> Datetime.of_human n
    | `Txt_str s -> (
      match int_of_string_opt s with
      | Some n -> Datetime.of_human n
      | None -> None
    )
    | _ -> None
  ;;

  let timespan = function
    | `Timespan t -> Some t
    | `Bin_list [ a; b; c ] | `Txt_list [ a; b; c ] ->
      three_opt (int a, int b, int c)
    | _ -> None
  ;;

  let amount = function
    | `Amount a -> Some a
    | `Bin_int n | `Vof_int n -> Some (Decimal.unpack n, None)
    | `Bin_list [ d ] | `List [ d ] -> Some (d, None)
    | `Bin_list [ d; c ] | `List [ d; c ] -> (
      match decimal d, string c with
      | Some d, Some c -> Some (d, Some c)
      | _ -> None
    )
    | `Bin_str s | `Txt_str s | `String s -> (
      match String.split_on_char ' ' s with
      | [ ds ] -> Decimal.of_string ds |> Option.map (fun d -> d, None)
      | [ ds; cs ] -> Decimal.of_string ds |> Option.map (fun d -> d, Some cs)
      | _ -> None
    )
    | _ -> None
  ;;

  let quantity = function
    | `Quantity q -> Some q
    | `Bin_int n | `Vof_int n -> Some (Decimal.unpack n, None)
    | `Bin_list [ d ] | `List [ d ] -> Some (d, None)
    | `Bin_list [ d; u ] -> both_opt (decimal d, string u)
    | `Txt_str s | `String s -> (
      match String.split_on_char ' ' s with
      | [ ds ] -> Decimal.of_string ds |> Option.map (fun d -> d, None)
      | [ ds; us ] -> Decimal.of_string ds |> Option.map (fun d -> d, Some us)
      | _ -> None
    )
    | _ -> None
  ;;

  let tax = function
    | `Tax t -> Some t
    | `Bin_int n | `Vof_int n -> Some (Decimal.unpack n, None, None)
    | `Bin_list [ d ] | `List [ d ] -> Some (d, None, None)
    | `Bin_list [ d; t ] -> (
      match decimal d, string t with
      | Some d, Some t -> Some (d, None, Some t)
      | _ -> None
    )
    | `Bin_list [ d; t; c ] -> three_opt (decimal d, string t, string c)
    | `Txt_str s | `String s -> (
      match String.split_on_char ' ' s with
      | [ ds ] -> Decimal.of_string ds |> Option.map (fun d -> d, None, None)
      | [ ds; ts ] ->
        Decimal.of_string ds |> Option.map (fun d -> d, None, Some ts)
      | [ ds; cs; ts ] ->
        Decimal.of_string ds |> Option.map (fun d -> d, Some cs, Some ts)
      | _ -> None
    )
    | _ -> None
  ;;

  let coords = function
    | `Coords (a, b) -> Some (a, b)
    | `Bin_list [ a; b ] | `Txt_list [ a; b ] | `List [ a; b ] ->
      both_opt (float a, float b)
    | _ -> None
  ;;

  let ip = function
    | `Data d | `Ip d -> d
    | `Bin_str s -> Bytes.of_string s
    | `Txt_str s | `String s ->
      Ipaddr.of_string s |> Result.to_option |> Option.map Bytes.of_string
    | _ -> None
  ;;

  let subnet = function
    | `Subnet s -> Some s
    | `Bin_list [ a; n ] | `Txt_list [ a; n ] -> both_opt (ip a, uint n)
    | `Txt_str s | `String s -> (
      let module I = Ipaddr in
      let module IP = Ipaddr.Prefix in
      match IP.of_string s with
      | Ok p -> Some (IP.network p |> I.to_octets |> Bytes.of_string, IP.bits p)
      | Error _ -> none
    )
    | _ -> None
  ;;

  let strmap f = function
    | `List l | `Bin_list l | `Txt_list l ->
      let rec each sm = function
        | [] -> Some sm
        | k :: v :: rest -> (
          match string k, f v with
          | Some ks, Some v' -> each (StringMap.add ks v' sm) rest
          | _ -> None
        )
        | _ -> None
      in
      each StringMap.empty l
    | _ -> None
  ;;

  let text = strmap string

  let intmap f = function
    | `List l | `Bin_list l | `Txt_list l ->
      let rec each sm = function
        | [] -> Some sm
        | k :: v :: rest -> (
          match int k, f v with
          | Some ki, Some v' -> each (IntMap.add ki v' sm) rest
          | _ -> None
        )
        | _ -> None
      in
      each IntMap.empty l
    | _ -> None
  ;;

  exception Reader_return

  let list f = function
    | `List l | `Bin_list l | `Txt_list l -> (
      let[@tail_mod_cons] rec next = function
        | [] -> []
        | x :: xs -> (
          match f x with
          | Some x' -> x' :: next xs
          | None -> raise_notrace Reader_return
        )
      in
      try Some (next l) with Reader_return -> None
    )
    | _ -> None
  ;;

  let ndarray f v =
    let map_array sizes a =
      try
        let expected = List.fold_left ( * ) 1 sizes in
        if expected <> Array.length a then raise_notrace Reader_return;
        let next x =
          match f x with
          | Some v -> v
          | None -> raise_notrace Reader_return
        in
        let out = Array.map next a in
        Some (sizes, out)
      with Reader_return -> None
    in
    match v with
    | `Ndarray (sizes, vals) -> map_array sizes vals
    | `List (sizes :: vals)
    | `Bin_list (sizes :: vals)
    | `Txt_list (sizes :: vals) -> (
      match list int sizes with
      | Some sl -> Array.of_list vals |> map_array sl
      | None -> None
    )
    | _ -> None
  ;;

  let variant ctx schema f = function
    | `Enum (_, s) -> f s []
    | `Variant (_, s, l) -> f s (l :> input list)
    | `Bin_str s | `Txt_str s | `String s -> f s []
    | `Bin_int n | `Txt_int n | `Vof_int n | `Int n | `Uint n ->
      let idx = Context.lookup ctx schema.path in
      Context.idx_sym ctx idx n |> Option.bind (fun s -> f s [])
    | `Bin_list (s :: l) | `Txt_list (s :: l) | `List (s :: l) ->
      let idx = Context.lookup ctx schema.path in
      ( match s with
      | `Bin_int n | `Txt_int n | `Vof_int n | `Int n | `Uint n ->
        Context.idx_sym ctx idx n
      | `Bin_str s | `Txt_str s | `String s -> Some s
      | _ -> None
      )
      |> Option.bind (fun name -> f name l)
    | _ -> None
  ;;

  let record ctx schema f = function
    | `Record (_, sm) -> f sm
    | `Txt_list l | `List l ->
      let rec pairs sm = function
        | [] -> f sm
        | k :: v :: rest -> (
          match string k with
          | Some ks -> pairs (StringMap.add ks v sm) rest
          | None -> None
        )
        | _ -> None
      in
      pairs StringMap.empty l
    | `Bin_list l ->
      let idx = Context.lookup ctx schema.path in
      let rec next pos sm = function
        | [] -> f sm
        | `Gap n :: rest -> next (pos + n) sm rest
        | v :: rest ->
          let sm =
            match Context.idx_sym ctx idx pos with
            | Some k -> StringMap.add k v sm
            | None -> sm
          in
          next (pos + 1) sm rest
      in
      next 0 StringMap.empty l
    | _ -> None
  ;;

  let series ctx schema f = function
    | `Bin_list [] | `Txt_list [] | `List [] -> Some []
    | `Series l -> (
      let[@tail_mod_cons] rec next = function
        | [] -> []
        | `Record (_, sm) :: rest -> (
          match f sm with
          | Some v -> v :: next rest
          | None -> raise_notrace Reader_return
        )
      in
      try Some (next l) with Reader_return -> None
    )
    | `Txt_list (fields :: rows) | `List (fields :: rows) -> (
      match list string fields with
      | None -> None
      | Some names -> (
        let rec zip sm ks vs =
          match ks, vs with
          | k :: ks, v :: vs -> zip (StringMap.add k v sm) ks vs
          | _ -> f sm
        in
        let build_row = function
          | `Txt_list vals | `List vals -> zip StringMap.empty names vals
          | _ -> None
        in
        let[@tail_mod_cons] rec next = function
          | [] -> []
          | row :: rest -> (
            match build_row row with
            | Some v -> v :: next rest
            | None -> raise_notrace Reader_return
          )
        in
        try Some (next rows) with Reader_return -> None
      )
    )
    | `Bin_list (fields :: values) -> (
      let idx = Context.lookup ctx schema.path in
      match list uint fields with
      | None -> None
      | Some ids ->
        let names = List.filter_map (Context.idx_sym ctx idx) ids in
        if List.length names <> List.length ids
        then None
        else if names = []
        then Some []
        else (
          let remaining = ref values in
          let read_row () =
            let rec consume sm = function
              | [] -> sm
              | k :: ks -> (
                match !remaining with
                | v :: vs ->
                  remaining := vs;
                  consume (StringMap.add k v sm) ks
                | [] -> raise_notrace Reader_return
              )
            in
            consume StringMap.empty names
          in
          let[@tail_mod_cons] rec read_all () =
            match !remaining with
            | [] -> []
            | _ -> (
              match f (read_row ()) with
              | Some v -> v :: read_all ()
              | None -> raise_notrace Reader_return
            )
          in
          try Some (read_all ()) with Reader_return -> None
        )
    )
  ;;
end

(* PATCH *)

let tag : t -> int = function
  | `Null -> 0
  | `Bool _ -> 1
  | `Int _ -> 2
  | `Uint _ -> 3
  | `Float _ -> 4
  | `String _ -> 5
  | `Data _ -> 6
  | `Enum _ -> 7
  | `Variant _ -> 8
  | `Decimal _ -> 9
  | `Ratio _ -> 10
  | `Percent _ -> 11
  | `Timestamp _ -> 12
  | `Date _ -> 13
  | `Datetime _ -> 14
  | `Timespan _ -> 15
  | `Code _ -> 16
  | `Language _ -> 17
  | `Country _ -> 18
  | `Subdivision _ -> 19
  | `Currency _ -> 20
  | `Tax_code _ -> 21
  | `Unit _ -> 22
  | `Text _ -> 23
  | `Amount _ -> 24
  | `Tax _ -> 25
  | `Quantity _ -> 26
  | `Ip _ -> 27
  | `Subnet _ -> 28
  | `Coords _ -> 29
  | `Strmap _ -> 30
  | `Intmap _ -> 31
  | `List _ -> 32
  | `Ndarray _ -> 33
  | `Record _ -> 34
  | `Series _ -> 35
;;

(* NOTE: OCaml 5.4 will have Array.compare *)
let array_compare cmp a1 a2 =
  let n = min (Array.length v1) (Array.length v2) in
  let rec next i =
    if i >= n
    then Int.compare (Array.length v1) (Array.length v2)
    else (
      let c = compare v1.(i) v2.(i) in
      if c <> 0 then c else next (i + 1)
    )
  in
  next 0
;;

let rec compare (a : t) (b : t) : int =
  match a, b with
  | `Null, `Null -> 0
  | `Bool a, `Bool b -> Bool.compare a b
  | `Int a, `Int b | `Uint a, `Uint b | `Timestamp a, `Timestamp b ->
    Int.compare a b
  | `Float a, `Float b -> Float.compare a b
  | `String a, `String b
  | `Code a, `Code b
  | `Language a, `Language b
  | `Country a, `Country b
  | `Subdivision a, `Subdivision b
  | `Currency a, `Currency b
  | `Tax_code a, `Tax_code b
  | `Unit a, `Unit b -> String.compare a b
  | `Data a, `Data b | `Ip a, `Ip b -> Bytes.compare a b
  | `Enum (_, a), `Enum (_, b) -> String.compare a b
  | `Variant (_, sa, la), `Variant (_, sb, lb) ->
    let c = String.compare sa sb in
    if c <> 0 then c else List.compare compare la lb
  | `Decimal (v1, d1), `Decimal (v2, d2)
  | `Ratio (v1, d1), `Ratio (v2, d2)
  | `Percent a, `Percent b -> Stdlib.compare a b
  | `Date a, `Date b -> Stdlib.compare a b
  | `Datetime a, `Datetime b -> Stdlib.compare a b
  | `Timespan a, `Timespan b -> Stdlib.compare a b
  | `Text a, `Text b -> StringMap.compare String.compare a b
  | `Amount a, `Amount b | `Quantity a, `Quantity b -> compare a b
  | `Tax a, `Tax b -> compare a b
  | `Subnet a, `Subnet b -> compare a b
  | `Coords a, `Coords b -> compare a b
  | `Strmap a, `Strmap b -> StringMap.compare compare a b
  | `Intmap a, `Intmap b -> IntMap.compare compare a b
  | `Record (_, a), `Record (_, b) -> StringMap.compare compare a b
  | `List a, `List b -> List.compare compare a b
  | `Ndarray (s1, v1), `Ndarray (s2, v2) ->
    let c = List.compare Int.compare s1 s2 in
    if c <> 0 then c else array_compare compare v1 v2
  | `Series a, `Series b ->
    List.compare
      (fun (`Record (_, a)) (`Record (_, b)) -> StringMap.compare compare a b)
      a b
  | a, b -> Int.compare (tag a) (tag b)
;;

let all_records =
  List.for_all (function
    | `Record _ -> true
    | _ -> false
    )
;;

module KeyMap = Map.Make (struct
  type nonrec t = t list

  let compare = Stdlib.compare
end)

let rec diff (`Record (sa, a)) (`Record (_, b)) =
  let is_key k = List.mem k sa.keys in
  let collect_keys acc k =
    match StringMap.find_opt k b with
    | Some v -> StringMap.add k v acc
    | None -> acc
  in
  let merge_field k vb acc =
    if is_key k
    then acc
    else (
      match StringMap.find_opt k a with
      | None -> StringMap.add k vb acc
      | Some va -> diff_field k va vb acc
    )
  in
  let unset_removed k _ acc =
    if is_key k || StringMap.mem k b then acc else StringMap.add k `Null acc
  in
  let result =
    List.fold_left collect_keys StringMap.empty sa.keys
    |> StringMap.fold merge_field b
    |> StringMap.fold unset_removed a
  in
  `Record (sa, result)

and diff_field k va vb acc =
  match va, vb with
  | (`Record _ as ra), (`Record _ as rb) ->
    let (`Record (s, dm) as d) = diff ra rb in
    if StringMap.for_all (fun f _ -> List.mem f s.keys) dm
    then acc
    else StringMap.add k (d :> t) acc
  | `List ol, `List nl
    when (ol <> [] || nl <> []) && all_records ol && all_records nl -> (
    match diff_record_list ol nl with
    | [] -> acc
    | dl -> StringMap.add k (`List dl) acc
  )
  | _ -> if compare va vb = 0 then acc else StringMap.add k vb acc

and diff_record_list old_list new_list =
  let schema =
    match old_list @ new_list with
    | `Record (s, _) :: _ -> s
    | _ -> assert false
  in
  let keys = schema.keys in
  if keys = [] then invalid_arg "diff_record_list: schema without keys";
  let key_of sm = List.map (fun k -> StringMap.find k sm) keys in
  let strip_keys sm =
    List.fold_left (fun m k -> StringMap.remove k m) sm keys
  in
  let restrict_to_keys sm =
    List.fold_left
      (fun m k ->
        match StringMap.find_opt k sm with
        | Some v -> StringMap.add k v m
        | None -> m
      )
      StringMap.empty keys
  in
  let old_map =
    List.fold_left
      (fun acc (`Record (_, sm) as r) -> KeyMap.add (key_of sm) r acc)
      KeyMap.empty old_list
  in
  let process_new_item (results, consumed) (`Record (s, sm) as nr) =
    let kt = key_of sm in
    match KeyMap.find_opt kt old_map with
    | None -> (nr :> t) :: results, consumed
    | Some (`Record _ as or_) ->
      let consumed = KeyMap.add kt () consumed in
      let (`Record (_, dm) as d) = diff or_ nr in
      if StringMap.for_all (fun f _ -> List.mem f keys) dm
      then results, consumed
      else (d :> t) :: results, consumed
  in
  let rev_results, consumed =
    List.fold_left process_new_item ([], KeyMap.empty) new_list
  in
  let collect_deleted acc (`Record (s, sm)) =
    if KeyMap.mem (key_of sm) consumed
    then acc
    else (`Record (s, restrict_to_keys sm) :> t) :: acc
  in
  old_list |> List.fold_left collect_deleted [] |> List.rev_append rev_results
;;
