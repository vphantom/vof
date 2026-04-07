module StringMap = Map.Make (String)
module IntMap = Map.Make (Int)

type json = [
  `Null
  | `Bool of bool
  | `Int of int
  | `Float of float
  | `String of string
  | `Assoc of (string * t) list
  | `List of t list
] [@@ocamlformat "disable"]

module Decimal = struct
  type t = int * int

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

type t = [
  `Null
  | `Bool of bool
  | `Int of int
  | `Uint of int
  | `Float of float
  | `String of string
  | `Data of bytes
  | `Decimal of Decimal.t
  | `Ratio of Ratio.t
  | `Percent of Decimal.t
  | `Timestamp of int
  | `Date of Unix.tm
  | `Datetime of Unix.tm
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
] [@@ocamlformat "disable"]

let decimal_str v d = failwith "unimplemented"

let rec to_json = function
  | `Null -> `Null
  | `Bool b -> `Bool b
  | `Int i -> `Int i
  | `Uint i -> `Int i
  | `Float f -> `Float f
  | `String s -> `String s
  | `Data d ->
    `String
      Base64.(
        encode_string ~pad:false ~alphabet:uri_safe_alphabet (Bytes.to_string d)
      )
  | `Decimal d -> `String (Decimal.to_string d)
  | `Ratio r -> `String (Ratio.to_string r)
  | `Percent d -> `String (Decimal.to_string d ^ "%")
  | `Timestamp i -> `Int i
  | `Date tm ->
    `Int (((tm.tm_year + 1900) * 10000) + ((tm.tm_mon + 1) * 100) + tm.tm_mday)
  | `Datetime tm ->
    `Int
      (((tm.tm_year + 1900) * 100000000)
      + ((tm.tm_mon + 1) * 1000000)
      + (tm.tm_mday * 10000)
      + (tm.tm_hour * 100)
      + tm.tm_min
      )
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
    | Ok addr -> `String (Ipadr.to_string addr)
    | Error _ -> failwith "invalid IP address"
  )
  | `Subnet (ip, len) -> (
    match Bytes.unsafe_to_string ip |> Ipaddr.of_octets with
    | Ok addr -> `String (Ipadr.to_string addr ^ "/" ^ Int.to_string len)
    | Error _ -> failwith "invalid IP address"
  )
  | `Coords (a, b) -> `List [ `Float a; `Float b ]
  | `Strmap sm ->
    `Assoc
      (StringMap.fold (fun k v acc -> (k, to_json v) :: acc) sm [] |> List.rev)
  | `Intmap im ->
    `Assoc
      (StringMap.fold (fun k v acc -> (Int.to_string k, to_json v) :: acc) im []
      |> List.rev
      )
  | `List l -> `List (List.map to_json l)
;;

let diff a b =
  ignore (a, b);
  failwith "unimplemented"
;;

type 'k cache = ('k, t) Hashtbl.t

let make_cache () = Hashtbl.create 32

let cached cache key f =
  match Hashtbl.find_opt cache key with
  | Some v -> v
  | None ->
    let v = f () in
    Hashtbl.add cache key v; v
;;
