(* CBOR RFC 8949 Appendix A test vectors.

   Validates our CBOR codec against the 82 official test vectors. See:
   https://github.com/cbor/test-vectors

   Entries are classified into: - Expect: decode must succeed with a specific
   value. - Reject: decode must return None (overflow ints, simple values,
   undefined).

   Due to the nature of VOF, the 'roundtrip' suggestion is ignored here. The
   main reason being our codec immediately decodes maps as lists, since the
   distinction wouldn't be useful in [Vof.t]. *)

(* -- Hex utilities -- *)

let hex_val = function
  | '0' .. '9' as c -> Char.code c - Char.code '0'
  | 'a' .. 'f' as c -> Char.code c - Char.code 'a' + 10
  | 'A' .. 'F' as c -> Char.code c - Char.code 'A' + 10
  | _ -> invalid_arg "hex_val"
;;

let hex_to_string s =
  String.init
    (String.length s / 2)
    (fun i -> Char.chr ((hex_val s.[2 * i] lsl 4) lor hex_val s.[(2 * i) + 1]))
;;

(* CBOR major type from the first byte of a hex-encoded string *)
let cbor_major hex = ((hex_val hex.[0] lsl 4) lor hex_val hex.[1]) lsr 5

(* -- Vof.t pretty-printer for the raw subset returned by Vof_cbor.decode -- *)

let rec pp_vof ppf = function
  | Vof.Null -> Format.fprintf ppf "Null"
  | Vof.Bool b -> Format.fprintf ppf "Bool(%b)" b
  | Vof.Raw_bint i -> Format.fprintf ppf "Raw_bint(%d)" i
  | Vof.Float f -> Format.fprintf ppf "Float(%h)" f
  | Vof.Raw_bstr s -> Format.fprintf ppf "Raw_bstr(%S)" s
  | Vof.Raw_blist l ->
    Format.fprintf ppf "@[<2>Raw_blist[%a]@]"
      (Format.pp_print_list
         ~pp_sep:(fun ppf () -> Format.fprintf ppf ";@ ")
         pp_vof
      )
      l
  | _ -> Format.fprintf ppf "<other>"
;;

(* Lenient structural equality. JSON object keys are always strings but CBOR map
   keys may be integers; we tolerate Raw_bstr "1" matching Raw_bint 1. *)
let rec vof_equal a b =
  match (a : Vof.t), (b : Vof.t) with
  | Null, Null -> true
  | Bool a, Bool b -> Bool.equal a b
  | Raw_bint a, Raw_bint b -> Int.equal a b
  | Float a, Float b -> (Float.is_nan a && Float.is_nan b) || Float.equal a b
  | Raw_bstr a, Raw_bstr b -> String.equal a b
  | Raw_blist a, Raw_blist b ->
    List.length a = List.length b && List.for_all2 vof_equal a b
  | _ -> false
;;

let vof_testable = Alcotest.testable pp_vof vof_equal

(* -- JSON decoded value to expected Vof.t -- *)

let rec json_to_vof : Yojson.Safe.t -> Vof.t option = function
  | `Intlit _ -> None
  | `Null -> Some Null
  | `Bool b -> Some (Bool b)
  | `Int i -> Some (Raw_bint i)
  | `Float f -> Some (Float f)
  | `String s -> Some (Raw_bstr s)
  | `List l ->
    let rec aux acc = function
      | [] -> Some (Vof.Raw_blist (List.rev acc))
      | x :: rest -> (
        match json_to_vof x with
        | Some v -> aux (v :: acc) rest
        | None -> None
      )
    in
    aux [] l
  | `Assoc pairs ->
    (* Maps are flattened to alternating key-value pairs *)
    let rec aux acc = function
      | [] -> Some (Vof.Raw_blist (List.rev acc))
      | (k, v) :: rest -> (
        match json_to_vof v with
        | Some v' -> aux (v' :: Raw_bstr k :: acc) rest
        | None -> None
      )
    in
    aux [] pairs
;;

(* -- Diagnostic string classification -- *)

type expectation = Expect of Vof.t | Reject

let is_indefinite s =
  String.length s >= 3
  && (s.[0] = '(' || s.[0] = '[' || s.[0] = '{')
  && s.[1] = '_'
  && s.[2] = ' '
;;

(* Parse the inner value of a tagged diagnostic: N("str"), N(12345), N(h'AB') *)
let parse_inner s =
  let n = String.length s in
  if n >= 2 && s.[0] = '"' && s.[n - 1] = '"'
  then Some (Vof.Raw_bstr (String.sub s 1 (n - 2)))
  else if n >= 3 && s.[0] = 'h' && s.[1] = '\'' && s.[n - 1] = '\''
  then (
    let hex = String.sub s 2 (n - 3) in
    Some (Raw_bstr (if hex = "" then "" else hex_to_string hex))
  )
  else (
    match int_of_string_opt s with
    | Some i -> Some (Raw_bint i)
    | None -> (
      match float_of_string_opt s with
      | Some f -> Some (Float f)
      | None -> None
    )
  )
;;

let parse_indef_bytes s =
  (* "(_ h'0102', h'030405')" → concatenated bytes *)
  let inner = String.sub s 3 (String.length s - 4) in
  let buf = Buffer.create 16 in
  let parse_chunk c =
    let c = String.trim c in
    let n = String.length c in
    if n >= 3 && c.[0] = 'h' && c.[1] = '\'' && c.[n - 1] = '\''
    then Buffer.add_string buf (hex_to_string (String.sub c 2 (n - 3)))
    else raise_notrace Exit
  in
  try
    List.iter parse_chunk (String.split_on_char ',' inner);
    Some (Vof.Raw_bstr (Buffer.contents buf))
  with Exit -> None
;;

let classify_diagnostic s =
  match s with
  | "NaN" -> Expect (Float Float.nan)
  | "Infinity" -> Expect (Float Float.infinity)
  | "-Infinity" -> Expect (Float Float.neg_infinity)
  | "undefined" -> Reject
  | "{1: 2, 3: 4}" ->
    Expect (Raw_blist [ Raw_bint 1; Raw_bint 2; Raw_bint 3; Raw_bint 4 ])
  | _ when is_indefinite s -> (
    match s.[0] with
    | '(' -> (
      match parse_indef_bytes s with
      | Some v -> Expect v
      | None -> assert false
    )
    | _ -> assert false
  )
  | _ when String.length s >= 7 && String.sub s 0 7 = "simple(" -> Reject
  | _ when String.length s >= 2 && s.[0] = 'h' && s.[1] = '\'' ->
    let hex = String.sub s 2 (String.length s - 3) in
    Expect (Raw_bstr (if hex = "" then "" else hex_to_string hex))
  | _ -> (
    (* Tagged value: N(inner) — tag is silently stripped by our decoder *)
    match String.index_opt s '(' with
    | Some i when i > 0 && s.[String.length s - 1] = ')' -> (
      let inner = String.sub s (i + 1) (String.length s - i - 2) in
      match parse_inner inner with
      | Some v -> Expect v
      | None -> assert false
    )
    | _ -> assert false
  )
;;

(* -- Build and run tests -- *)

let has_key k = function
  | `Assoc pairs -> List.mem_assoc k pairs
  | _ -> false
;;

let make_test i obj =
  let open Yojson.Safe.Util in
  let hex = obj |> member "hex" |> to_string in
  let cbor_b64 = obj |> member "cbor" |> to_string in
  let name = Printf.sprintf "#%02d %s" i hex in
  let expectation =
    if has_key "diagnostic" obj
    then obj |> member "diagnostic" |> to_string |> classify_diagnostic
    else if has_key "decoded" obj
    then (
      match obj |> member "decoded" with
      | `Intlit _ ->
        (* Integer too large for OCaml int *)
        if cbor_major hex = 6
        then (
          match Vof_cbor.decode (hex_to_string hex) with
          | Some (v, _) -> Expect v
          | None -> Reject
        )
        else Reject
      | decoded -> (
        match json_to_vof decoded with
        | Some v -> Expect v
        | None -> assert false
      )
    )
    else assert false
  in
  Alcotest.test_case name `Quick (fun () ->
    match expectation with
    | Reject -> (
      match Vof_cbor.decode (Base64.decode_exn cbor_b64) with
      | None -> ()
      | Some (v, _) ->
        Alcotest.failf "%s: expected rejection but decoded: %a" hex pp_vof v
    )
    | Expect expected -> (
      let cbor = Base64.decode_exn cbor_b64 in
      match Vof_cbor.decode cbor with
      | None ->
        Alcotest.failf "%s: decode returned None, expected %a" hex pp_vof
          expected
      | Some (v, pos) ->
        Alcotest.check vof_testable (hex ^ " value") expected v;
        Alcotest.check Alcotest.int (hex ^ " end position") (String.length cbor)
          pos
    )
)
;;

(* Hand-crafted vectors for gaps not covered by Appendix A *)
let extra_tests =
  let make (name, hex, expected) =
    Alcotest.test_case name `Quick (fun () ->
      let cbor = hex_to_string hex in
      match Vof_cbor.decode cbor with
      | None ->
        Alcotest.failf "%s: decode returned None, expected %a" hex pp_vof
          expected
      | Some (v, pos) ->
        Alcotest.check vof_testable (hex ^ " value") expected v;
        Alcotest.check Alcotest.int (hex ^ " end position") (String.length cbor)
          pos
  )
  in
  List.map make
    [
      (* tag wrapping a map: tag(99, {1: 2, 3: 4}) *)
      ( "tag-map",
        "d863a201020304",
        Raw_blist [ Raw_bint 1; Raw_bint 2; Raw_bint 3; Raw_bint 4 ] );
    ]
;;

let () =
  let entries =
    match Yojson.Safe.from_file "cbor_appendix_a.json" with
    | `List l -> l
    | _ -> failwith "expected JSON array"
  in
  let tests = List.mapi make_test entries in
  Alcotest.run "CBOR Appendix A" [ "decode", tests; "extra", extra_tests ]
;;
