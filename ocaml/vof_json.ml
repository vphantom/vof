type t = [
  `Null
  | `Bool of bool
  | `Int of int
  | `Float of float
  | `String of string
  | `Assoc of (string * t) list
  | `List of t list
] [@@ocamlformat "disable"]

let rec to_input j =
  match j with
  | `Null -> `Null
  | `Bool b -> `Bool b
  | `Float f -> `Float f
  | `Int i -> `Txt_int i
  | `String s -> `Txt_str s
  | `List l -> `Txt_list (List.map to_input l)
  | `Assoc a ->
    `Txt_list
      (List.fold_left (fun acc (k, v) -> `Txt_str k :: to_input v :: acc) [] a)
;;

let js_imax = 9_007_199_254_740_991
let js_imin = -9_007_199_254_740_991

let bytes_to_b64url d =
  Bytes.to_string d
  |> Base64.encode_string ~pad:false ~alphabet:uri_safe_alphabet
;;

let to_int = function
  | `Int i -> i
  | `String s -> int_of_string_opt s
  | _ -> None
;;

let to_timestamp = to_int
let of_decimal d = `String (to_string d)

let to_decimal = function
  | `String s -> Decimal.of_string s
  | _ -> Error "invalid decimal"
;;

let of_ratio r = `String (Ratio.to_string r)

let to_ratio = function
  | `String s -> Ratio.of_string s
  | _ -> Error "invalid ratio"
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

let rec of_vof = function
  | `Null -> `Null
  | `Bool b -> `Bool b
  | `Int i | `Uint i | `Timestamp i ->
    if i >= js_imin && i <= js_imax then `Int i else `String (Int.to_string i)
  | `Float f -> `Float f
  | `String s -> `String s
  | `Data d -> `String (bytes_to_b64url d)
  | `Enum (_, s) -> `String s
  | `Variant (_, s, l) -> `List (`String s :: List.map of_vof l)
  | `Decimal d -> of_decimal d
  | `Ratio r -> of_ratio r
  | `Percent (v, p) -> `String (Decimal.to_string (v * 100, p) ^ "%")
  | `Date d -> `Int (Vof.Date.to_human d)
  | `Datetime dt -> of_datetime dt
  | `Timespan (a, b, c) -> `List [ `Int a; `Int b; `Int c ]
  | `Code s
  | `Language s
  | `Country s
  | `Subdivision s
  | `Currency s
  | `Tax_code s
  | `Unit s -> `String s
  | `Text sm ->
    `Assoc
      (StringMap.fold (fun k v acc -> (k, `String v) :: acc) sm [] |> List.rev)
  | `Amount (d, None) | `Quantity (d, None) -> `String (Decimal.to_string d)
  | `Amount (d, Some s) | `Quantity (d, Some s) ->
    `String (Decimal.to_string d ^ " " ^ s)
  | `Tax (d, c, t) ->
    let parts = Some (Decimal.to_string d) :: [ c; t ] in
    `String (String.concat " " (List.filter_map Fun.id parts))
  | `Ip ip -> (
    match Bytes.unsafe_to_string ip |> Ipaddr.of_octets with
    | Ok addr -> `String (Ipaddr.to_string addr)
    | Error _ -> failwith "invalid IP address"
  )
  | `Subnet (ip, len) -> (
    match Bytes.unsafe_to_string ip |> Ipaddr.of_octets with
    | Ok addr -> `String (Ipaddr.to_string addr ^ "/" ^ Int.to_string len)
    | Error _ -> failwith "invalid IP address"
  )
  | `Coords (a, b) -> `List [ `Float a; `Float b ]
  | `Strmap sm | `Record (_, sm) ->
    `Assoc
      (StringMap.fold (fun k v acc -> (k, of_vof v) :: acc) sm [] |> List.rev)
  | `Intmap im ->
    `Assoc
      (IntMap.fold (fun k v acc -> (Int.to_string k, of_vof v) :: acc) im []
      |> List.rev
      )
  | `List l -> `List (List.map of_vof l)
  | `Ndarray (il, l) ->
    let sizes = `List (List.map (fun i -> `Int i) il) in
    `List (sizes :: Array.(map of_vof a |> to_list))
  | `Series [] -> `List []
  | `Series (`Record (_, first) :: _ as rl) ->
    let keys = StringMap.fold (fun k _ acc -> k :: acc) first [] |> List.rev in
    let header = `List (List.map (fun k -> `String k) keys) in
    let key_to_json sm k =
      match StringMap.find_opt k sm with
      | Some v -> of_vof v
      | None -> `Null
    in
    let row (`Record (_, sm)) =
      if StringMap.exists (fun k _ -> not (StringMap.mem k first)) sm
      then failwith "series: unexpected extra fields"
      else `List (List.map key_to_json sm keys)
    in
    `List (header :: List.map row rl)
;;
