open Vof_lib
module StringSet = Set.Make (String)
module StringMap = Map.Make (String)
module IntMap = Map.Make (Int)

let ( let| ) = Option.bind

exception Vof_return

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

type decimal = int * int
type ratio = int * int
type date = { year: int; month: int; day: int }
type datetime = { year: int; month: int; day: int; hour: int; minute: int }

type t =
  | Null
  | Bool of bool
  | Int of int
  | Uint of int
  | Float of float
  | String of string
  | Data of bytes
  | Enum of schema * string
  | Variant of schema * string * t list
  | Decimal of decimal
  | Ratio of ratio
  | Percent of decimal
  | Timestamp of int
  | Date of date
  | Datetime of datetime
  | Timespan of int * int * int
  | Code of string
  | Language of string
  | Country of string
  | Subdivision of string
  | Currency of string
  | Tax_code of string
  | Unit of string
  | Text of string StringMap.t
  | Amount of decimal * string option
  | Tax of decimal * string * string option
  | Quantity of decimal * string option
  | Ip of bytes
  | Subnet of bytes * int
  | Coords of float * float
  | Strmap of t StringMap.t
  | Uintmap of t IntMap.t
  | List of t list
  | Ndarray of int list * t array
  | Record of record
  | Series of record list
  | Raw_bint of int
  | Raw_blist of t list
  | Raw_bstr of string
  | Raw_gap of int
  | Raw_int of int
  | Raw_list of t list
  | Raw_tag of int * t
  | Raw_tint of int
  | Raw_tlist of t list
  | Raw_tstr of string

and record = schema * t StringMap.t

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

  type fetcher = string * (record -> record option)

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

  let[@tail_mod_cons] rec map_some f = function
    | [] -> []
    | x :: xs -> (
      match f x with
      | Some v -> v :: map_some f xs
      | None -> raise_notrace Vof_return
    )
  ;;

  let[@inline] zigzag i = (i lsr 1) lxor ~-(i land 1)

  let int = function
    | Raw_int n -> Some (zigzag n)
    | Raw_bint n | Raw_tint n | Int n | Uint n -> Some n
    | Raw_tstr s | Raw_bstr s | String s -> int_of_string_opt s
    | _ -> None
  ;;

  let uint = function
    | Raw_int n | Raw_bint n | Raw_tint n | Uint n -> Some n
    | Int i -> if i >= 0 then Some i else None
    | Raw_tstr s | Raw_bstr s -> int_of_string_opt s
    | _ -> None
  ;;

  let bool = function
    | Null -> Some false
    | Bool b -> Some b
    | Raw_int i | Raw_bint i | Raw_tint i | Int i | Uint i -> Some (i <> 0)
    | Float f -> Some (f <> 0.0)
    | Decimal (d, _) | Ratio (d, _) | Percent (d, _) -> Some (d <> 0)
    | Amount ((d, _), _) | Quantity ((d, _), _) | Tax ((d, _), _, _) ->
      Some (d <> 0)
    | Text sm -> Some (StringMap.cardinal sm <> 0)
    | Strmap sm -> Some (StringMap.cardinal sm <> 0)
    | Uintmap um -> Some (IntMap.cardinal um <> 0)
    | List l -> Some (List.length l <> 0)
    | _ -> None
  ;;

  let float = function
    | Float f -> Some f
    | Raw_bint n | Raw_tint n | Int n | Uint n -> Some (Float.of_int n)
    | Raw_bstr s | Raw_tstr s | String s -> float_of_string_opt s
    | _ -> None
  ;;

  let string = function
    | Raw_tstr s | Raw_bstr s | String s -> Some s
    | Raw_tint n | Raw_bint n | Int n | Uint n -> Some (Int.to_string n)
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
    | Raw_tstr s | Raw_bstr s | String s -> Some (Bytes.of_string s)
    | Data d -> Some d
    | _ -> None
  ;;

  let decimal = function
    | Decimal d | Percent d -> Some d
    | Raw_bint n -> Decimal.of_n n
    | Raw_int n -> Some (Decimal.unpack n)
    | Raw_tag (-1, Raw_int n) -> Some (Decimal.unpack (-n))
    | Raw_bstr s | Raw_tstr s | String s -> Decimal.of_string s
    | _ -> None
  ;;

  let ratio = function
    | Ratio r -> Some r
    | Raw_blist [ n; d ] | Raw_tlist [ n; d ] | Raw_list [ n; d ] ->
      both_opt (int n, uint d)
    | Raw_bstr s | Raw_tstr s | String s -> Ratio.of_string s
    | _ -> None
  ;;

  let percent = function
    | Percent d | Decimal d -> Some d
    | Raw_bint n -> Decimal.of_n n
    | Raw_int d -> Some (Decimal.unpack d)
    | Raw_tint i -> Some (Decimal.optimize (i, 2))
    | Raw_bstr s | Raw_tstr s | String s ->
      let len = String.length s in
      if len > 1 && s.[len - 1] = '%'
      then Decimal.of_string ~shift:2 s
      else None
    | _ -> None
  ;;

  let timestamp = function
    | Timestamp ts | Uint ts | Int ts | Raw_tint ts -> Some ts
    | Raw_bint n -> Some n
    | Raw_int n -> Some (zigzag n |> Timestamp.unpack)
    | Raw_tstr s | Raw_bstr s | String s -> int_of_string_opt s
    | _ -> None
  ;;

  let date d =
    let conv = function
      | Some (y, m, d) -> Some { year = y; month = m; day = d }
      | None -> None
    in
    match d with
    | Date d -> Some d
    | Datetime dt -> Some { year = dt.year; month = dt.month; day = dt.day }
    | Raw_bint n | Raw_int n -> Date.unpack n |> conv
    | Raw_tint n -> Date.of_human n |> conv
    | Raw_tstr s ->
      let| n = int_of_string_opt s in
      Date.of_human n |> conv
    | Raw_tlist [ y; m; d ]
    | Raw_blist [ y; m; d ]
    | Raw_list [ y; m; d ]
    | List [ y; m; d ] ->
      let| year, month, day = three_opt (int y, int m, int d) in
      Some { year; month; day }
    | _ -> None
  ;;

  let datetime dt =
    let conv = function
      | Some (year, month, day, hour, minute) ->
        Some { year; month; day; hour; minute }
      | None -> None
    in
    match dt with
    | Datetime dt -> Some dt
    | Date d ->
      Some { year = d.year; month = d.month; day = d.day; hour = 0; minute = 0 }
    | Raw_bint n | Raw_int n | Int n | Uint n -> Datetime.unpack n |> conv
    | Raw_tint n -> Datetime.of_human n |> conv
    | Raw_tstr s ->
      let| n = int_of_string_opt s in
      Datetime.of_human n |> conv
    | Raw_tlist [ y; m; d; hh; mm ]
    | Raw_blist [ y; m; d; hh; mm ]
    | Raw_list [ y; m; d; hh; mm ]
    | List [ y; m; d; hh; mm ] ->
      let| year, month, day = three_opt (int y, int m, int d) in
      let| hour, minute = both_opt (int hh, int mm) in
      Some { year; month; day; hour; minute }
    | _ -> None
  ;;

  let timespan = function
    | Timespan (a, b, c) -> Some (a, b, c)
    | Raw_blist [ a; b; c ]
    | Raw_tlist [ a; b; c ]
    | Raw_list [ a; b; c ]
    | List [ a; b; c ] -> three_opt (int a, int b, int c)
    | _ -> None
  ;;

  let decimal_qual = function
    | Raw_bstr s | Raw_tstr s | String s -> (
      match String.split_on_char ' ' s with
      | [ ds ] -> Decimal.of_string ds |> Option.map (fun d -> d, None)
      | [ ds; cs ] -> Decimal.of_string ds |> Option.map (fun d -> d, Some cs)
      | _ -> None
    )
    | Raw_blist [ d; c ]
    | Raw_list [ d; c ]
    | Raw_tlist [ d; c ]
    | List [ d; c ] -> (
      match decimal d, string c with
      | Some d, Some c -> Some (d, Some c)
      | _ -> None
    )
    | Raw_blist [ d ] | Raw_list [ d ] | List [ d ] | d ->
      let| d = decimal d in
      Some (d, None)
  ;;

  let amount = function
    | Amount (a, b) -> Some (a, b)
    | d -> decimal_qual d
  ;;

  let quantity = function
    | Quantity (a, b) -> Some (a, b)
    | d -> decimal_qual d
  ;;

  let tax = function
    | Tax (a, b, c) -> Some (a, b, c)
    | Raw_blist [ d; t ]
    | Raw_list [ d; t ]
    | Raw_tlist [ d; t ]
    | List [ d; t ] -> (
      match decimal d, string t with
      | Some d, Some t -> Some (d, t, None)
      | _ -> None
    )
    | Raw_blist [ d; t; c ] | Raw_list [ d; t; c ] -> (
      match decimal d, string t, string c with
      | Some d, Some t, Some c -> Some (d, t, Some c)
      | _ -> None
    )
    | Raw_tstr s | Raw_bstr s | String s -> (
      match String.split_on_char ' ' s with
      | [ ds; ts ] -> Decimal.of_string ds |> Option.map (fun d -> d, ts, None)
      | [ ds; ts; cs ] ->
        Decimal.of_string ds |> Option.map (fun d -> d, ts, Some cs)
      | _ -> None
    )
    | _ -> None
  ;;

  let coords = function
    | Coords (a, b) -> Some (a, b)
    | Raw_blist [ a; b ]
    | Raw_tlist [ a; b ]
    | Raw_list [ a; b ]
    | List [ a; b ] -> both_opt (float a, float b)
    | _ -> None
  ;;

  let ip = function
    | Data d | Ip d -> Some d
    | Raw_bstr s -> Some (Bytes.of_string s)
    | Raw_tstr s | String s ->
      Ipaddr.of_string s
      |> Result.to_option
      |> Option.map (fun a -> Ipaddr.to_octets a |> Bytes.of_string)
    | _ -> None
  ;;

  let subnet = function
    | Subnet (a, b) -> Some (a, b)
    | Raw_blist [ a; n ]
    | Raw_tlist [ a; n ]
    | Raw_list [ a; n ]
    | List [ a; n ] -> both_opt (ip a, uint n)
    | Raw_tstr s | String s -> (
      let module I = Ipaddr in
      let module IP = Ipaddr.Prefix in
      match IP.of_string s with
      | Ok p -> Some (IP.network p |> I.to_octets |> Bytes.of_string, IP.bits p)
      | Error _ -> None
    )
    | _ -> None
  ;;

  let strmap f = function
    | Raw_blist l | Raw_tlist l | Raw_list l | List l ->
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
    | Raw_blist l | Raw_tlist l | Raw_list l | List l ->
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
    | Raw_blist l | Raw_tlist l | Raw_list l | List l -> (
      try Some (map_some f l) with Vof_return -> None
    )
    | _ -> None
  ;;

  let ndarray f v =
    let map_array sizes a =
      try
        let expected = List.fold_left ( * ) 1 sizes in
        if expected <> Array.length a then raise_notrace Vof_return;
        let next x =
          match f x with
          | Some v -> v
          | None -> raise_notrace Vof_return
        in
        let out = Array.map next a in
        Some (sizes, out)
      with Vof_return -> None
    in
    match v with
    | Ndarray (sizes, vals) -> map_array sizes vals
    | Raw_blist (sizes :: vals)
    | Raw_tlist (sizes :: vals)
    | Raw_list (sizes :: vals)
    | List (sizes :: vals) ->
      let| sl = list int sizes in
      Array.of_list vals |> map_array sl
    | _ -> None
  ;;

  let variant ctx schema f v =
    let enum v =
      let idx = Context.lookup ctx schema.path in
      match v with
      | Raw_bint n | Raw_tint n | Raw_int n | Int n | Uint n ->
        Context.idx_sym idx n
      | _ -> None
    in
    match v with
    | Enum (_, s) -> f s []
    | Variant (_, s, l) -> f s l
    | Raw_bstr s | Raw_tstr s | String s -> f s []
    | Raw_blist (s :: l) | Raw_tlist (s :: l) | Raw_list (s :: l) | List (s :: l)
      ->
      let| name = enum s in
      f name l
    | _ -> enum v
  ;;

  let record ctx schema f = function
    | Record (_, sm) -> f sm
    | Raw_tlist l ->
      let rec pairs sm = function
        | [] -> f sm
        | k :: v :: rest ->
          let| ks = string k in
          pairs (StringMap.add ks v sm) rest
        | _ -> None
      in
      pairs StringMap.empty l
    | Raw_blist l ->
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
    | Raw_list l ->
      let idx = Context.lookup ctx schema.path in
      let rec next pos sm = function
        | [] -> f sm
        | Raw_gap n :: rest -> next (pos + n) sm rest
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
    | Raw_blist [] | Raw_tlist [] | Raw_list [] -> Some []
    | Series l -> (
      try Some (map_some (fun (_, sm) -> f sm) l) with Vof_return -> None
    )
    | Raw_tlist (fields :: rows) -> (
      let build_row names = function
        | Raw_tlist vals | List vals ->
          stringmap_zip StringMap.empty names vals |> f
        | _ -> None
      in
      let| names = list string fields in
      try Some (map_some (build_row names) rows) with Vof_return -> None
    )
    | Raw_blist (fields :: rows) ->
      let| ids = list uint fields in
      let idx = Context.lookup ctx schema.path in
      let names = List.filter_map (Context.idx_sym idx) ids in
      let build_row = function
        | Raw_blist vals -> stringmap_zip StringMap.empty names vals |> f
        | _ -> None
      in
      if List.length names <> List.length ids
      then None
      else if names = []
      then Some []
      else (try Some (map_some build_row rows) with Vof_return -> None)
    | Raw_list (fields :: values) ->
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
          | [] -> raise_notrace Vof_return
        )
      in
      let[@tail_mod_cons] rec read_all () =
        match !remaining with
        | [] -> []
        | _ -> (
          match f (consume StringMap.empty names) with
          | Some v -> v :: read_all ()
          | None -> raise_notrace Vof_return
        )
      in
      if List.length names <> List.length ids
      then None
      else if names = []
      then Some []
      else (try Some (read_all ()) with Vof_return -> None)
    | _ -> None
  ;;
end

let rec equal (a : t) (b : t) : bool =
  match a, b with
  | Float a, Float b -> Float.equal a b
  | Coords (a1, a2), Coords (b1, b2) -> Float.equal a1 b1 && Float.equal a2 b2
  | Enum (_, a), Enum (_, b) -> String.equal a b
  | Variant (_, sa, la), Variant (_, sb, lb) -> (sa, la) = (sb, lb)
  | Text a, Text b -> StringMap.equal String.equal a b
  | Strmap a, Strmap b -> StringMap.equal equal a b
  | Uintmap a, Uintmap b -> IntMap.equal equal a b
  | Record (_, a), Record (_, b) -> StringMap.equal equal a b
  | List a, List b -> List.equal equal a b
  | Ndarray (s1, v1), Ndarray (s2, v2) ->
    let n = Array.length v1 in
    let rec loop i = i >= n || (equal v1.(i) v2.(i) && loop (i + 1)) in
    List.equal Int.equal s1 s2 && n = Array.length v2 && loop 0
  | Series a, Series b ->
    List.equal (fun (_, a) (_, b) -> StringMap.equal equal a b) a b
  | a, b -> a = b
;;

let all_records l =
  let[@tail_mod_cons] rec loop = function
    | [] -> []
    | Record r :: rest -> r :: loop rest
    | _ -> raise_notrace Vof_return
  in
  try Some (loop l) with Vof_return -> None
;;

let rec diff_rec (sa, a) (_, b) =
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
    if is_key k || StringMap.mem k b then acc else StringMap.add k Null acc
  in
  let result =
    List.fold_left collect_keys StringMap.empty sa.keys
    |> StringMap.fold merge_field b
    |> StringMap.fold unset_removed a
  in
  sa, result

and diff_field k va vb acc =
  match va, vb with
  | Record ra, Record rb ->
    let ((s, dm) as d) = diff_rec ra rb in
    if StringMap.for_all (fun f _ -> List.mem f s.keys) dm
    then acc
    else StringMap.add k (Record d) acc
  | List ol, List nl when ol <> [] || nl <> [] -> (
    match all_records ol, all_records nl with
    | Some ol', Some nl' -> (
      match diff_record_list ol' nl' with
      | [] -> acc
      | dl -> StringMap.add k (List (List.map (fun r -> Record r) dl)) acc
    )
    | _ -> if compare va vb = 0 then acc else StringMap.add k vb acc
  )
  | _ -> if compare va vb = 0 then acc else StringMap.add k vb acc

and diff_record_list old_list new_list =
  let schema =
    match old_list @ new_list with
    | (s, _) :: _ -> s
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
      (fun acc ((_, sm) as r) -> KeyMap.add (key_of sm) r acc)
      KeyMap.empty old_list
  in
  let process_new_item (results, consumed) ((_, sm) as nr) =
    let kt = key_of sm in
    match KeyMap.find_opt kt old_map with
    | None -> nr :: results, consumed
    | Some or_ ->
      let consumed = KeyMap.add kt () consumed in
      let ((_, dm) as d) = diff_rec or_ nr in
      if StringMap.for_all (fun f _ -> List.mem f keys) dm
      then results, consumed
      else d :: results, consumed
  in
  let rev_results, consumed =
    List.fold_left process_new_item ([], KeyMap.empty) new_list
  in
  let collect_deleted acc (s, sm) =
    if KeyMap.mem (key_of sm) consumed
    then acc
    else (s, restrict_to_keys sm) :: acc
  in
  List.fold_left collect_deleted rev_results old_list
;;

let diff a b =
  match a, b with
  | Record ra, Record rb -> Some (Record (diff_rec ra rb))
  | _ -> None
;;
