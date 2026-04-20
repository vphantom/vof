module StringMap = Map.Make (String)
module IntMap = Map.Make (Int)

let ( let| ) = Option.bind

type schema = { path: string; keys: string list; required: string list }

let make_schema ?(keys = []) ?(required = []) path = { path; keys; required }

let both_opt = function
  | Some a, Some b -> Some (a, b)
  | _ -> None
;;

let three_opt = function
  | Some a, Some b, Some c -> Some (a, b, c)
  | _ -> None
;;

let rec stringmap_zip sm ks vs =
  match ks, vs with
  | k :: ks, v :: vs -> stringmap_zip (StringMap.add k v sm) ks vs
  | _ -> sm
;;

module Decimal = struct
  type t = int * int

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
    | _ -> failwith "Vof.Decimal.pack: unsupported decimal places"
  ;;

  let unpack n =
    let value = n asr 2 in
    match n land 3 with
    | 0 -> value, 0
    | 1 -> optimize (value, 2)
    | 2 -> optimize (value, 4)
    | 3 -> optimize (value, 9)
    | _ -> assert false
  ;;

  let to_n (value, dec) =
    if dec < 0 || dec > 9
    then failwith "Vof.Decimal.to_n: unsupported decimal places";
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
    let| i = int_of_string_opt (B.contents buf) in
    Some (i, B.length buf - !int_chars)
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
    Unix.{ year = tm.tm_year + 1900; month = tm.tm_mon + 1; day = tm.tm_mday }
  ;;

  let to_tm { year; month; day } =
    Unix.
      {
        tm_year = year - 1900;
        tm_mon = month - 1;
        tm_mday = day;
        tm_hour = 0;
        tm_min = 0;
        tm_sec = 0;
        tm_wday = 0;
        tm_yday = 0;
        tm_isdst = false;
      }
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
    Unix.
      {
        year = tm.tm_year + 1900;
        month = tm.tm_mon + 1;
        day = tm.tm_mday;
        hour = tm.tm_hour;
        minute = tm.tm_min;
      }
  ;;

  let to_tm { year; month; day; hour; minute } =
    Unix.
      {
        tm_year = year - 1900;
        tm_mon = month - 1;
        tm_mday = day;
        tm_hour = hour;
        tm_min = minute;
        tm_sec = 0;
        tm_wday = 0;
        tm_yday = 0;
        tm_isdst = false;
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
  | `Tax of Decimal.t * string * string option
  | `Quantity of Decimal.t * string option
  | `Ip of bytes
  | `Subnet of bytes * int
  | `Coords of float * float
  | `Strmap of t StringMap.t
  | `Uintmap of t IntMap.t
  | `List of t list
  | `Ndarray of int list * t array
  | `Record of schema * t StringMap.t
  | `Series of [ `Record of schema * t StringMap.t ] list
] [@@ocamlformat "disable"]

type record = [ `Record of schema * t StringMap.t ]

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
  | `Vof_list of input list
  | `Vof_tag of int * input
] [@@ocamlformat "disable"]

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
    mutable fetchers: (record -> record option) StringMap.t;
  }

  let add_fetchers ctx fl =
    let add sm (k, v) = StringMap.add k v sm in
    ctx.fetchers <- List.fold_left add ctx.fetchers fl
  ;;

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

  let idx_sym idx id =
    if id < 0 || id >= Array.length idx.id_syms
    then None
    else Some (Array.unsafe_get idx.id_syms id)
  ;;

  let make ?(update = false) root =
    {
      update;
      modified = false;
      root;
      registry = StringMap.empty;
      fetchers = StringMap.empty;
    }
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
  let load ?(update = false) root path =
    ignore (update, root, path);
    failwith "unimplemented"
  ;;

  (* Remember to prepend the root to each namespace. *)
  let save ctx =
    if not ctx.update then assert false;
    if ctx.modified then failwith "unimplemented"
  ;;
end

module KeyMap = Map.Make (struct
  type nonrec t = t list

  let compare = Stdlib.compare
end)

module Reader = struct
  (* NOTE: Null not useful here *)

  exception Reader_return

  let[@tail_mod_cons] rec map_some f = function
    | [] -> []
    | x :: xs -> (
      match f x with
      | Some v -> v :: map_some f xs
      | None -> raise_notrace Reader_return
    )
  ;;

  let[@inline] zigzag i = (i lsr 1) lxor ~-(i land 1)

  let int = function
    | `Vof_int n -> Some (zigzag n)
    | `Bin_int n | `Txt_int n | `Int n | `Uint n -> Some n
    | `Txt_str s | `Bin_str s | `String s -> int_of_string_opt s
    | _ -> None
  ;;

  let uint = function
    | `Vof_int n | `Bin_int n | `Txt_int n | `Uint n -> Some n
    | `Txt_str s | `Bin_str s -> int_of_string_opt s
    | _ -> None
  ;;

  let bool = function
    | `Bool b -> Some b
    | `Vof_int i | `Bin_int i | `Txt_int i | `Int i | `Uint i -> Some (i <> 0)
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

  let unalt_int i =
    match i with
    | `Vof_tag (-1, `Vof_int n) -> `Vof_int (-n)
    | _ -> i
  ;;

  let decimal = function
    | `Decimal d -> Some d
    | `Bin_int n -> Decimal.of_n n
    | `Vof_int n -> Some (Decimal.unpack n)
    | `Vof_tag (-1, `Vof_int n) -> Some (Decimal.unpack (-n))
    | `Bin_str s | `Txt_str s | `String s -> Decimal.of_string s
    | _ -> None
  ;;

  let ratio = function
    | `Ratio r -> Some r
    | `Bin_list [ n; d ]
    | `Txt_list [ n; d ]
    | `Vof_list [ n; d ]
    | `List [ n; d ] -> both_opt (int n, uint d)
    | `Bin_str s | `Txt_str s | `String s -> Ratio.of_string s
    | _ -> None
  ;;

  let percent = function
    | `Percent d -> Some d
    | `Txt_int i | `Int i | `Uint i -> Some (i, 2)
    | `Txt_str s | `String s ->
      let len = String.length s in
      if len > 1 && s.[len - 1] = '%' then Decimal.of_string s else None
    | _ as p -> decimal p
  ;;

  let timestamp = function
    | `Timestamp ts -> Some ts
    | `Bin_int n -> Some n
    | `Vof_int n -> Some (zigzag n |> Timestamp.unpack)
    | `Txt_int n | `Int n -> Some n
    | `Txt_str s | `String s -> int_of_string_opt s
    | _ -> None
  ;;

  let date = function
    | `Date d -> Some d
    | `Bin_int n | `Vof_int n | `Int n | `Uint n -> Date.unpack n
    | `Txt_int n -> Date.of_human n
    | `Txt_str s ->
      let| n = int_of_string_opt s in
      Date.of_human n
    | `Txt_list [ y; m; d ]
    | `Bin_list [ y; m; d ]
    | `Vof_list [ y; m; d ]
    | `List [ y; m; d ] ->
      let| y, m, d = three_opt (int y, int m, int d) in
      Some { Date.year = y; month = m; day = d }
    | _ -> None
  ;;

  let datetime = function
    | `Datetime dt -> Some dt
    | `Bin_int n | `Vof_int n | `Int n | `Uint n -> Datetime.unpack n
    | `Txt_int n -> Datetime.of_human n
    | `Txt_str s ->
      let| n = int_of_string_opt s in
      Datetime.of_human n
    | `Txt_list [ y; m; d; h; min ]
    | `Bin_list [ y; m; d; h; min ]
    | `Vof_list [ y; m; d; h; min ]
    | `List [ y; m; d; h; min ] ->
      let| y, m, d = three_opt (int y, int m, int d) in
      let| h, min = both_opt (int h, int min) in
      Some { Datetime.year = y; month = m; day = d; hour = h; minute = min }
    | _ -> None
  ;;

  let timespan = function
    | `Timespan t -> Some t
    | `Bin_list [ a; b; c ] | `Txt_list [ a; b; c ] | `Vof_list [ a; b; c ] ->
      three_opt (int a, int b, int c)
    | _ -> None
  ;;

  let decimal_qual = function
    | `Bin_list [ d; c ] | `Vof_list [ d; c ] | `List [ d; c ] -> (
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
    | `Bin_list [ d ] | `Vof_list [ d ] | `List [ d ] | d ->
      let| d = decimal d in
      Some (d, None)
  ;;

  let amount = function
    | `Amount a -> Some a
    | d -> decimal_qual d
  ;;

  let quantity = function
    | `Quantity q -> Some q
    | d -> decimal_qual d
  ;;

  let tax = function
    | `Tax t -> Some t
    | `Bin_list [ d; t ] | `Vof_list [ d; t ] -> (
      match decimal d, string t with
      | Some d, Some t -> Some (d, t, None)
      | _ -> None
    )
    | `Bin_list [ d; t; c ] | `Vof_list [ d; t; c ] -> (
      match decimal d, string t, string c with
      | Some d, Some t, Some c -> Some (d, t, Some c)
      | _ -> None
    )
    | `Txt_str s | `String s -> (
      match String.split_on_char ' ' s with
      | [ ds; ts ] -> Decimal.of_string ds |> Option.map (fun d -> d, ts, None)
      | [ ds; ts; cs ] ->
        Decimal.of_string ds |> Option.map (fun d -> d, ts, Some cs)
      | _ -> None
    )
    | _ -> None
  ;;

  let coords = function
    | `Coords (a, b) -> Some (a, b)
    | `Bin_list [ a; b ]
    | `Txt_list [ a; b ]
    | `Vof_list [ a; b ]
    | `List [ a; b ] -> both_opt (float a, float b)
    | _ -> None
  ;;

  let ip = function
    | `Data d | `Ip d -> Some d
    | `Bin_str s -> Some (Bytes.of_string s)
    | `Txt_str s | `String s ->
      Ipaddr.of_string s
      |> Result.to_option
      |> Option.map (fun a -> Ipaddr.to_octets a |> Bytes.of_string)
    | _ -> None
  ;;

  let subnet = function
    | `Subnet s -> Some s
    | `Bin_list [ a; n ] | `Txt_list [ a; n ] | `Vof_list [ a; n ] ->
      both_opt (ip a, uint n)
    | `Txt_str s | `String s -> (
      let module I = Ipaddr in
      let module IP = Ipaddr.Prefix in
      match IP.of_string s with
      | Ok p -> Some (IP.network p |> I.to_octets |> Bytes.of_string, IP.bits p)
      | Error _ -> None
    )
    | _ -> None
  ;;

  let strmap f = function
    | `List l | `Bin_list l | `Txt_list l | `Vof_list l ->
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

  let text v = strmap string v

  let uintmap f = function
    | `List l | `Bin_list l | `Txt_list l | `Vof_list l ->
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

  let list f = function
    | `List l | `Bin_list l | `Txt_list l | `Vof_list l -> (
      try Some (map_some f l) with Reader_return -> None
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
    | `Txt_list (sizes :: vals)
    | `Vof_list (sizes :: vals) ->
      let| sl = list int sizes in
      Array.of_list vals |> map_array sl
    | _ -> None
  ;;

  let variant ctx schema f v =
    let enum v =
      let idx = Context.lookup ctx schema.path in
      match v with
      | `Bin_int n | `Txt_int n | `Vof_int n | `Int n | `Uint n ->
        Context.idx_sym idx n
      | _ -> None
    in
    match v with
    | `Enum (_, s) -> f s []
    | `Variant (_, s, l) -> f s (l :> input list)
    | `Bin_str s | `Txt_str s | `String s -> f s []
    | `Bin_list (s :: l)
    | `Txt_list (s :: l)
    | `Vof_list (s :: l)
    | `List (s :: l) ->
      let| name = enum s in
      f name l
    | _ -> enum v
  ;;

  let record ctx schema f = function
    | `Record (_, sm) -> f sm
    | `Txt_list l | `List l ->
      let rec pairs sm = function
        | [] -> f sm
        | k :: v :: rest ->
          let| ks = string k in
          pairs (StringMap.add ks v sm) rest
        | _ -> None
      in
      pairs StringMap.empty l
    | `Bin_list l ->
      let idx = Context.lookup ctx schema.path in
      let rec pairs sm = function
        | [] -> f sm
        | k :: v :: rest -> (
          let| id = uint k in
          match Context.idx_sym idx id with
          | Some name -> pairs (StringMap.add name v sm) rest
          | None -> pairs sm rest
        )
        | _ -> None
      in
      pairs StringMap.empty l
    | `Vof_list l ->
      let idx = Context.lookup ctx schema.path in
      let rec next pos sm = function
        | [] -> f sm
        | `Gap n :: rest -> next (pos + n) sm rest
        | v :: rest ->
          let sm =
            match Context.idx_sym idx pos with
            | Some k -> StringMap.add k v sm
            | None -> sm
          in
          next (pos + 1) sm rest
      in
      next 0 StringMap.empty l
    | _ -> None
  ;;

  let series ctx schema f = function
    | `Bin_list [] | `Txt_list [] | `Vof_list [] | `List [] -> Some []
    | `Series l -> (
      try Some (map_some (fun (`Record (_, sm)) -> f sm) l)
      with Reader_return -> None
    )
    | `Txt_list (fields :: rows) | `List (fields :: rows) -> (
      let build_row names = function
        | `Txt_list vals | `List vals ->
          stringmap_zip StringMap.empty names vals |> f
        | _ -> None
      in
      let| names = list string fields in
      try Some (map_some (build_row names) rows) with Reader_return -> None
    )
    | `Bin_list (fields :: rows) ->
      let| ids = list uint fields in
      let idx = Context.lookup ctx schema.path in
      let names = List.filter_map (Context.idx_sym idx) ids in
      let build_row = function
        | `Bin_list vals -> stringmap_zip StringMap.empty names vals |> f
        | _ -> None
      in
      if List.length names <> List.length ids
      then None
      else if names = []
      then Some []
      else (try Some (map_some build_row rows) with Reader_return -> None)
    | `Vof_list (fields :: values) ->
      let idx = Context.lookup ctx schema.path in
      let| ids = list uint fields in
      let names = List.filter_map (Context.idx_sym idx) ids in
      let remaining = ref values in
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
      let[@tail_mod_cons] rec read_all () =
        match !remaining with
        | [] -> []
        | _ -> (
          match f (consume StringMap.empty names) with
          | Some v -> v :: read_all ()
          | None -> raise_notrace Reader_return
        )
      in
      if List.length names <> List.length ids
      then None
      else if names = []
      then Some []
      else (try Some (read_all ()) with Reader_return -> None)
  ;;
end

(* Collect all fields from all records, resolve to IDs, return sorted by ID *)
let series_fields ctx schema records =
  let idx = Context.lookup ctx schema.path in
  let collect acc (`Record (_, sm)) =
    StringMap.fold (fun k _ a -> StringMap.add k () a) sm acc
  in
  let all = List.fold_left collect StringMap.empty records in
  let pairs =
    StringMap.fold
      (fun name () acc -> (name, Context.idx_id ctx idx name) :: acc)
      all []
  in
  List.sort (fun (_, a) (_, b) -> Int.compare a b) pairs
;;

(* Extract one row's values in field order *)
let series_row fields sm =
  List.map
    (fun (name, _) ->
      match StringMap.find_opt name sm with
      | Some v -> v
      | None -> `Null
    )
    fields
;;

(* PATCH *)

let rec equal (a : t) (b : t) : bool =
  match a, b with
  | `Float a, `Float b -> Float.equal a b
  | `Coords (a1, a2), `Coords (b1, b2) -> Float.equal a1 b1 && Float.equal a2 b2
  | `Enum (_, a), `Enum (_, b) -> String.equal a b
  | `Variant (_, sa, la), `Variant (_, sb, lb) -> (sa, la) = (sb, lb)
  | `Text a, `Text b -> StringMap.equal String.equal a b
  | `Strmap a, `Strmap b -> StringMap.equal equal a b
  | `Uintmap a, `Uintmap b -> IntMap.equal equal a b
  | `Record (_, a), `Record (_, b) -> StringMap.equal equal a b
  | `List a, `List b -> List.equal equal a b
  | `Ndarray (s1, v1), `Ndarray (s2, v2) ->
    let n = Array.length v1 in
    let rec loop i = i >= n || (equal v1.(i) v2.(i) && loop (i + 1)) in
    List.equal Int.equal s1 s2 && n = Array.length v2 && loop 0
  | `Series a, `Series b ->
    List.equal
      (fun (`Record (_, a)) (`Record (_, b)) -> StringMap.equal equal a b)
      a b
  | a, b -> a = b
;;

let as_records l =
  List.filter_map
    (function
      | `Record _ as r -> Some r
      | _ -> None
      )
    l
;;

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
  | `List ol, `List nl when ol <> [] || nl <> [] ->
    let ol' = as_records ol
    and nl' = as_records nl in
    if List.length ol' = List.length ol && List.length nl' = List.length nl
    then (
      match diff_record_list ol' nl' with
      | [] -> acc
      | dl -> StringMap.add k (`List dl) acc
    )
    else if compare va vb = 0
    then acc
    else StringMap.add k vb acc
  | _ -> if compare va vb = 0 then acc else StringMap.add k vb acc

and diff_record_list (old_list : record list) (new_list : record list) =
  let schema =
    match old_list @ new_list with
    | `Record (s, _) :: _ -> s
    | _ -> assert false
  in
  let keys = schema.keys in
  if keys = [] then invalid_arg "diff_record_list: schema without keys";
  let key_of sm = List.map (fun k -> StringMap.find k sm) keys in
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
  let process_new_item (results, consumed) (`Record (_, sm) as nr) =
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
