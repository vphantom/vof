module StringMap = Map.Make (String)
module IntMap = Map.Make (Int)

type schema = { path: string; keys: string list }

let make_schema ?(keys = []) path = { path; keys }

type context

let make_context () = failwith "unimplemented"

module Decimal = struct
  type t = int * int

  let pack (value, dec) =
    match dec with
    | 0 .. 6 -> (value lsl 3) lor tag
    | 7 -> ((value * 100) lsl 3) lor 7
    | 8 -> ((value * 10) lsl 3) lor 7
    | 9 -> (value lsl 3) lor 7
    | _ -> failwith "Vof.Decimal.pack: unsupported decimal places"
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
    | Some i -> Ok (i, B.length buf - !int_chars)
    | None -> Error "invalid decimal string"
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
      | Some n, Some d when d > 0 -> Ok (n, d)
      | Some _, Some _ -> Error "invalid ratio: denominator must be positive"
      | _ -> Error "invalid ratio"
    )
    | _ -> Error "invalid ratio"
  ;;

  let to_string (n, d) = Printf.sprintf "%d/%d" n d
end

module Date = struct
  type t = { year: int; month: int; day: int }

  let pack d = ((d.year - 1900) lsl 9) lor (d.month lsl 5) lor d.day

  let unpack i =
    (* TODO: range checks *)
    { year = (i lsr 9) + 1900; month = (i lsr 5) land 15; day = i land 31 }
  ;;

  let of_tm tm =
    { year = tm.tm_year + 1900; month = tm.tm_mon + 1; day = tm.tm_mday }
  ;;

  let to_tm { year; month; day } =
    { tm_year = year - 1900; tm_mon = month - 1; tm_mday = day }
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
    (* TODO: range checks *)
    {
      year = (i lsr 20) + 1900;
      month = (i lsr 16) land 15;
      day = (i lsr 11) land 31;
      hour = (i lsr 6) land 63;
      minute = i land 63;
    }
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
  | `Ndarray of int list * t list
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
  let int = function
    | `Bin_int n -> failwith "ZigZag decoding unimplemented"
    | `Txt_int n | `Int n -> Some n
    | `Txt_str s | `Int_str s | `String s -> int_of_string_opt s
    | _ -> None
  ;;

  let uint = function
    | `Bin_int n | `Txt_int n | `Uint n -> Some n
    | `Txt_str s | `Int_str s -> int_of_string_opt s
    | _ -> None
  ;;

  (* TODO: all other types in Vof.t *)
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
    if c <> 0 then c else List.compare compare v1 v2
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
