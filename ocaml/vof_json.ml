open Vof
open Vof_enc
open Vof_lib

type t = [
  `Null
  | `Bool of bool
  | `Int of int
  | `Float of float
  | `String of string
  | `Assoc of (string * t) list
  | `List of t list
] [@@ocamlformat "disable"]

let rec to_raw j =
  match j with
  | `Null -> Null
  | `Bool b -> Bool b
  | `Float f -> Float f
  | `Int i -> Raw_tint i
  | `String s -> Raw_tstr s
  | `List l -> Raw_tlist (List.map to_raw l)
  | `Assoc a ->
    Raw_tlist
      (List.fold_left (fun acc (k, v) -> Raw_tstr k :: to_raw v :: acc) [] a)
;;

let js_imax = 9_007_199_254_740_991
let js_imin = -9_007_199_254_740_991

let bytes_to_b64url d =
  Bytes.to_string d
  |> Base64.(encode_string ~pad:false ~alphabet:uri_safe_alphabet)
;;

let of_datetime dt =
  `Int
    ((dt.year * 100000000)
    + (dt.month * 1000000)
    + (dt.day * 10000)
    + (dt.hour * 100)
    + dt.minute
    )
;;

let rec of_vof ctx = function
  | Null -> `Null
  | Bool b -> `Bool b
  | Int i | Uint i | Timestamp i | Raw_tint i ->
    if i >= js_imin && i <= js_imax then `Int i else `String (Int.to_string i)
  | Float f -> `Float f
  | String s | Raw_tstr s -> `String s
  | Data d -> `String (bytes_to_b64url d)
  | Enum (_, s) -> `String s
  | Variant (_, s, l) -> `List (`String s :: List.map (of_vof ctx) l)
  | Decimal d -> `String (Decimal.to_string d)
  | Ratio r -> `String (Ratio.to_string r)
  | Percent (v, d) -> `String (Decimal.to_string (v * 100, d) ^ "%")
  | Date d -> `Int (Date.to_human (d.year, d.month, d.day))
  | Datetime dt -> of_datetime dt
  | Timespan (a, b, c) -> `List [ `Int a; `Int b; `Int c ]
  | Code s
  | Language s
  | Country s
  | Subdivision s
  | Currency s
  | Tax_code s
  | Unit s -> `String s
  | Text sm ->
    `Assoc
      (StringMap.fold (fun k v acc -> (k, `String v) :: acc) sm [] |> List.rev)
  | Amount (d, None) | Quantity (d, None) -> `String (Decimal.to_string d)
  | Amount (d, Some s) | Quantity (d, Some s) ->
    `String (Decimal.to_string d ^ " " ^ s)
  | Tax (d, t, c) ->
    let parts = Some (Decimal.to_string d) :: [ c; Some t ] in
    `String (String.concat " " (List.filter_map Fun.id parts))
  | Ip ip -> (
    match Bytes.unsafe_to_string ip |> Ipaddr.of_octets with
    | Ok addr -> `String (Ipaddr.to_string addr)
    | Error _ -> invalid_arg "Vof_json.of_vof: invalid IP address"
  )
  | Subnet (ip, len) -> (
    match Bytes.unsafe_to_string ip |> Ipaddr.of_octets with
    | Ok addr -> `String (Ipaddr.to_string addr ^ "/" ^ Int.to_string len)
    | Error _ -> invalid_arg "Vof_json.of_vof: invalid IP address"
  )
  | Coords (a, b) -> `List [ `Float a; `Float b ]
  | Strmap sm | Record (_, sm) ->
    `Assoc
      (StringMap.fold (fun k v acc -> (k, of_vof ctx v) :: acc) sm []
      |> List.rev
      )
  | Uintmap im ->
    `Assoc
      (IntMap.fold (fun k v acc -> (Int.to_string k, of_vof ctx v) :: acc) im []
      |> List.rev
      )
  | List l -> `List (List.map (of_vof ctx) l)
  | Ndarray (shape, values) ->
    let sizes = `List (List.map (fun i -> `Int i) shape) in
    `List (sizes :: Array.(map (of_vof ctx) values |> to_list))
  | Series [] -> `List []
  | Series ((schema, _) :: _ as rl) ->
    let fields = series_fields ctx schema rl in
    let header = `List (List.map (fun (k, _) -> `String k) fields) in
    let row (_, sm) = `List (List.map (of_vof ctx) (series_row fields sm)) in
    `List (header :: List.map row rl)
  | _ -> invalid_arg "Vof_json.of_vof: raw types cannot be converted"
;;
