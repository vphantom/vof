(** TODO:

    - [make_query]
    - [build_msg], [msg_add], [msg_record]

    /TODO *)

module Decimal = Vof_lib.Decimal
module Ratio = Vof_lib.Ratio
module Date = Vof_lib.Date
module Datetime = Vof_lib.Datetime
module Timestamp = Vof_lib.Timestamp

(* === Core === *)

let test_detect_format () =
  (* Values from SPECIFICATION.md "Decoding and Compression" table *)
  let cases =
    [
      '\x1F', Some Vof.Gzip;
      '\x28', Some Vof.Zstd;
      '\x5B', Some Vof.Json;
      (* '[' *)
      '\x6E', Some Vof.Json;
      (* 'n' for null *)
      '\x7B', Some Vof.Json;
      (* '{' *)
      '\x80', Some Vof.Cbor;
      '\x9F', Some Vof.Cbor;
      '\xA0', Some Vof.Cbor;
      '\xBF', Some Vof.Cbor;
      '\xD8', Some Vof.Cbor;
      '\xD9', Some Vof.Cbor;
      '\xDA', Some Vof.Cbor;
      '\xDB', Some Vof.Cbor;
      '\xF6', Some Vof.Cbor;
      '\xE8', Some Vof.Binary;
      '\xF3', Some Vof.Binary;
      '\xFA', Some Vof.Binary;
      '\xFD', Some Vof.Binary;
      (* Unrecognized bytes *)
      '\x00', None;
      '\x20', None;
      '\x41', None;
      '\xFF', None;
    ]
  in
  List.iter
    (fun (c, expected) ->
      let got = Vof.detect_format c in
      if got <> expected
      then
        Alcotest.failf "detect_format 0x%02X: expected %s got %s" (Char.code c)
          ( match expected with
          | Some Vof.Gzip -> "Gzip"
          | Some Vof.Zstd -> "Zstd"
          | Some Vof.Json -> "Json"
          | Some Vof.Cbor -> "Cbor"
          | Some Vof.Binary -> "Binary"
          | None -> "None"
          )
          ( match got with
          | Some Vof.Gzip -> "Gzip"
          | Some Vof.Zstd -> "Zstd"
          | Some Vof.Json -> "Json"
          | Some Vof.Cbor -> "Cbor"
          | Some Vof.Binary -> "Binary"
          | None -> "None"
          )
    )
    cases
;;

(* === Warnings === *)

let test_pp_warn () =
  let open Vof in
  let cases =
    [
      `Vof_bad_field ("order", "name"), [ "order"; "name" ];
      `Vof_fetch_failed ("order", "not found"), [ "order"; "not found" ];
      `Vof_invalid_param ("max~", "abc"), [ "max~"; "abc" ];
      `Vof_unknown_param "foo~", [ "foo~" ];
    ]
  in
  let has_sub s sub =
    let slen = String.length s
    and sublen = String.length sub in
    if sublen > slen
    then false
    else (
      let rec check i =
        if i > slen - sublen
        then false
        else if String.sub s i sublen = sub
        then true
        else check (i + 1)
      in
      check 0
    )
  in
  List.iter
    (fun (w, expected_subs) ->
      let s = pp_warn w in
      if String.length s = 0 then Alcotest.fail "pp_warn returned empty string";
      List.iter
        (fun sub ->
          if not (has_sub s sub)
          then Alcotest.failf "pp_warn: expected %S in %S" sub s
        )
        expected_subs
    )
    cases
;;

(* === Context === *)

let test_context_make () =
  (* Basic creation succeeds *)
  let ctx = Vof.Context.make ~update:true "com.test" in
  (* Can declare a schema immediately *)
  let _s = Vof.Context.schema ctx "order" in
  ()
;;

let test_context_schema_basic () =
  let ctx = Vof.Context.make ~update:true "com.test" in
  let _ =
    Vof.Context.schema ctx
      ~fields:[ "orders", [ List_of "com.test.order" ] ]
      "$msg"
  in
  let order_schema =
    Vof.Context.schema ctx
      ~fields:[ "id", [ Key ]; "modified_at", [ Req ] ]
      "order"
  in
  Alcotest.(check string) "path" "com.test.order" order_schema.path;
  Alcotest.(check (list string)) "keys" [ "id" ] order_schema.keys;
  Alcotest.(check (list string)) "required" [ "modified_at" ] order_schema.reqs
;;

let test_context_schema_retrieval () =
  (* Second call with same path returns same schema *)
  let ctx = Vof.Context.make ~update:true "com.test" in
  let s1 = Vof.Context.schema ctx ~fields:[ "id", [ Key ] ] "order" in
  let s2 = Vof.Context.schema ctx "order" in
  Alcotest.(check string) "same path" s1.path s2.path;
  Alcotest.(check (list string)) "same keys" s1.keys s2.keys
;;

let test_context_schema_nested () =
  let ctx = Vof.Context.make ~update:true "com.test" in
  let s = Vof.Context.schema ctx ~fields:[ "i", [ Key ] ] "order.line" in
  Alcotest.(check string) "nested path" "com.test.order.line" s.path
;;

let test_context_lookup_id () =
  let ctx = Vof.Context.make ~update:true "com.test" in
  let _s = Vof.Context.schema ctx "order" in
  (* First symbol gets id 0, second gets 1, etc. *)
  let id0 = Vof.Context.lookup_id ctx "com.test.order" "id" in
  let id1 = Vof.Context.lookup_id ctx "com.test.order" "modified_at" in
  let id2 = Vof.Context.lookup_id ctx "com.test.order" "customer" in
  Alcotest.(check int) "first symbol" 0 id0;
  Alcotest.(check int) "second symbol" 1 id1;
  Alcotest.(check int) "third symbol" 2 id2;
  (* Repeated lookup returns same id *)
  let id0' = Vof.Context.lookup_id ctx "com.test.order" "id" in
  Alcotest.(check int) "same id on repeat" 0 id0'
;;

let test_context_idx_sym () =
  let ctx = Vof.Context.make ~update:true "com.test" in
  let _s = Vof.Context.schema ctx "order" in
  let idx = Vof.Context.idx_lookup ctx "com.test.order" in
  let _id = Vof.Context.idx_id ctx idx "alpha" in
  let _id = Vof.Context.idx_id ctx idx "beta" in
  Alcotest.(check (option string))
    "sym 0" (Some "alpha")
    (Vof.Context.idx_sym idx 0);
  Alcotest.(check (option string))
    "sym 1" (Some "beta")
    (Vof.Context.idx_sym idx 1);
  Alcotest.(check (option string)) "sym 99" None (Vof.Context.idx_sym idx 99)
;;

let tmp_symtable () =
  let path = Filename.temp_file "vof_test_symtable" ".txt" in
  at_exit (fun () -> try Sys.remove path with _ -> ());
  path
;;

let test_context_no_update_rejects_unknown () =
  let path = tmp_symtable () in
  (* Set up a namespace with one known field *)
  let ctx = Vof.Context.make ~update:true "com.test" in
  Vof.Context.load ctx path;
  let _ = Vof.Context.schema ctx ~fields:[ "id", [ Key ] ] "order" in
  let _ = Vof.Context.lookup_id ctx "com.test.order" "id" in
  Vof.Context.save ctx;
  (* Now load into a non-update context *)
  let ctx2 = Vof.Context.make ~update:false "com.test" in
  Vof.Context.load ctx2 path;
  let raised =
    match Vof.Context.lookup_id ctx2 "com.test.order" "new_field" with
    | _ -> false
    | exception Invalid_argument _ -> true
  in
  if not raised
  then
    Alcotest.fail
      "expected Invalid_argument for unknown symbol in no-update mode"
;;

let test_context_save_load () =
  let path = tmp_symtable () in
  (* Create, populate, save *)
  let ctx = Vof.Context.make ~update:true "com.test" in
  Vof.Context.load ctx path;
  let _ =
    Vof.Context.schema ctx
      ~fields:[ "orders", [ List_of "com.test.order" ] ]
      "$msg"
  in
  let _s =
    Vof.Context.schema ctx
      ~fields:[ "id", [ Key ]; "modified_at", [ Req ] ]
      "order"
  in
  let _ = Vof.Context.lookup_id ctx "com.test.order" "id" in
  let _ = Vof.Context.lookup_id ctx "com.test.order" "modified_at" in
  let _ = Vof.Context.lookup_id ctx "com.test.order" "customer" in
  let _s = Vof.Context.schema ctx ~fields:[ "i", [ Key ] ] "order.line" in
  let _ = Vof.Context.lookup_id ctx "com.test.order.line" "i" in
  let _ = Vof.Context.lookup_id ctx "com.test.order.line" "product" in
  Vof.Context.save ctx;
  (* Load into a fresh context and verify *)
  let ctx2 = Vof.Context.make ~update:false "com.test" in
  Vof.Context.load ctx2 path;
  let id0 = Vof.Context.lookup_id ctx2 "com.test.order" "id" in
  let id1 = Vof.Context.lookup_id ctx2 "com.test.order" "modified_at" in
  let id2 = Vof.Context.lookup_id ctx2 "com.test.order" "customer" in
  Alcotest.(check int) "loaded id" 0 id0;
  Alcotest.(check int) "loaded modified_at" 1 id1;
  Alcotest.(check int) "loaded customer" 2 id2;
  let li0 = Vof.Context.lookup_id ctx2 "com.test.order.line" "i" in
  let li1 = Vof.Context.lookup_id ctx2 "com.test.order.line" "product" in
  Alcotest.(check int) "loaded line i" 0 li0;
  Alcotest.(check int) "loaded line product" 1 li1
;;

let test_context_save_load_qualifiers () =
  let path = tmp_symtable () in
  (* Verify qualifiers (key, req) survive save/load *)
  let ctx = Vof.Context.make ~update:true "com.test" in
  Vof.Context.load ctx path;
  let _s =
    Vof.Context.schema ctx
      ~fields:[ "id", [ Key ]; "modified_at", [ Req ]; "data", [] ]
      "thing"
  in
  let _ = Vof.Context.lookup_id ctx "com.test.thing" "id" in
  let _ = Vof.Context.lookup_id ctx "com.test.thing" "modified_at" in
  let _ = Vof.Context.lookup_id ctx "com.test.thing" "data" in
  Vof.Context.save ctx;
  (* Read the file and check qualifier strings are present *)
  let contents =
    let ic = open_in path in
    let s = In_channel.input_all ic in
    close_in ic; s
  in
  let has sub =
    String.length contents > 0
    &&
    let re = sub in
    let rec check i =
      if i > String.length contents - String.length re
      then false
      else if String.sub contents i (String.length re) = re
      then true
      else check (i + 1)
    in
    check 0
  in
  if not (has "\tid key")
  then
    Alcotest.failf "expected 'id key' qualifier in saved file, got:\n%s"
      contents;
  if not (has "\tmodified_at req")
  then
    Alcotest.failf
      "expected 'modified_at req' qualifier in saved file, got:\n%s" contents;
  (* 'data' should have no qualifier *)
  if has "\tdata key" || has "\tdata req"
  then
    Alcotest.failf "unexpected qualifier on 'data' in saved file, got:\n%s"
      contents
;;

let test_context_load_nonexistent_update () =
  (* In update mode, loading a non-existent file should not fail *)
  let ctx = Vof.Context.make ~update:true "com.test" in
  let path =
    "/tmp/vof_test_nonexistent_" ^ string_of_int (Random.bits ()) ^ ".txt"
  in
  (try Sys.remove path with _ -> ());
  (* Should not raise *)
  Vof.Context.load ctx path;
  (* Context should still be usable *)
  let _s = Vof.Context.schema ctx "foo" in
  let _ = Vof.Context.lookup_id ctx "com.test.foo" "bar" in
  ()
;;

let test_context_schema_redefine_no_update () =
  let path = tmp_symtable () in
  let fields =
    [
      "id", [ Vof.Key ];
      "updated_at", [ Req ];
      "items", [ List_of "com.test.gadget.item" ];
      "label", [ Other ("indexed", None) ];
      "meta", [ Other ("format", Some "json") ];
      "value", [];
    ]
  in
  (* Build schema in update mode, register symbols, save *)
  let ctx = Vof.Context.make ~update:true "com.test" in
  Vof.Context.load ctx path;
  let _ = Vof.Context.schema ctx ~fields "gadget" in
  List.iter
    (fun (s, _) -> ignore (Vof.Context.lookup_id ctx "com.test.gadget" s))
    fields;
  Vof.Context.save ctx;
  (* Reload in non-update mode *)
  let ctx2 = Vof.Context.make ~update:false "com.test" in
  Vof.Context.load ctx2 path;
  (* Identical re-declaration succeeds *)
  let s = Vof.Context.schema ctx2 ~fields "gadget" in
  Alcotest.(check string) "path" "com.test.gadget" s.path;
  Alcotest.(check (list string)) "keys" [ "id" ] s.keys;
  Alcotest.(check (list string)) "reqs" [ "updated_at" ] s.reqs;
  (* Incompatible: promote plain field "value" to Key *)
  let raised =
    match Vof.Context.schema ctx2 ~fields:[ "value", [ Key ] ] "gadget" with
    | _ -> false
    | exception Invalid_argument _ -> true
  in
  if not raised
  then
    Alcotest.fail
      "expected Invalid_argument for incompatible qualifier in non-update mode"
;;

let test_context_schema_redefine_update () =
  let path = tmp_symtable () in
  let fields =
    [
      "id", [ Vof.Key ];
      "updated_at", [ Req ];
      "items", [ List_of "com.test.gizmo.item" ];
      "label", [ Other ("indexed", None) ];
      "meta", [ Other ("format", Some "json") ];
      "value", [];
    ]
  in
  let ctx = Vof.Context.make ~update:true "com.test" in
  Vof.Context.load ctx path;
  let _ = Vof.Context.schema ctx ~fields "gizmo" in
  List.iter
    (fun (s, _) -> ignore (Vof.Context.lookup_id ctx "com.test.gizmo" s))
    fields;
  Vof.Context.save ctx;
  let read_file p =
    let ic = open_in p in
    let s = In_channel.input_all ic in
    close_in ic; s
  in
  let saved1 = read_file path in
  (* Identical re-declaration: no modification *)
  let s1 = Vof.Context.schema ctx ~fields "gizmo" in
  Alcotest.(check string) "path unchanged" "com.test.gizmo" s1.path;
  Alcotest.(check (list string)) "keys unchanged" [ "id" ] s1.keys;
  Alcotest.(check (list string)) "reqs unchanged" [ "updated_at" ] s1.reqs;
  Vof.Context.save ctx;
  let saved2 = read_file path in
  Alcotest.(check string)
    "file unchanged after identical re-declaration" saved1 saved2;
  (* Update: promote "value" to Req and add new field "extra" *)
  let s2 =
    Vof.Context.schema ctx
      ~fields:
        [
          "id", [ Key ];
          "updated_at", [ Req ];
          "items", [ List_of "com.test.gizmo.item" ];
          "label", [ Other ("indexed", None) ];
          "meta", [ Other ("format", Some "json") ];
          "value", [ Req ];
          "extra", [];
        ]
      "gizmo"
  in
  if not (List.mem "updated_at" s2.reqs)
  then Alcotest.fail "reqs should still contain updated_at";
  if not (List.mem "value" s2.reqs)
  then Alcotest.fail "reqs should now contain value";
  Vof.Context.save ctx;
  let saved3 = read_file path in
  if saved3 = saved2
  then Alcotest.fail "expected file to change after schema update"
;;

let pow10 n =
  let rec go acc = function
    | 0 -> acc
    | k -> go (acc * 10) (k - 1)
  in
  go 1 n
;;

(* Generator for (value, dec) pairs with dec in 0..9 and value small enough that
   pack won't overflow (value * 10000 must fit in an int). *)
let gen_dec_pair =
  QCheck2.Gen.(
    let* dec = int_range 0 9 in
    let* value = int_range (-100_000_000) 100_000_000 in
    return (value, dec)
  )
;;

(* --- Decimal.optimize --- *)

let test_decimal_optimize_idempotent =
  QCheck_alcotest.to_alcotest
    (QCheck2.Test.make ~name:"optimize is idempotent" gen_dec_pair (fun d ->
       let o = Decimal.optimize d in
       Decimal.optimize o = o
   )
    )
;;

let test_decimal_optimize_preserves_value =
  QCheck_alcotest.to_alcotest
    (QCheck2.Test.make ~name:"optimize preserves mathematical value"
       gen_dec_pair (fun (value, dec) ->
       let v', d' = Decimal.optimize (value, dec) in
       v' * pow10 (dec - d') = value
   )
    )
;;

let test_decimal_optimize_no_trailing_zeros =
  QCheck_alcotest.to_alcotest
    (QCheck2.Test.make ~name:"optimize removes trailing zeros" gen_dec_pair
       (fun d ->
       let v, dec = Decimal.optimize d in
       dec = 0 || v = 0 || v mod 10 <> 0
   )
    )
;;

let test_decimal_optimize_known () =
  let cases =
    [
      (0, 0), (0, 0);
      (0, 5), (0, 0);
      (100, 2), (1, 0);
      (1230, 3), (123, 2);
      (5, 1), (5, 1);
      (-2500, 4), (-25, 2);
    ]
  in
  List.iter
    (fun (input, expected) ->
      let got = Decimal.optimize input in
      if got <> expected
      then
        Alcotest.failf "optimize (%d,%d): expected (%d,%d) got (%d,%d)"
          (fst input) (snd input) (fst expected) (snd expected) (fst got)
          (snd got)
    )
    cases
;;

(* --- Decimal.pack / unpack --- *)

let test_decimal_pack_unpack_roundtrip =
  QCheck_alcotest.to_alcotest
    (QCheck2.Test.make ~name:"pack/unpack roundtrip" gen_dec_pair (fun d ->
       Decimal.unpack (Decimal.pack d) = Decimal.optimize d
   )
    )
;;

let test_decimal_pack_known () =
  (* From BINARY.md: 2.123 = (2123,3) → ((2123*10) lsl 2) lor 2 = 84922 *)
  let cases =
    [
      (2123, 3), 84922;
      (42, 0), 42 lsl 2;
      (1, 0), 1 lsl 2;
      (0, 0), 0;
      (* tag 1 = 2 decimal places *)
      (150, 2), (150 lsl 2) lor 1;
      (* dec=1 after optimize → stays 1, packed as value*10 with tag 1 *)
      (5, 1), ((5 * 10) lsl 2) lor 1;
      (* tag 2 = 4 decimal places *)
      (12345, 4), (12345 lsl 2) lor 2;
      (* tag 3 = 9 decimal places *)
      (123456789, 9), (123456789 lsl 2) lor 3;
    ]
  in
  List.iter
    (fun (input, expected) ->
      let got = Decimal.pack input in
      if got <> expected
      then
        Alcotest.failf "pack (%d,%d): expected %d got %d" (fst input)
          (snd input) expected got
    )
    cases
;;

let test_decimal_unpack_known () =
  let cases =
    [
      84922, (2123, 3);
      0, (0, 0);
      42 lsl 2, (42, 0);
      (150 lsl 2) lor 1, (15, 1);
      (* 150 with 2 dec → optimize → (15,1) *)
      (12345 lsl 2) lor 2, (12345, 4);
      (123456789 lsl 2) lor 3, (123456789, 9);
    ]
  in
  List.iter
    (fun (input, expected) ->
      let got = Decimal.unpack input in
      if got <> expected
      then
        Alcotest.failf "unpack %d: expected (%d,%d) got (%d,%d)" input
          (fst expected) (snd expected) (fst got) (snd got)
    )
    cases
;;

(* --- Decimal.to_n / of_n --- *)

let test_decimal_to_n_of_n_roundtrip =
  QCheck_alcotest.to_alcotest
    (QCheck2.Test.make ~name:"to_n/of_n roundtrip" gen_dec_pair (fun d ->
       let opt = Decimal.optimize d in
       if fst opt = 0 && snd opt = 0
       then Decimal.of_n (Decimal.to_n d) = Some (0, 0)
       else Decimal.of_n (Decimal.to_n d) = Some opt
   )
    )
;;

let test_decimal_to_n_known () =
  (* From SPECIFICATION.md: 2.150 = (2150,3) → optimize → (215,2) → 2152 *)
  let cases =
    [
      (2150, 3), 2152;
      (215, 2), 2152;
      (0, 0), 0;
      (42, 0), 420;
      (15, 1), 151;
      (-15, 1), -151;
      (-215, 2), -2152;
    ]
  in
  List.iter
    (fun (input, expected) ->
      let got = Decimal.to_n input in
      if got <> expected
      then
        Alcotest.failf "to_n (%d,%d): expected %d got %d" (fst input)
          (snd input) expected got
    )
    cases
;;

let test_decimal_of_n_known () =
  let valid_cases =
    [
      0, Some (0, 0);
      2152, Some (215, 2);
      -2152, Some (-215, 2);
      420, Some (42, 0);
      151, Some (15, 1);
      -151, Some (-15, 1);
      10, Some (1, 0);
    ]
  in
  List.iter
    (fun (input, expected) ->
      let got = Decimal.of_n input in
      if got <> expected
      then
        Alcotest.failf "of_n %d: expected %s got %s" input
          ( match expected with
          | Some (v, d) -> Printf.sprintf "Some (%d,%d)" v d
          | None -> "None"
          )
          ( match got with
          | Some (v, d) -> Printf.sprintf "Some (%d,%d)" v d
          | None -> "None"
          )
    )
    valid_cases;
  (* Values 1..9 are invalid (absolute value < 10 but not 0) *)
  List.iter
    (fun n ->
      if Decimal.of_n n <> None then Alcotest.failf "of_n %d: expected None" n
    )
    [ 1; 2; 3; 4; 5; 6; 7; 8; 9; -1; -2; -9 ]
;;

(* --- Decimal.of_string / to_string --- *)

let test_decimal_of_string_to_string_roundtrip =
  QCheck_alcotest.to_alcotest
    (QCheck2.Test.make ~name:"of_string(to_string d) = Some (optimize d)"
       gen_dec_pair (fun d ->
       let opt = Decimal.optimize d in
       let s = Decimal.to_string opt in
       Decimal.of_string s = Some opt
   )
    )
;;

let test_decimal_of_string_known () =
  let cases =
    [
      "2.123", Some (2123, 3);
      "2.150", Some (215, 2);
      "-1.5", Some (-15, 1);
      "100", Some (100, 0);
      "0", Some (0, 0);
      "0.0", Some (0, 0);
      "-0.05", Some (-5, 2);
      "1000.00", Some (1000, 0);
      "3", Some (3, 0);
      "-7", Some (-7, 0);
      "0.001", Some (1, 3);
      "", None;
      "abc", None;
      ".", None;
    ]
  in
  List.iter
    (fun (input, expected) ->
      let got = Decimal.of_string input in
      if got <> expected
      then
        Alcotest.failf "of_string %S: expected %s got %s" input
          ( match expected with
          | Some (v, d) -> Printf.sprintf "Some (%d,%d)" v d
          | None -> "None"
          )
          ( match got with
          | Some (v, d) -> Printf.sprintf "Some (%d,%d)" v d
          | None -> "None"
          )
    )
    cases
;;

let test_decimal_to_string_known () =
  let cases =
    [
      (2123, 3), "2.123";
      (215, 2), "2.15";
      (100, 0), "100";
      (-15, 1), "-1.5";
      (0, 0), "0";
      (-5, 2), "-0.05";
      (1, 3), "0.001";
      (42, 0), "42";
      (-1000, 0), "-1000";
      (10, 1), "1";
      (3050, 4), "0.305";
    ]
  in
  List.iter
    (fun (input, expected) ->
      let got = Decimal.to_string input in
      if got <> expected
      then
        Alcotest.failf "to_string (%d,%d): expected %S got %S" (fst input)
          (snd input) expected got
    )
    cases
;;

let test_decimal_of_string_shift () =
  (* shift parameter multiplies by 10^shift *)
  let cases =
    [
      ("50", 2), Some (5, 1); ("1.5", 1), Some (15, 2); ("100", 0), Some (100, 0);
    ]
  in
  List.iter
    (fun ((s, shift), expected) ->
      let got = Decimal.of_string ~shift s in
      if got <> expected
      then
        Alcotest.failf "of_string ~shift:%d %S: expected %s got %s" shift s
          ( match expected with
          | Some (v, d) -> Printf.sprintf "Some (%d,%d)" v d
          | None -> "None"
          )
          ( match got with
          | Some (v, d) -> Printf.sprintf "Some (%d,%d)" v d
          | None -> "None"
          )
    )
    cases
;;

(* --- Ratio.of_string --- *)

let test_ratio_of_string_known () =
  let valid =
    [
      "1/2", Some (1, 2);
      "0/1", Some (0, 1);
      "-3/4", Some (-3, 4);
      "100/7", Some (100, 7);
      "0/100", Some (0, 100);
      "-1/1", Some (-1, 1);
      "999999/1000000", Some (999999, 1000000);
    ]
  in
  List.iter
    (fun (input, expected) ->
      let got = Ratio.of_string input in
      if got <> expected
      then
        Alcotest.failf "Ratio.of_string %S: expected %s got %s" input
          ( match expected with
          | Some (n, d) -> Printf.sprintf "Some (%d,%d)" n d
          | None -> "None"
          )
          ( match got with
          | Some (n, d) -> Printf.sprintf "Some (%d,%d)" n d
          | None -> "None"
          )
    )
    valid
;;

let test_ratio_of_string_invalid () =
  let cases =
    [
      "";
      "1";
      "/2";
      "1/";
      "abc";
      "1/0";
      "1/-1";
      "1/-2";
      "1/2/3";
      "a/b";
      "1.5/2";
      "1/2.5";
      " 1/2";
      "1 /2";
    ]
  in
  List.iter
    (fun input ->
      match Ratio.of_string input with
      | None -> ()
      | Some (n, d) ->
        Alcotest.failf "Ratio.of_string %S: expected None got Some (%d,%d)"
          input n d
    )
    cases
;;

(* --- Ratio.to_string --- *)

let test_ratio_to_string_known () =
  let cases =
    [
      (1, 2), "1/2";
      (0, 1), "0/1";
      (-3, 4), "-3/4";
      (100, 7), "100/7";
      (-1, 1), "-1/1";
    ]
  in
  List.iter
    (fun (input, expected) ->
      let got = Ratio.to_string input in
      if got <> expected
      then
        Alcotest.failf "Ratio.to_string (%d,%d): expected %S got %S" (fst input)
          (snd input) expected got
    )
    cases
;;

(* --- Ratio roundtrip --- *)

let gen_ratio =
  QCheck2.Gen.(
    let* num = int_range (-100_000) 100_000 in
    let* den = int_range 1 100_000 in
    return (num, den)
  )
;;

let test_ratio_roundtrip =
  QCheck_alcotest.to_alcotest
    (QCheck2.Test.make ~name:"of_string(to_string r) = Some r" gen_ratio
       (fun r -> Ratio.of_string (Ratio.to_string r) = Some r
   )
    )
;;

(* --- Float16 --- *)

let test_float16_conv () =
  for bits = 0 to 65535 do
    let f = Vof_float16.float_of_bits bits in
    match Float.is_nan f with
    | true -> (
      let sign = (bits lsr 15) land 1 in
      let expected = (sign lsl 15) lor 0x7E00 in
      match Vof_float16.bits_of_float_opt f with
      | Some result ->
        if result <> expected
        then
          Alcotest.failf "NaN bits=0x%04X: expected 0x%04X got 0x%04X" bits
            expected result
      | None ->
        Alcotest.failf "NaN bits=0x%04X: bits_of_float_opt returned None" bits
    )
    | false -> (
      match Vof_float16.bits_of_float_opt f with
      | Some result ->
        if result <> bits
        then
          Alcotest.failf "bits=0x%04X float=%h: roundtrip got 0x%04X" bits f
            result
      | None ->
        Alcotest.failf "bits=0x%04X float=%h: bits_of_float_opt returned None"
          bits f
    )
  done
;;

let test_float16_rejects () =
  let should_reject =
    [
      65536.0;
      65504.0 +. 1.0;
      0.000001;
      1.0000001;
      1.00048828125;
      3.14159;
      Float.min_float;
      5e-324;
      (* float64 subnormal: exp64=0, mant64<>0 *)
    ]
  in
  List.iter
    (fun f ->
      match Vof_float16.bits_of_float_opt f with
      | None -> ()
      | Some bits -> Alcotest.failf "%h should not encode, got 0x%04X" f bits
    )
    should_reject
;;

let test_float16_known_values () =
  (* float_of_bits: known bit patterns to expected float64 values *)
  let decode_cases =
    [
      0x0000, 0.0;
      0x3C00, 1.0;
      0xBC00, -1.0;
      0x4000, 2.0;
      0x3800, 0.5;
      0x3400, 0.25;
      0x7BFF, 65504.0;
      0x7C00, infinity;
      0xFC00, neg_infinity;
      0x0001, ldexp 1.0 (-24);
      0x0400, ldexp 1.0 (-14);
      0x3555, 0.333251953125;
    ]
  in
  List.iter
    (fun (bits, expected) ->
      let got = Vof_float16.float_of_bits bits in
      if got <> expected
      then
        Alcotest.failf "decode: bits=0x%04X expected=%h got=%h" bits expected
          got
    )
    decode_cases;
  (* Negative zero: bit comparison since -0.0 = 0.0 in OCaml *)
  let nz = Vof_float16.float_of_bits 0x8000 in
  if Int64.bits_of_float nz <> Int64.bits_of_float (-0.0)
  then Alcotest.fail "0x8000 should decode to -0.0";
  (* NaN: just check it is NaN *)
  if not (Float.is_nan (Vof_float16.float_of_bits 0x7E00))
  then Alcotest.fail "0x7E00 should decode to NaN";
  if not (Float.is_nan (Vof_float16.float_of_bits 0xFE00))
  then Alcotest.fail "0xFE00 should decode to NaN";
  (* bits_of_float_opt: known float64 values to expected bit patterns *)
  let encode_cases =
    [
      0.0, Some 0x0000;
      -0.0, Some 0x8000;
      1.0, Some 0x3C00;
      -1.0, Some 0xBC00;
      0.5, Some 0x3800;
      65504.0, Some 0x7BFF;
      infinity, Some 0x7C00;
      neg_infinity, Some 0xFC00;
      ldexp 1.0 (-24), Some 0x0001;
      ldexp 1.0 (-14), Some 0x0400;
    ]
  in
  List.iter
    (fun (f, expected) ->
      let got = Vof_float16.bits_of_float_opt f in
      if got <> expected
      then
        Alcotest.failf "encode: float=%h expected=%s got=%s" f
          ( match expected with
          | Some v -> Printf.sprintf "0x%04X" v
          | None -> "None"
          )
          ( match got with
          | Some v -> Printf.sprintf "0x%04X" v
          | None -> "None"
          )
    )
    encode_cases
;;

let test_float16_bits_of_float () =
  (* Succeeds on representable values *)
  let check f expected =
    let got = Vof_float16.bits_of_float f in
    if got <> expected
    then
      Alcotest.failf "bits_of_float %h: expected 0x%04X got 0x%04X" f expected
        got
  in
  check 1.0 0x3C00;
  check 0.0 0x0000;
  check (-0.0) 0x8000;
  check 65504.0 0x7BFF;
  check infinity 0x7C00;
  (* Raises on non-representable values *)
  let should_raise f =
    match Vof_float16.bits_of_float f with
    | _ -> Alcotest.failf "bits_of_float %h should have raised" f
    | exception _ -> ()
  in
  should_raise 3.14159;
  should_raise 65536.0;
  should_raise Float.min_float
;;

(* --- Date.pack / unpack --- *)

let gen_date =
  QCheck2.Gen.(
    let* y = int_range 1900 9999 in
    let* m = int_range 1 12 in
    let* d = int_range 1 31 in
    return (y, m, d)
  )
;;

let test_date_pack_unpack_roundtrip =
  QCheck_alcotest.to_alcotest
    (QCheck2.Test.make ~name:"pack/unpack roundtrip" gen_date (fun date ->
       Date.unpack (Date.pack date) = Some date
   )
    )
;;

let test_date_pack_known () =
  (* Expected values computed independently from BINARY.md bit layout: 17 bits:
     (year-1900) in bits 9..16, month in 5..8, day in 0..4. *)
  let cases =
    [
      (1900, 1, 1), 33;
      (2025, 6, 15), 64207;
      (2000, 12, 31), 51615;
      (1900, 1, 31), 63;
      (2099, 3, 7), 101991;
    ]
  in
  List.iter
    (fun (input, expected) ->
      let got = Date.pack input in
      if got <> expected
      then (
        let y, m, d = input in
        Alcotest.failf "pack (%d,%d,%d): expected %d got %d" y m d expected got
      )
    )
    cases
;;

let test_date_unpack_known () =
  let valid =
    [
      64207, Some (2025, 6, 15);
      33, Some (1900, 1, 1);
      51615, Some (2000, 12, 31);
    ]
  in
  List.iter
    (fun (input, expected) ->
      let got = Date.unpack input in
      if got <> expected
      then
        Alcotest.failf "unpack %d: expected %s got %s" input
          ( match expected with
          | Some (y, m, d) -> Printf.sprintf "Some (%d,%d,%d)" y m d
          | None -> "None"
          )
          ( match got with
          | Some (y, m, d) -> Printf.sprintf "Some (%d,%d,%d)" y m d
          | None -> "None"
          )
    )
    valid
;;

let test_date_unpack_invalid () =
  (* Each value has exactly one field out of the valid range per the spec *)
  let cases =
    [ 64015; (* month=0 *) 64431; (* month=13 *) 64192 (* day=0 *) ]
  in
  List.iter
    (fun input ->
      match Date.unpack input with
      | None -> ()
      | Some (y, m, d) ->
        Alcotest.failf "unpack %d: expected None got Some (%d,%d,%d)" input y m
          d
    )
    cases
;;

(* --- Date.to_human / of_human --- *)

let test_date_to_human_of_human_roundtrip =
  QCheck_alcotest.to_alcotest
    (QCheck2.Test.make ~name:"to_human/of_human roundtrip" gen_date (fun date ->
       Date.of_human (Date.to_human date) = Some date
   )
    )
;;

let test_date_to_human_known () =
  let cases =
    [
      (2025, 6, 15), 20250615;
      (1900, 1, 1), 19000101;
      (2000, 12, 31), 20001231;
      (9999, 9, 9), 99990909;
    ]
  in
  List.iter
    (fun (input, expected) ->
      let got = Date.to_human input in
      if got <> expected
      then (
        let y, m, d = input in
        Alcotest.failf "to_human (%d,%d,%d): expected %d got %d" y m d expected
          got
      )
    )
    cases
;;

let test_date_of_human_known () =
  let valid =
    [
      20250615, Some (2025, 6, 15);
      19000101, Some (1900, 1, 1);
      20001231, Some (2000, 12, 31);
      99990909, Some (9999, 9, 9);
    ]
  in
  List.iter
    (fun (input, expected) ->
      let got = Date.of_human input in
      if got <> expected
      then
        Alcotest.failf "of_human %d: expected %s got %s" input
          ( match expected with
          | Some (y, m, d) -> Printf.sprintf "Some (%d,%d,%d)" y m d
          | None -> "None"
          )
          ( match got with
          | Some (y, m, d) -> Printf.sprintf "Some (%d,%d,%d)" y m d
          | None -> "None"
          )
    )
    valid
;;

let test_date_of_human_invalid () =
  let cases =
    [
      0;
      (* year too small *)
      9990101;
      (* year 999, < 1000 *)
      20250015;
      (* month 0 *)
      20251315;
      (* month 13 *)
      20250600;
      (* day 0 *)
      20250632;
      (* day 32 *)
      100000101;
      (* year 10000 *)
    ]
  in
  List.iter
    (fun input ->
      match Date.of_human input with
      | None -> ()
      | Some (y, m, d) ->
        Alcotest.failf "of_human %d: expected None got Some (%d,%d,%d)" input y
          m d
    )
    cases
;;

(* --- Date.of_tm / to_tm --- *)

let test_date_of_tm_to_tm_roundtrip =
  QCheck_alcotest.to_alcotest
    (QCheck2.Test.make ~name:"of_tm(to_tm d) = d" gen_date (fun date ->
       Date.of_tm (Date.to_tm date) = date
   )
    )
;;

let test_date_to_tm_known () =
  let y, m, d = 2025, 6, 15 in
  let tm = Date.to_tm (y, m, d) in
  if tm.Unix.tm_year <> 125
  then Alcotest.failf "to_tm tm_year: expected 125 got %d" tm.Unix.tm_year;
  if tm.Unix.tm_mon <> 5
  then Alcotest.failf "to_tm tm_mon: expected 5 got %d" tm.Unix.tm_mon;
  if tm.Unix.tm_mday <> 15
  then Alcotest.failf "to_tm tm_mday: expected 15 got %d" tm.Unix.tm_mday;
  if tm.Unix.tm_hour <> 0
  then Alcotest.failf "to_tm tm_hour: expected 0 got %d" tm.Unix.tm_hour;
  if tm.Unix.tm_min <> 0
  then Alcotest.failf "to_tm tm_min: expected 0 got %d" tm.Unix.tm_min;
  if tm.Unix.tm_sec <> 0
  then Alcotest.failf "to_tm tm_sec: expected 0 got %d" tm.Unix.tm_sec
;;

let test_date_of_tm_known () =
  let tm =
    Unix.
      {
        tm_year = 125;
        tm_mon = 5;
        tm_mday = 15;
        tm_hour = 10;
        tm_min = 30;
        tm_sec = 45;
        tm_wday = 0;
        tm_yday = 0;
        tm_isdst = false;
      }
  in
  let got = Date.of_tm tm in
  if got <> (2025, 6, 15)
  then (
    let y, m, d = got in
    Alcotest.failf "of_tm: expected (2025,6,15) got (%d,%d,%d)" y m d
  )
;;

(* --- Datetime.pack / unpack --- *)

let gen_datetime =
  QCheck2.Gen.(
    let* y = int_range 1900 9999 in
    let* m = int_range 1 12 in
    let* d = int_range 1 31 in
    let* hh = int_range 0 23 in
    let* mm = int_range 0 59 in
    return (y, m, d, hh, mm)
  )
;;

let test_datetime_pack_unpack_roundtrip =
  QCheck_alcotest.to_alcotest
    (QCheck2.Test.make ~name:"pack/unpack roundtrip" gen_datetime (fun dt ->
       Datetime.unpack (Datetime.pack dt) = Some dt
   )
    )
;;

let test_datetime_pack_known () =
  (* Expected values computed independently from BINARY.md bit layout: 28 bits:
     (year-1900) in bits 20..27, month in 16..19, day in 11..15, hour in 6..10,
     minute in 0..5. *)
  let cases =
    [
      (1900, 1, 1, 0, 0), 67584;
      (2025, 6, 15, 14, 30), 131496862;
      (2000, 12, 31, 23, 59), 105709051;
      (1900, 1, 1, 23, 59), 69115;
      (2099, 3, 7, 8, 5), 208878085;
    ]
  in
  List.iter
    (fun (input, expected) ->
      let got = Datetime.pack input in
      if got <> expected
      then (
        let y, m, d, hh, mm = input in
        Alcotest.failf "pack (%d,%d,%d,%d,%d): expected %d got %d" y m d hh mm
          expected got
      )
    )
    cases
;;

let test_datetime_unpack_known () =
  let valid =
    [
      131496862, Some (2025, 6, 15, 14, 30);
      67584, Some (1900, 1, 1, 0, 0);
      105709051, Some (2000, 12, 31, 23, 59);
    ]
  in
  List.iter
    (fun (input, expected) ->
      let got = Datetime.unpack input in
      if got <> expected
      then
        Alcotest.failf "unpack %d: expected %s got %s" input
          ( match expected with
          | Some (y, m, d, hh, mm) ->
            Printf.sprintf "Some (%d,%d,%d,%d,%d)" y m d hh mm
          | None -> "None"
          )
          ( match got with
          | Some (y, m, d, hh, mm) ->
            Printf.sprintf "Some (%d,%d,%d,%d,%d)" y m d hh mm
          | None -> "None"
          )
    )
    valid
;;

let test_datetime_unpack_invalid () =
  (* Each value has exactly one field out of the valid range per the spec *)
  let cases =
    [
      131103390;
      (* month=0 *)
      131955358;
      (* month=13 *)
      131465886;
      (* day=0 *)
      131497502;
      (* hour=24 *)
      131496636;
      (* minute=60 *)
    ]
  in
  List.iter
    (fun input ->
      match Datetime.unpack input with
      | None -> ()
      | Some (y, m, d, hh, mm) ->
        Alcotest.failf "unpack %d: expected None got Some (%d,%d,%d,%d,%d)"
          input y m d hh mm
    )
    cases
;;

(* --- Datetime.to_human / of_human --- *)

let test_datetime_to_human_of_human_roundtrip =
  QCheck_alcotest.to_alcotest
    (QCheck2.Test.make ~name:"to_human/of_human roundtrip" gen_datetime
       (fun dt -> Datetime.of_human (Datetime.to_human dt) = Some dt
   )
    )
;;

let test_datetime_to_human_known () =
  let cases =
    [
      (2025, 6, 15, 14, 30), 202506151430;
      (1900, 1, 1, 0, 0), 190001010000;
      (2000, 12, 31, 23, 59), 200012312359;
      (9999, 9, 9, 9, 9), 999909090909;
    ]
  in
  List.iter
    (fun (input, expected) ->
      let got = Datetime.to_human input in
      if got <> expected
      then (
        let y, m, d, hh, mm = input in
        Alcotest.failf "to_human (%d,%d,%d,%d,%d): expected %d got %d" y m d hh
          mm expected got
      )
    )
    cases
;;

let test_datetime_of_human_known () =
  let valid =
    [
      202506151430, Some (2025, 6, 15, 14, 30);
      190001010000, Some (1900, 1, 1, 0, 0);
      200012312359, Some (2000, 12, 31, 23, 59);
      999909090909, Some (9999, 9, 9, 9, 9);
    ]
  in
  List.iter
    (fun (input, expected) ->
      let got = Datetime.of_human input in
      if got <> expected
      then
        Alcotest.failf "of_human %d: expected %s got %s" input
          ( match expected with
          | Some (y, m, d, hh, mm) ->
            Printf.sprintf "Some (%d,%d,%d,%d,%d)" y m d hh mm
          | None -> "None"
          )
          ( match got with
          | Some (y, m, d, hh, mm) ->
            Printf.sprintf "Some (%d,%d,%d,%d,%d)" y m d hh mm
          | None -> "None"
          )
    )
    valid
;;

let test_datetime_of_human_invalid () =
  let cases =
    [
      0;
      (* year too small *)
      99901010000;
      (* year 999, < 1000 *)
      202500151430;
      (* month 0 *)
      202513151430;
      (* month 13 *)
      202506001430;
      (* day 0 *)
      202506321430;
      (* day 32 *)
      202506152430;
      (* hour 24 *)
      202506151460;
      (* minute 60 *)
      10000001010000;
      (* year 10000 *)
    ]
  in
  List.iter
    (fun input ->
      match Datetime.of_human input with
      | None -> ()
      | Some (y, m, d, hh, mm) ->
        Alcotest.failf "of_human %d: expected None got Some (%d,%d,%d,%d,%d)"
          input y m d hh mm
    )
    cases
;;

(* --- Datetime.of_tm / to_tm --- *)

let test_datetime_of_tm_to_tm_roundtrip =
  QCheck_alcotest.to_alcotest
    (QCheck2.Test.make ~name:"of_tm(to_tm d) = d" gen_datetime (fun dt ->
       Datetime.of_tm (Datetime.to_tm dt) = dt
   )
    )
;;

let test_datetime_to_tm_known () =
  let y, m, d, hh, mm = 2025, 6, 15, 14, 30 in
  let tm = Datetime.to_tm (y, m, d, hh, mm) in
  if tm.Unix.tm_year <> 125
  then Alcotest.failf "to_tm tm_year: expected 125 got %d" tm.Unix.tm_year;
  if tm.Unix.tm_mon <> 5
  then Alcotest.failf "to_tm tm_mon: expected 5 got %d" tm.Unix.tm_mon;
  if tm.Unix.tm_mday <> 15
  then Alcotest.failf "to_tm tm_mday: expected 15 got %d" tm.Unix.tm_mday;
  if tm.Unix.tm_hour <> 14
  then Alcotest.failf "to_tm tm_hour: expected 14 got %d" tm.Unix.tm_hour;
  if tm.Unix.tm_min <> 30
  then Alcotest.failf "to_tm tm_min: expected 30 got %d" tm.Unix.tm_min;
  if tm.Unix.tm_sec <> 0
  then Alcotest.failf "to_tm tm_sec: expected 0 got %d" tm.Unix.tm_sec
;;

let test_datetime_of_tm_known () =
  let tm =
    Unix.
      {
        tm_year = 125;
        tm_mon = 5;
        tm_mday = 15;
        tm_hour = 14;
        tm_min = 30;
        tm_sec = 45;
        tm_wday = 0;
        tm_yday = 0;
        tm_isdst = false;
      }
  in
  let got = Datetime.of_tm tm in
  if got <> (2025, 6, 15, 14, 30)
  then (
    let y, m, d, hh, mm = got in
    Alcotest.failf "of_tm: expected (2025,6,15,14,30) got (%d,%d,%d,%d,%d)" y m
      d hh mm
  )
;;

(* --- Timestamp.pack / unpack --- *)

let test_timestamp_pack_unpack_roundtrip =
  QCheck_alcotest.to_alcotest
    (QCheck2.Test.make ~name:"pack/unpack roundtrip"
       QCheck2.Gen.(int_range 0 2_100_000_000)
       (fun ts -> Timestamp.unpack (Timestamp.pack ts) = ts)
    )
;;

let test_timestamp_pack_known () =
  (* The offset is 1,750,750,750 per spec: wire zero ≈ June 2025 *)
  let cases =
    [
      1_750_750_750, 0;
      (* offset itself maps to wire-zero *)
      0, -1_750_750_750;
      (* Unix epoch maps to negative wire value *)
      1_750_750_751, 1;
      1_750_750_749, -1;
      2_000_000_000, 2_000_000_000 - 1_750_750_750;
    ]
  in
  List.iter
    (fun (input, expected) ->
      let got = Timestamp.pack input in
      if got <> expected
      then Alcotest.failf "pack %d: expected %d got %d" input expected got
    )
    cases
;;

let test_timestamp_unpack_known () =
  let cases =
    [
      0, 1_750_750_750;
      1, 1_750_750_751;
      -1, 1_750_750_749;
      -1_750_750_750, 0;
      100_000_000, 1_850_750_750;
    ]
  in
  List.iter
    (fun (input, expected) ->
      let got = Timestamp.unpack input in
      if got <> expected
      then Alcotest.failf "unpack %d: expected %d got %d" input expected got
    )
    cases
;;

let test_timestamp_offset () =
  (* Verify the offset constant matches the spec value *)
  if Timestamp.offset <> 1_750_750_750
  then Alcotest.failf "offset: expected 1750750750 got %d" Timestamp.offset
;;

(* === Codec Round-Trip Infrastructure === *)

let make_test_ctx () =
  let open Vof in
  let ctx = Context.make ~update:true "com.test" in
  let msg_schema =
    Context.schema ctx
      ~fields:
        [
          "orders", [ List_of "com.test.order" ];
          "addresses", [ List_of "com.test.address" ];
          "sales_report", [];
          "matrix", [];
          "nullable", [];
        ]
      "$msg"
  in
  let order_schema =
    Context.schema ctx
      ~fields:
        [
          "id", [ Key ];
          "modified_at", [ Req ];
          "name", [];
          "active", [];
          "total", [];
          "ordered_on", [];
          "shipped_at", [];
          "created_ts", [];
          "duration", [];
          "weight", [];
          "weight32", [];
          "split", [];
          "discount", [];
          "price", [];
          "sales_tax", [];
          "local_tax", [];
          "neg_price", [];
          "neg_tax", [];
          "qty", [];
          "sku", [];
          "lang", [];
          "country", [];
          "subdivision", [];
          "curr", [];
          "tax_code", [];
          "measure_unit", [];
          "description", [];
          "ip_addr", [];
          "network", [];
          "coords", [];
          "payload", [];
          "tags", [];
          "scores", [];
          "flags", [];
          "status", [];
          "payment", [];
          "lines", [];
          "addresses", [];
          (* Large uint coverage (5 Binary encoding size classes) *)
          "bigint1", [];
          "bigint2", [];
          "bigint3", [];
          "bigint4", [];
          "bigint5", [];
          (* Binary gap coverage: skip1, there1, skip2+skip3, there2 *)
          "gap_skip1", [];
          "gap_there1", [];
          "gap_skip2", [];
          "gap_skip3", [];
          "gap_there2", [];
        ]
      "order"
  in
  let line_schema =
    Context.schema ctx
      ~fields:[ "i", [ Key ]; "product", []; "qty", []; "unit_price", [] ]
      "order.line"
  in
  let address_schema =
    Context.schema ctx
      ~fields:[ "id", [ Key ]; "street", []; "city", []; "zip", [] ]
      "address"
  in
  let status_schema =
    Context.schema ctx
      ~fields:[ "Draft", []; "Confirmed", []; "Shipped", []; "Delivered", [] ]
      "order.status"
  in
  let payment_schema =
    Context.schema ctx
      ~fields:[ "Cash", []; "Card", []; "Transfer", [] ]
      "order.payment"
  in
  let sales_schema =
    Context.schema ctx
      ~fields:
        [
          "date", [];
          "orders", [];
          "revenue", [];
          "tax", [];
          "items", [];
          "avg_order", [];
        ]
      "sales_report"
  in
  ( ctx,
    msg_schema,
    order_schema,
    line_schema,
    address_schema,
    status_schema,
    payment_schema,
    sales_schema )
;;

let make_test_t
  ( _,
    msg_schema,
    order_schema,
    line_schema,
    address_schema,
    status_schema,
    payment_schema,
    sales_schema
  ) =
  let open Vof in
  let sm = StringMap.empty in
  let line1 =
    Record
      ( line_schema,
        sm
        |> StringMap.add "i" (Uint 1)
        |> StringMap.add "product" (String "Widget")
        |> StringMap.add "qty" (Quantity ((10, 0), None))
        |> StringMap.add "unit_price" (Decimal (599, 2))
      )
  in
  let line2 =
    Record
      ( line_schema,
        sm
        |> StringMap.add "i" (Uint 2)
        |> StringMap.add "product" (String "Gadget")
        |> StringMap.add "qty" (Quantity ((3, 0), None))
        |> StringMap.add "unit_price" (Decimal (1299, 2))
      )
  in
  let addr1 =
    Record
      ( address_schema,
        sm
        |> StringMap.add "id" (Uint 1)
        |> StringMap.add "street" (String "123 Main St")
        |> StringMap.add "city" (String "Montreal")
        |> StringMap.add "zip" (String "H2X1A1")
      )
  in
  let addr2 =
    Record
      ( address_schema,
        sm
        |> StringMap.add "id" (Uint 2)
        |> StringMap.add "street" (String "456 Oak Ave")
        |> StringMap.add "city" (String "Toronto")
        |> StringMap.add "zip" (String "M5V2T6")
      )
  in
  let order =
    Record
      ( order_schema,
        sm
        |> StringMap.add "id" (Uint 42)
        |> StringMap.add "modified_at" (Timestamp 1750800000)
        |> StringMap.add "name" (String "Test Order")
        |> StringMap.add "active" (Bool true)
        |> StringMap.add "total" (Amount ((12350, 2), None))
        |> StringMap.add "ordered_on" (Date { year = 2025; month = 6; day = 15 })
        |> StringMap.add "shipped_at"
             (Datetime
                { year = 2025; month = 6; day = 16; hour = 10; minute = 30 }
             )
        |> StringMap.add "created_ts" (Timestamp 1750750800)
        |> StringMap.add "duration"
             (Timespan { hmonths = 4; days = 3; secs = 0 })
        |> StringMap.add "weight" (Float 3.14)
        |> StringMap.add "weight32" (Float 100000.0)
        |> StringMap.add "split" (Ratio (1, 3))
        |> StringMap.add "discount" (Percent (-10, 0))
        |> StringMap.add "price" (Amount ((9999, 2), Some "USD"))
        |> StringMap.add "sales_tax" (Tax ((750, 2), "US_ST", Some "USD"))
        |> StringMap.add "local_tax" (Tax ((125, 2), "CA_QC_QST", None))
        |> StringMap.add "neg_price" (Amount ((-500, 2), Some "USD"))
        |> StringMap.add "neg_tax" (Tax ((-75, 2), "CA_QC_QST", None))
        |> StringMap.add "qty" (Quantity ((5, 0), Some "EA"))
        |> StringMap.add "sku" (Code "ABC_123")
        |> StringMap.add "lang" (Language "en")
        |> StringMap.add "country" (Country "US")
        |> StringMap.add "subdivision" (Subdivision "QC")
        |> StringMap.add "curr" (Currency "USD")
        |> StringMap.add "tax_code" (Tax_code "US_ST")
        |> StringMap.add "measure_unit" (Unit "KGM")
        |> StringMap.add "description"
             (Text
                (sm |> StringMap.add "en" "Test" |> StringMap.add "fr" "Essai")
             )
        |> StringMap.add "ip_addr" (Ip (Bytes.of_string "\xC0\xA8\x01\x01"))
        |> StringMap.add "network"
             (Subnet (Bytes.of_string "\x0A\x00\x00\x00", 8))
        |> StringMap.add "coords" (Coords (45.5, -73.5))
        |> StringMap.add "payload" (Data (Bytes.of_string "hello"))
        |> StringMap.add "tags"
             (Strmap
                (sm
                |> StringMap.add "priority" (String "high")
                |> StringMap.add "source" (String "web")
                )
             )
        |> StringMap.add "scores"
             (Uintmap
                (IntMap.empty
                |> IntMap.add 1 (Int 100)
                |> IntMap.add 2 (Int (-200))
                )
             )
        |> StringMap.add "flags" (List [ Bool true; Bool false; Bool true ])
        |> StringMap.add "status" (Enum (status_schema, "Confirmed"))
        |> StringMap.add "payment"
             (Variant (payment_schema, "Card", [ String "visa" ]))
        |> StringMap.add "lines" (List [ line1; line2 ])
        |> StringMap.add "addresses"
             (List
                [
                  Record (address_schema, StringMap.add "id" (Uint 1) sm);
                  Record (address_schema, StringMap.add "id" (Uint 2) sm);
                ]
             )
        (* Large uints: one per Binary encoding size class *)
        |> StringMap.add "bigint1" (Uint 0x900_0000)
        |> StringMap.add "bigint2" (Uint 0x2_0000_0000)
        |> StringMap.add "bigint3" (Uint 0x200_0000_0000)
        |> StringMap.add "bigint4" (Uint 0x2_0000_0000_0000)
        |> StringMap.add "bigint5" (Uint 0x200_0000_0000_0000)
        (* Gap fields: gap_skip1/skip2/skip3 left unset *)
        |> StringMap.add "gap_there1" (Uint 23)
        |> StringMap.add "gap_there2" (Uint 42)
      )
  in
  let make_sales_row d orders revenue tax items avg =
    ( sales_schema,
      sm
      |> StringMap.add "date" (Date d)
      |> StringMap.add "orders" (Uint orders)
      |> StringMap.add "revenue" (Decimal revenue)
      |> StringMap.add "tax" (Decimal tax)
      |> StringMap.add "items" (Uint items)
      |> StringMap.add "avg_order" (Decimal avg) )
  in
  let sales_report =
    Series
      [
        make_sales_row
          { year = 2025; month = 6; day = 9 }
          15 (45000, 2) (5850, 2) 42 (3000, 2);
        make_sales_row
          { year = 2025; month = 6; day = 10 }
          22 (68500, 2) (8905, 2) 67 (3113, 2);
        make_sales_row
          { year = 2025; month = 6; day = 11 }
          18 (52300, 2) (6799, 2) 51 (2905, 2);
      ]
  in
  let matrix =
    Ndarray ([ 2; 3 ], [| Int 1; Int 2; Int 3; Int 4; Int 5; Int 6 |])
  in
  Record
    ( msg_schema,
      sm
      |> StringMap.add "orders" (List [ order ])
      |> StringMap.add "addresses" (List [ addr1; addr2 ])
      |> StringMap.add "sales_report" sales_report
      |> StringMap.add "matrix" matrix
      |> StringMap.add "nullable" Null
    )
;;

let test_of_vof ctx
  ( msg_schema,
    order_schema,
    line_schema,
    address_schema,
    status_schema,
    payment_schema,
    sales_schema
  ) v =
  let open Vof in
  let require msg = function
    | None -> Alcotest.fail msg
    | Some x -> x
  in
  let get name sm =
    match StringMap.find_opt name sm with
    | None -> Alcotest.failf "missing field %S" name
    | Some v -> v
  in
  let chk_uint name exp sm =
    let got = require name (Read.uint (get name sm)) in
    if got <> exp then Alcotest.failf "%s: expected %d got %d" name exp got
  in
  let chk_str name exp sm =
    let got = require name (Read.string (get name sm)) in
    if got <> exp then Alcotest.failf "%s: expected %S got %S" name exp got
  in
  let chk_dec name exp sm =
    let got = require name (Read.decimal (get name sm)) in
    if got <> exp
    then
      Alcotest.failf "%s: expected (%d,%d) got (%d,%d)" name (fst exp) (snd exp)
        (fst got) (snd got)
  in
  (* Decode root $msg *)
  let msg = require "decode $msg" (Read.record ctx msg_schema Option.some v) in
  (* --- Orders --- *)
  let orders =
    require "decode orders"
      (Read.list (Read.record ctx order_schema Option.some) (get "orders" msg))
  in
  let o =
    match orders with
    | [ o ] -> o
    | _ -> Alcotest.failf "expected 1 order, got %d" (List.length orders)
  in
  chk_uint "id" 42 o;
  let ts = require "modified_at" (Read.timestamp (get "modified_at" o)) in
  if ts <> 1750800000
  then Alcotest.failf "modified_at: expected 1750800000 got %d" ts;
  chk_str "name" "Test Order" o;
  let active = require "active" (Read.bool (get "active" o)) in
  if active <> true then Alcotest.fail "active: expected true";
  let amt = require "total" (Read.amount (get "total" o)) in
  if amt <> ((1235, 1), None) then Alcotest.fail "total mismatch";
  let d = require "ordered_on" (Read.date (get "ordered_on" o)) in
  if d <> { year = 2025; month = 6; day = 15 }
  then Alcotest.fail "ordered_on mismatch";
  let dt = require "shipped_at" (Read.datetime (get "shipped_at" o)) in
  if dt <> { year = 2025; month = 6; day = 16; hour = 10; minute = 30 }
  then Alcotest.fail "shipped_at mismatch";
  let ts2 = require "created_ts" (Read.timestamp (get "created_ts" o)) in
  if ts2 <> 1750750800
  then Alcotest.failf "created_ts: expected 1750750800 got %d" ts2;
  let span = require "duration" (Read.timespan (get "duration" o)) in
  if span <> { hmonths = 4; days = 3; secs = 0 }
  then Alcotest.fail "duration mismatch";
  let w = require "weight" (Read.float (get "weight" o)) in
  if w <> 3.14 then Alcotest.fail "weight mismatch";
  let w32 = require "weight32" (Read.float (get "weight32" o)) in
  if w32 <> 100000.0 then Alcotest.fail "weight32 mismatch";
  let r = require "split" (Read.ratio (get "split" o)) in
  if r <> (1, 3) then Alcotest.fail "split mismatch";
  let pct = require "discount" (Read.percent (get "discount" o)) in
  if pct <> (-10, 0) then Alcotest.fail "discount mismatch";
  let amt = require "price" (Read.amount (get "price" o)) in
  if amt <> ((9999, 2), Some "USD") then Alcotest.fail "price mismatch";
  let tax = require "sales_tax" (Read.tax (get "sales_tax" o)) in
  if tax <> ((75, 1), "US_ST", Some "USD")
  then Alcotest.fail "sales_tax mismatch";
  let local_tax = require "local_tax" (Read.tax (get "local_tax" o)) in
  if local_tax <> ((125, 2), "CA_QC_QST", None)
  then Alcotest.fail "local_tax mismatch";
  let neg_price = require "neg_price" (Read.amount (get "neg_price" o)) in
  if neg_price <> ((-5, 0), Some "USD") then Alcotest.fail "neg_price mismatch";
  let neg_tax = require "neg_tax" (Read.tax (get "neg_tax" o)) in
  if neg_tax <> ((-75, 2), "CA_QC_QST", None)
  then Alcotest.fail "neg_tax mismatch";
  let qty = require "qty" (Read.quantity (get "qty" o)) in
  if qty <> ((5, 0), Some "EA") then Alcotest.fail "qty mismatch";
  let code = require "sku" (Read.code (get "sku" o)) in
  if code <> "ABC_123" then Alcotest.failf "sku: expected ABC_123 got %s" code;
  let lang = require "lang" (Read.language (get "lang" o)) in
  if lang <> "en" then Alcotest.failf "lang: expected en got %s" lang;
  let country = require "country" (Read.country (get "country" o)) in
  if country <> "US" then Alcotest.failf "country: expected US got %s" country;
  let subdiv = require "subdivision" (Read.subdivision (get "subdivision" o)) in
  if subdiv <> "QC" then Alcotest.failf "subdivision: expected QC got %s" subdiv;
  let curr = require "curr" (Read.currency (get "curr" o)) in
  if curr <> "USD" then Alcotest.failf "curr: expected USD got %s" curr;
  let tc = require "tax_code" (Read.tax_code (get "tax_code" o)) in
  if tc <> "US_ST" then Alcotest.failf "tax_code: expected US_ST got %s" tc;
  let u = require "measure_unit" (Read.unit_ (get "measure_unit" o)) in
  if u <> "KGM" then Alcotest.failf "measure_unit: expected KGM got %s" u;
  (* Text *)
  let txt = require "description" (Read.text (get "description" o)) in
  let en = require "description[en]" (StringMap.find_opt "en" txt) in
  if en <> "Test" then Alcotest.failf "description[en]: expected Test got %s" en;
  let fr = require "description[fr]" (StringMap.find_opt "fr" txt) in
  if fr <> "Essai"
  then Alcotest.failf "description[fr]: expected Essai got %s" fr;
  (* IP *)
  let ip = require "ip_addr" (Read.ip (get "ip_addr" o)) in
  if ip <> Bytes.of_string "\xC0\xA8\x01\x01"
  then Alcotest.fail "ip_addr mismatch";
  (* Subnet *)
  let net = require "network" (Read.subnet (get "network" o)) in
  if net <> (Bytes.of_string "\x0A\x00\x00\x00", 8)
  then Alcotest.fail "network mismatch";
  (* Coords *)
  let coords = require "coords" (Read.coords (get "coords" o)) in
  if coords <> (45.5, -73.5) then Alcotest.fail "coords mismatch";
  (* Data *)
  let payload = require "payload" (Read.data (get "payload" o)) in
  if payload <> Bytes.of_string "hello" then Alcotest.fail "payload mismatch";
  (* Strmap *)
  let tags = require "tags" (Read.strmap Read.string (get "tags" o)) in
  let tp = require "tags[priority]" (StringMap.find_opt "priority" tags) in
  if tp <> "high" then Alcotest.failf "tags[priority]: expected high got %s" tp;
  let src = require "tags[source]" (StringMap.find_opt "source" tags) in
  if src <> "web" then Alcotest.failf "tags[source]: expected web got %s" src;
  (* Uintmap *)
  let scores = require "scores" (Read.uintmap Read.int (get "scores" o)) in
  let s1 = require "scores[1]" (IntMap.find_opt 1 scores) in
  if s1 <> 100 then Alcotest.failf "scores[1]: expected 100 got %d" s1;
  let s2 = require "scores[2]" (IntMap.find_opt 2 scores) in
  if s2 <> -200 then Alcotest.failf "scores[2]: expected -200 got %d" s2;
  (* List of bools *)
  let flags = require "flags" (Read.list Read.bool (get "flags" o)) in
  if flags <> [ true; false; true ] then Alcotest.fail "flags mismatch";
  (* Enum *)
  let status =
    require "status"
      (Read.variant ctx status_schema
         (fun name _args -> Some name)
         (get "status" o)
      )
  in
  if status <> "Confirmed"
  then Alcotest.failf "status: expected Confirmed got %s" status;
  (* Variant *)
  let payment =
    require "payment"
      (Read.variant ctx payment_schema
         (fun name args ->
           match name, args with
           | "Card", [ arg ] -> Read.string arg
           | n, [] -> Some n
           | _ -> None
         )
         (get "payment" o)
      )
  in
  if payment <> "visa"
  then Alcotest.failf "payment: expected visa got %s" payment;
  (* Lines (dependent children) *)
  let lines =
    require "lines"
      (Read.list (Read.record ctx line_schema Option.some) (get "lines" o))
  in
  ( match lines with
  | [ l1; l2 ] ->
    chk_uint "i" 1 l1;
    chk_str "product" "Widget" l1;
    let qty = require "qty" (Read.quantity (get "qty" l1)) in
    if qty <> ((10, 0), None) then Alcotest.fail "l1 qty mismatch";
    chk_dec "unit_price" (599, 2) l1;
    chk_uint "i" 2 l2;
    chk_str "product" "Gadget" l2;
    let qty = require "qty" (Read.quantity (get "qty" l2)) in
    if qty <> ((3, 0), None) then Alcotest.fail "l1 qty mismatch";
    chk_dec "unit_price" (1299, 2) l2
  | _ -> Alcotest.failf "expected 2 lines, got %d" (List.length lines)
  );
  (* Order addresses (references) *)
  let oaddrs =
    require "order.addresses"
      (Read.list
         (Read.record ctx address_schema Option.some)
         (get "addresses" o)
      )
  in
  ( match oaddrs with
  | [ a1; a2 ] -> chk_uint "id" 1 a1; chk_uint "id" 2 a2
  | _ -> Alcotest.failf "expected 2 order addr refs, got %d" (List.length oaddrs)
  );
  (* --- Large uints (Binary encoding size classes) --- *)
  chk_uint "bigint1" 0x900_0000 o;
  chk_uint "bigint2" 0x2_0000_0000 o;
  chk_uint "bigint3" 0x200_0000_0000 o;
  chk_uint "bigint4" 0x2_0000_0000_0000 o;
  chk_uint "bigint5" 0x200_0000_0000_0000 o;
  (* --- Gap fields (Binary positional gap codes) --- *)
  chk_uint "gap_there1" 23 o;
  chk_uint "gap_there2" 42 o;
  (* --- $msg Addresses --- *)
  let addrs =
    require "msg.addresses"
      (Read.list
         (Read.record ctx address_schema Option.some)
         (get "addresses" msg)
      )
  in
  ( match addrs with
  | [ a1; a2 ] ->
    chk_uint "id" 1 a1;
    chk_str "street" "123 Main St" a1;
    chk_str "city" "Montreal" a1;
    chk_str "zip" "H2X1A1" a1;
    chk_uint "id" 2 a2;
    chk_str "street" "456 Oak Ave" a2;
    chk_str "city" "Toronto" a2;
    chk_str "zip" "M5V2T6" a2
  | _ -> Alcotest.failf "expected 2 msg addresses, got %d" (List.length addrs)
  );
  (* --- Sales Report (Series) --- *)
  let sales =
    require "sales_report"
      (Read.series ctx sales_schema Option.some (get "sales_report" msg))
  in
  ( match sales with
  | [ r1; r2; r3 ] ->
    let chk_row name row exp_d exp_ord exp_rev exp_tax exp_items exp_avg =
      let d = require (name ^ ".date") (Read.date (get "date" row)) in
      if d <> exp_d then Alcotest.failf "%s.date mismatch" name;
      chk_uint "orders" exp_ord row;
      chk_dec "revenue" exp_rev row;
      chk_dec "tax" exp_tax row;
      chk_uint "items" exp_items row;
      chk_dec "avg_order" exp_avg row
    in
    chk_row "sales[0]" r1
      { year = 2025; month = 6; day = 9 }
      15 (450, 0) (585, 1) 42 (30, 0);
    chk_row "sales[1]" r2
      { year = 2025; month = 6; day = 10 }
      22 (685, 0) (8905, 2) 67 (3113, 2);
    chk_row "sales[2]" r3
      { year = 2025; month = 6; day = 11 }
      18 (523, 0) (6799, 2) 51 (2905, 2)
  | _ -> Alcotest.failf "expected 3 sales rows, got %d" (List.length sales)
  );
  (* --- Matrix (Ndarray) --- *)
  let dims, arr = require "matrix" (Read.ndarray Read.int (get "matrix" msg)) in
  if dims <> [ 2; 3 ] then Alcotest.fail "matrix dims mismatch";
  if arr <> [| 1; 2; 3; 4; 5; 6 |] then Alcotest.fail "matrix values mismatch";
  (* --- Nullable --- *)
  match Read.uint (get "nullable" msg) with
  | None -> ()
  | Some n -> Alcotest.failf "nullable: expected None, got Some %d" n
;;

let test_codec_base () =
  let ( (ctx, msg_s, order_s, line_s, addr_s, status_s, payment_s, sales_s) as
        all
      ) =
    make_test_ctx ()
  in
  let schemas = msg_s, order_s, line_s, addr_s, status_s, payment_s, sales_s in
  let v = make_test_t all in
  test_of_vof ctx schemas v
;;

let test_json_large_int () =
  let open Vof in
  let ctx = Context.make ~update:true "com.test.li" in
  (* Normal integer: should encode as JSON `Int *)
  let normal = Uint 42 in
  let j_normal = Vof_json.of_vof ctx normal in
  ( match j_normal with
  | `Int 42 -> ()
  | `Int n -> Alcotest.failf "normal: expected `Int 42, got `Int %d" n
  | `String s -> Alcotest.failf "normal: expected `Int 42, got `String %S" s
  | _ -> Alcotest.fail "normal: unexpected JSON form"
  );
  let decoded_normal = Read.uint (Vof_json.to_raw j_normal) in
  ( match decoded_normal with
  | Some 42 -> ()
  | Some n -> Alcotest.failf "normal roundtrip: expected 42 got %d" n
  | None -> Alcotest.fail "normal roundtrip: Read.uint returned None"
  );
  (* Large unsigned beyond MAX_SAFE_INTEGER: should encode as JSON `String *)
  let big = 9_007_199_254_740_992 in
  let large = Uint big in
  let j_large = Vof_json.of_vof ctx large in
  ( match j_large with
  | `String s ->
    if s <> string_of_int big
    then
      Alcotest.failf "large uint: expected `String %S, got `String %S"
        (string_of_int big) s
  | `Int n -> Alcotest.failf "large uint: expected `String, got `Int %d" n
  | _ -> Alcotest.fail "large uint: unexpected JSON form"
  );
  let decoded_large = Read.uint (Vof_json.to_raw j_large) in
  ( match decoded_large with
  | Some n when n = big -> ()
  | Some n -> Alcotest.failf "large uint roundtrip: expected %d got %d" big n
  | None -> Alcotest.fail "large uint roundtrip: Read.uint returned None"
  );
  (* Large negative beyond -MAX_SAFE_INTEGER: should encode as JSON `String *)
  let neg_big = -9_007_199_254_740_992 in
  let large_neg = Int neg_big in
  let j_neg = Vof_json.of_vof ctx large_neg in
  ( match j_neg with
  | `String s ->
    if s <> string_of_int neg_big
    then
      Alcotest.failf "large neg: expected `String %S, got `String %S"
        (string_of_int neg_big) s
  | `Int n -> Alcotest.failf "large neg: expected `String, got `Int %d" n
  | _ -> Alcotest.fail "large neg: unexpected JSON form"
  );
  let decoded_neg = Read.int (Vof_json.to_raw j_neg) in
  match decoded_neg with
  | Some n when n = neg_big -> ()
  | Some n -> Alcotest.failf "large neg roundtrip: expected %d got %d" neg_big n
  | None -> Alcotest.fail "large neg roundtrip: Read.int returned None"
;;

let test_codec_json () =
  let ( (ctx, msg_s, order_s, line_s, addr_s, status_s, payment_s, sales_s) as
        all
      ) =
    make_test_ctx ()
  in
  let schemas = msg_s, order_s, line_s, addr_s, status_s, payment_s, sales_s in
  let v = make_test_t all in
  let json = Vof_json.of_vof ctx v in
  let decoded = Vof_json.to_raw json in
  test_of_vof ctx schemas decoded
;;

let test_codec_cbor () =
  let ( (ctx, msg_s, order_s, line_s, addr_s, status_s, payment_s, sales_s) as
        all
      ) =
    make_test_ctx ()
  in
  let schemas = msg_s, order_s, line_s, addr_s, status_s, payment_s, sales_s in
  let v = make_test_t all in
  let encoded = Vof_cbor.encode_str ctx v in
  let decoded, _len =
    match Vof_cbor.decode encoded with
    | Some x -> x
    | None -> Alcotest.fail "CBOR decode returned None"
  in
  test_of_vof ctx schemas decoded
;;

let test_codec_bin () =
  let ( (ctx, msg_s, order_s, line_s, addr_s, status_s, payment_s, sales_s) as
        all
      ) =
    make_test_ctx ()
  in
  let schemas = msg_s, order_s, line_s, addr_s, status_s, payment_s, sales_s in
  let v = make_test_t all in
  let encoded = Vof_bin.encode_str ctx v in
  let decoded, _len =
    match Vof_bin.decode encoded with
    | Some x -> x
    | None -> Alcotest.fail "Binary decode returned None"
  in
  test_of_vof ctx schemas decoded
;;

let test_codec_cbor_coverage () =
  let open Vof in
  let ctx = Context.make ~update:true "com.test.cborcov" in
  let require msg = function
    | None -> Alcotest.fail msg
    | Some x -> x
  in
  (* 1. Float that encodes as 32-bit (not 16, not 64) *)
  let f32_val = 100000.0 in
  let enc = Vof_cbor.encode_str ctx (Float f32_val) in
  (* First byte 0xFA = CBOR float32 *)
  if String.length enc < 1 || Char.code enc.[0] <> 0xFA
  then
    Alcotest.failf "float32: expected CBOR float32 tag 0xFA, got 0x%02X"
      (Char.code enc.[0]);
  let dec, _ = require "float32 decode" (Vof_cbor.decode enc) in
  let got = require "float32 read" (Read.float dec) in
  if got <> f32_val
  then Alcotest.failf "float32: expected %f got %f" f32_val got;
  (* 2. List of 25 items (exercises CBOR array length >= 24) *)
  let big_list = List (List.init 25 (fun i -> Int i)) in
  let enc = Vof_cbor.encode_str ctx big_list in
  let dec, _ = require "list25 decode" (Vof_cbor.decode enc) in
  let got = require "list25 read" (Read.list Read.int dec) in
  if List.length got <> 25
  then Alcotest.failf "list25: expected 25 items, got %d" (List.length got);
  List.iteri
    (fun i v ->
      if v <> i then Alcotest.failf "list25[%d]: expected %d got %d" i i v
    )
    got;
  (* 3. Strmap of 25 pairs *)
  let big_strmap =
    Strmap
      (List.init 25 (fun i -> Printf.sprintf "k%02d" i, Int i)
      |> List.to_seq
      |> StringMap.of_seq
      )
  in
  let enc = Vof_cbor.encode_str ctx big_strmap in
  let dec, _ = require "strmap25 decode" (Vof_cbor.decode enc) in
  let got = require "strmap25 read" (Read.strmap Read.int dec) in
  if StringMap.cardinal got <> 25
  then
    Alcotest.failf "strmap25: expected 25 pairs, got %d" (StringMap.cardinal got);
  (* 4. Uintmap of 25 pairs *)
  let big_uintmap =
    Uintmap
      (List.init 25 (fun i -> i, Int (i * 10)) |> List.to_seq |> IntMap.of_seq)
  in
  let enc = Vof_cbor.encode_str ctx big_uintmap in
  let dec, _ = require "uintmap25 decode" (Vof_cbor.decode enc) in
  let got = require "uintmap25 read" (Read.uintmap Read.int dec) in
  if IntMap.cardinal got <> 25
  then
    Alcotest.failf "uintmap25: expected 25 pairs, got %d" (IntMap.cardinal got);
  (* 5. 64-bit integer (value > 2^32) *)
  let big_int_val = 5_000_000_000 in
  let enc = Vof_cbor.encode_str ctx (Uint big_int_val) in
  let dec, _ = require "uint64 decode" (Vof_cbor.decode enc) in
  let got = require "uint64 read" (Read.uint dec) in
  if got <> big_int_val
  then Alcotest.failf "uint64: expected %d got %d" big_int_val got;
  (* 6. Indefinite-length text string *)
  let indef_text =
    let b = Buffer.create 16 in
    Buffer.add_char b '\x7F';
    (* indefinite text start *)
    Buffer.add_char b '\x63';
    (* text chunk of length 3 *)
    Buffer.add_string b "Hel";
    Buffer.add_char b '\x62';
    (* text chunk of length 2 *)
    Buffer.add_string b "lo";
    Buffer.add_char b '\xFF';
    (* break *)
    Buffer.contents b
  in
  let dec, _ = require "indef text decode" (Vof_cbor.decode indef_text) in
  let got = require "indef text read" (Read.string dec) in
  if got <> "Hello"
  then Alcotest.failf "indef text: expected %S got %S" "Hello" got;
  (* Indefinite-length byte string *)
  let indef_bytes =
    let b = Buffer.create 16 in
    Buffer.add_char b '\x5F';
    (* indefinite bytes start *)
    Buffer.add_char b '\x43';
    (* bytes chunk of length 3 *)
    Buffer.add_string b "wor";
    Buffer.add_char b '\x42';
    (* bytes chunk of length 2 *)
    Buffer.add_string b "ld";
    Buffer.add_char b '\xFF';
    (* break *)
    Buffer.contents b
  in
  let dec, _ = require "indef bytes decode" (Vof_cbor.decode indef_bytes) in
  let got = require "indef bytes read" (Read.data dec) in
  if got <> Bytes.of_string "world"
  then Alcotest.fail "indef bytes: expected \"world\""
;;

let test_codec_cbor_magic () =
  let ( (ctx, msg_s, order_s, line_s, addr_s, status_s, payment_s, sales_s) as
        all
      ) =
    make_test_ctx ()
  in
  let schemas = msg_s, order_s, line_s, addr_s, status_s, payment_s, sales_s in
  let v = make_test_t all in
  let encoded = Vof_cbor.encode_str ctx ~magic:true v in
  let decoded, _len =
    match Vof_cbor.decode encoded with
    | Some x -> x
    | None -> Alcotest.fail "CBOR magic decode returned None"
  in
  test_of_vof ctx schemas decoded
;;

let test_equal_is_ref_make_ref () =
  let open Vof in
  let all = make_test_ctx () in
  let _, _, order_schema, _, address_schema, _, _, _ = all in
  let v = make_test_t all in
  (* equal: identical values *)
  let v2 = make_test_t all in
  if not (equal v v2) then Alcotest.fail "equal: identical msg should be equal";
  (* equal: modified value *)
  let sm = StringMap.empty in
  let modified =
    Record
      ( address_schema,
        sm
        |> StringMap.add "id" (Uint 1)
        |> StringMap.add "street" (String "CHANGED")
        |> StringMap.add "city" (String "Montreal")
        |> StringMap.add "zip" (String "H2X1A1")
      )
  in
  let original =
    Record
      ( address_schema,
        sm
        |> StringMap.add "id" (Uint 1)
        |> StringMap.add "street" (String "123 Main St")
        |> StringMap.add "city" (String "Montreal")
        |> StringMap.add "zip" (String "H2X1A1")
      )
  in
  if equal modified original
  then Alcotest.fail "equal: modified addr should not equal original";
  (* is_ref: full address record → not a ref *)
  ( match original with
  | Record r ->
    if is_ref r then Alcotest.fail "is_ref: full address should not be a ref"
  | _ -> Alcotest.fail "expected Record"
  );
  (* is_ref: address with only key → is a ref *)
  let addr_ref = address_schema, StringMap.add "id" (Uint 1) StringMap.empty in
  if not (is_ref addr_ref)
  then Alcotest.fail "is_ref: address with only id should be a ref";
  (* make_ref: order record stripped to key + req *)
  match v with
  | Record (_, msg_fields) -> (
    match StringMap.find_opt "orders" msg_fields with
    | Some (List [ Record (_, ofields) ]) ->
      let order_rec = order_schema, ofields in
      let r = make_ref order_rec in
      if not (is_ref r) then Alcotest.fail "make_ref result should be a ref";
      let _, rfields = r in
      (* Should have key "id" and req "modified_at" *)
      if not (StringMap.mem "id" rfields)
      then Alcotest.fail "make_ref: missing key field id";
      if not (StringMap.mem "modified_at" rfields)
      then Alcotest.fail "make_ref: missing req field modified_at";
      (* Should not have other fields *)
      if StringMap.mem "name" rfields
      then Alcotest.fail "make_ref: should not have 'name'"
    | _ -> Alcotest.fail "could not extract order from msg"
  )
  | _ -> Alcotest.fail "expected Record at top level"
;;

let test_pp_smoke () =
  let open Vof in
  let all = make_test_ctx () in
  let v = make_test_t all in
  (* pp on various scalars shouldn't crash and should be non-empty *)
  let check_nonempty label x =
    let s = pp x in
    if String.length s = 0
    then Alcotest.failf "pp %s returned empty string" label
  in
  check_nonempty "Null" Null;
  check_nonempty "Bool" (Bool true);
  check_nonempty "Int" (Int 42);
  check_nonempty "Uint" (Uint 7);
  check_nonempty "Float" (Float 3.14);
  check_nonempty "String" (String "hello");
  check_nonempty "Decimal" (Decimal (1235, 1));
  check_nonempty "Date" (Date { year = 2025; month = 6; day = 15 });
  check_nonempty "Timestamp" (Timestamp 1750800000);
  check_nonempty "Code" (Code "ABC");
  check_nonempty "Currency" (Currency "USD");
  (* pp on the full msg record *)
  check_nonempty "msg Record" v;
  (* pp_ref on a full order *)
  ( match v with
  | Record (_, msg_fields) -> (
    match StringMap.find_opt "orders" msg_fields with
    | Some (List [ Record r ]) ->
      let s = pp_ref r in
      if String.length s = 0
      then Alcotest.fail "pp_ref on order returned empty string"
    | _ -> Alcotest.fail "could not extract order"
  )
  | _ -> Alcotest.fail "expected Record"
  );
  (* pp_ref on a reference *)
  let _, _, _, _, address_schema, _, _, _ = all in
  let addr_ref = address_schema, StringMap.add "id" (Uint 1) StringMap.empty in
  let s = pp_ref addr_ref in
  if String.length s = 0
  then Alcotest.fail "pp_ref on addr ref returned empty string"
;;

(* === Read helpers: each_field, field, children === *)

type test_addr = { a_id: int; a_street: string; a_city: string; a_zip: string }

let empty_addr = { a_id = 0; a_street = ""; a_city = ""; a_zip = "" }

type test_line = {
  l_i: int;
  l_product: string;
  l_qty: (int * int) * string option;
  l_unit_price: int * int;
}

let empty_line =
  { l_i = 0; l_product = ""; l_qty = (0, 0), None; l_unit_price = 0, 0 }
;;

let test_each_field_happy () =
  let open Vof in
  let all = make_test_ctx () in
  let ctx, _, _, _, address_schema, _, _, _ = all in
  let v = make_test_t all in
  let msg_fields =
    match v with
    | Record (_, f) -> f
    | _ -> Alcotest.fail "expected Record"
  in
  let addrs_v =
    match StringMap.find_opt "addresses" msg_fields with
    | Some v -> v
    | None -> Alcotest.fail "missing addresses"
  in
  let decode_addr v =
    let sm =
      match Read.record ctx address_schema Option.some v with
      | Some sm -> sm
      | None -> Alcotest.fail "record decode failed"
    in
    match
      Read.each_field (address_schema, sm) empty_addr (fun k v acc ->
        match k with
        | "id" -> { acc with a_id = Read.field Read.uint v }
        | "street" -> { acc with a_street = Read.field Read.string v }
        | "city" -> { acc with a_city = Read.field Read.string v }
        | "zip" -> { acc with a_zip = Read.field Read.string v }
        | _ -> acc
    )
    with
    | Some a -> a
    | None -> Alcotest.fail "each_field returned None"
  in
  let addrs =
    match Read.list (fun x -> Some x) addrs_v with
    | Some l -> List.map decode_addr l
    | None -> Alcotest.fail "addrs not a list"
  in
  let a1, a2 =
    match addrs with
    | [ a; b ] -> a, b
    | _ -> Alcotest.failf "expected 2 addresses, got %d" (List.length addrs)
  in
  Alcotest.(check int) "a1.id" 1 a1.a_id;
  Alcotest.(check string) "a1.street" "123 Main St" a1.a_street;
  Alcotest.(check string) "a1.city" "Montreal" a1.a_city;
  Alcotest.(check string) "a1.zip" "H2X1A1" a1.a_zip;
  Alcotest.(check int) "a2.id" 2 a2.a_id;
  Alcotest.(check string) "a2.street" "456 Oak Ave" a2.a_street;
  Alcotest.(check string) "a2.city" "Toronto" a2.a_city;
  Alcotest.(check string) "a2.zip" "M5V2T6" a2.a_zip;
  (* Test ~null default: address with Null city gets fallback *)
  let null_city_sm =
    StringMap.empty
    |> StringMap.add "id" (Uint 99)
    |> StringMap.add "street" (String "Test St")
    |> StringMap.add "city" Null
    |> StringMap.add "zip" (String "X0X0X0")
  in
  match
    Read.each_field (address_schema, null_city_sm) empty_addr (fun k v acc ->
      match k with
      | "id" -> { acc with a_id = Read.field Read.uint v }
      | "street" -> { acc with a_street = Read.field Read.string v }
      | "city" -> { acc with a_city = Read.field Read.string ~null:"default" v }
      | "zip" -> { acc with a_zip = Read.field Read.string v }
      | _ -> acc
  )
  with
  | Some a ->
    Alcotest.(check string) "null city gets default" "default" a.a_city
  | None -> Alcotest.fail "each_field with ~null returned None"
;;

let test_each_field_errors () =
  let open Vof in
  let all = make_test_ctx () in
  let _, _, _, _, address_schema, _, _, _ = all in
  (* Type mismatch: Bool where string expected *)
  let bad_sm =
    StringMap.empty
    |> StringMap.add "id" (Uint 1)
    |> StringMap.add "street" (Bool true)
    |> StringMap.add "city" (String "Montreal")
    |> StringMap.add "zip" (String "H2X1A1")
  in
  let warn = ref [] in
  let result =
    Read.each_field ~warn (address_schema, bad_sm) empty_addr (fun k v acc ->
      match k with
      | "id" -> { acc with a_id = Read.field Read.uint v }
      | "street" -> { acc with a_street = Read.field Read.string v }
      | "city" -> { acc with a_city = Read.field Read.string v }
      | "zip" -> { acc with a_zip = Read.field Read.string v }
      | _ -> acc
  )
  in
  if Option.is_some result then Alcotest.fail "expected None on type mismatch";
  if List.length !warn = 0
  then Alcotest.fail "expected warning on type mismatch";
  (* Null without ~null default → failure *)
  let null_sm =
    StringMap.empty
    |> StringMap.add "id" (Uint 1)
    |> StringMap.add "street" Null
    |> StringMap.add "city" (String "Montreal")
    |> StringMap.add "zip" (String "H2X1A1")
  in
  let warn2 = ref [] in
  let result2 =
    Read.each_field ~warn:warn2 (address_schema, null_sm) empty_addr
      (fun k v acc ->
      match k with
      | "id" -> { acc with a_id = Read.field Read.uint v }
      | "street" -> { acc with a_street = Read.field Read.string v }
      | "city" -> { acc with a_city = Read.field Read.string v }
      | "zip" -> { acc with a_zip = Read.field Read.string v }
      | _ -> acc
  )
  in
  if Option.is_some result2
  then Alcotest.fail "expected None on Null without ~null";
  if List.length !warn2 = 0
  then Alcotest.fail "expected warning on Null without default"
;;

let test_children_patch () =
  let open Vof in
  let all = make_test_ctx () in
  let ctx, _, _, line_schema, _, _, _, _ = all in
  (* Current lines matching make_test_t *)
  let existing =
    [
      {
        l_i = 1;
        l_product = "Widget";
        l_qty = (10, 0), None;
        l_unit_price = 599, 2;
      };
      {
        l_i = 2;
        l_product = "Gadget";
        l_qty = (3, 0), None;
        l_unit_price = 1299, 2;
      };
    ]
  in
  let line_of_vof base v =
    match Read.record ctx line_schema Option.some v with
    | None -> None
    | Some sm ->
      let init = Option.value ~default:empty_line base in
      Read.each_field (line_schema, sm) init (fun k v acc ->
        match k with
        | "i" -> { acc with l_i = Read.field Read.uint v }
        | "product" ->
          { acc with l_product = Read.field Read.string ~null:acc.l_product v }
        | "qty" ->
          { acc with l_qty = Read.field Read.quantity ~null:acc.l_qty v }
        | "unit_price" ->
          {
            acc with
            l_unit_price = Read.field Read.decimal ~null:acc.l_unit_price v;
          }
        | _ -> acc
    )
  in
  let line_key_of l = l.l_i in
  let line_key_read sm =
    match StringMap.find_opt "i" sm with
    | None -> None
    | Some v -> Read.uint v
  in
  (* Patch: delete line 1, edit line 2 qty, add new line *)
  let patch =
    List
      [
        (* Delete: reference with only key field *)
        Record (line_schema, StringMap.singleton "i" (Uint 1));
        (* Edit: key + changed qty *)
        Record
          ( line_schema,
            StringMap.empty
            |> StringMap.add "i" (Uint 2)
            |> StringMap.add "qty" (Quantity ((5, 0), None))
          );
        (* Add: no key field *)
        Record
          ( line_schema,
            StringMap.empty
            |> StringMap.add "product" (String "Doohickey")
            |> StringMap.add "qty" (Quantity ((7, 0), None))
            |> StringMap.add "unit_price" (Decimal (399, 2))
          );
      ]
  in
  let result =
    Read.children ctx line_schema ~of_vof:line_of_vof ~key_of:line_key_of
      ~key_read:line_key_read existing patch
  in
  match result with
  | None -> Alcotest.fail "children returned None"
  | Some [ edited; added ] ->
    (* Line 1 deleted: not in result *)
    (* Line 2 edited: qty updated, product and unit_price preserved *)
    Alcotest.(check int) "edited.i" 2 edited.l_i;
    Alcotest.(check string) "edited.product preserved" "Gadget" edited.l_product;
    if edited.l_qty <> ((5, 0), None)
    then Alcotest.fail "edited.qty should be (5,0),None";
    if edited.l_unit_price <> (1299, 2)
    then Alcotest.fail "edited.unit_price should be preserved";
    (* New line added *)
    Alcotest.(check int) "added.i" 0 added.l_i;
    Alcotest.(check string) "added.product" "Doohickey" added.l_product;
    if added.l_qty <> ((7, 0), None)
    then Alcotest.fail "added.qty should be (7,0),None";
    if added.l_unit_price <> (399, 2)
    then Alcotest.fail "added.unit_price mismatch"
  | Some l -> Alcotest.failf "expected 2 result lines, got %d" (List.length l)
;;

(* === Diff === *)

let diff_fields a b =
  match Vof.diff (Vof.Record a) (Vof.Record b) with
  | None -> Alcotest.fail "diff returned None for two records"
  | Some (Vof.Record (_, fields)) -> fields
  | Some _ -> Alcotest.fail "diff returned non-Record"
;;

let test_diff_non_records () =
  let open Vof in
  if Option.is_some (diff (Int 1) (Int 2)) then Alcotest.fail "Int vs Int";
  if Option.is_some (diff (List []) (List [])) then Alcotest.fail "List vs List";
  if Option.is_some (diff (String "a") (String "b"))
  then Alcotest.fail "String vs String";
  if Option.is_some (diff Null Null) then Alcotest.fail "Null vs Null";
  (* Mixed: one record, one non-record *)
  let _, _, _, _, addr_s, _, _, _ = make_test_ctx () in
  let r = Record (addr_s, StringMap.singleton "id" (Uint 1)) in
  if Option.is_some (diff r (Int 1)) then Alcotest.fail "Record vs Int";
  if Option.is_some (diff (Int 1) r) then Alcotest.fail "Int vs Record"
;;

let test_diff_scalars () =
  let open Vof in
  let _, _, _, _, addr_s, _, _, _ = make_test_ctx () in
  let mk id fields =
    ( addr_s,
      List.fold_left
        (fun m (k, v) -> StringMap.add k v m)
        (StringMap.singleton "id" (Uint id))
        fields )
  in
  (* Identical → only key *)
  let r =
    mk 1
      [
        "street", String "123 Main St";
        "city", String "Montreal";
        "zip", String "H2X1A1";
      ]
  in
  let p = diff_fields r r in
  if not (StringMap.mem "id" p) then Alcotest.fail "identical: missing key";
  if StringMap.mem "street" p then Alcotest.fail "identical: has street";
  if StringMap.mem "city" p then Alcotest.fail "identical: has city";
  if StringMap.mem "zip" p then Alcotest.fail "identical: has zip";
  (* Changed + removed + unchanged *)
  let a =
    mk 1
      [
        "street", String "123 Main St";
        "city", String "Montreal";
        "zip", String "H2X1A1";
      ]
  in
  let b = mk 1 [ "street", String "456 Oak Ave"; "zip", String "H2X1A1" ] in
  let p = diff_fields a b in
  if not (StringMap.mem "id" p) then Alcotest.fail "change: missing key";
  ( match StringMap.find_opt "street" p with
  | Some (String "456 Oak Ave") -> ()
  | _ -> Alcotest.fail "change: street should be '456 Oak Ave'"
  );
  ( match StringMap.find_opt "city" p with
  | Some Null -> ()
  | _ -> Alcotest.fail "change: city should be Null (removed)"
  );
  if StringMap.mem "zip" p then Alcotest.fail "change: unchanged zip present";
  (* Added field *)
  let a2 = mk 2 [ "street", String "X" ] in
  let b2 = mk 2 [ "street", String "X"; "city", String "Toronto" ] in
  let p = diff_fields a2 b2 in
  if StringMap.mem "street" p then Alcotest.fail "add: unchanged street";
  ( match StringMap.find_opt "city" p with
  | Some (String "Toronto") -> ()
  | _ -> Alcotest.fail "add: city should be Toronto"
  );
  (* Null → value *)
  let a3 = mk 3 [ "street", Null ] in
  let b3 = mk 3 [ "street", String "New St" ] in
  let p = diff_fields a3 b3 in
  ( match StringMap.find_opt "street" p with
  | Some (String "New St") -> ()
  | _ -> Alcotest.fail "null_to_val: street should be 'New St'"
  );
  (* Value → Null *)
  let p = diff_fields b3 a3 in
  match StringMap.find_opt "street" p with
  | Some Null -> ()
  | _ -> Alcotest.fail "val_to_null: street should be Null"
;;

let test_diff_children_and_collections () =
  let open Vof in
  let _, _, order_s, line_s, addr_s, _, _, _ = make_test_ctx () in
  let sm = StringMap.empty in
  let mk_line i prod qty price =
    Record
      ( line_s,
        sm
        |> StringMap.add "i" (Uint i)
        |> StringMap.add "product" (String prod)
        |> StringMap.add "qty" (Quantity (qty, None))
        |> StringMap.add "unit_price" (Decimal price)
      )
  in
  let mk_order fields =
    ( order_s,
      List.fold_left
        (fun m (k, v) -> StringMap.add k v m)
        (sm
        |> StringMap.add "id" (Uint 42)
        |> StringMap.add "modified_at" (Timestamp 1750800000)
        )
        fields )
  in
  let tags v =
    Strmap
      (sm
      |> StringMap.add "priority" (String v)
      |> StringMap.add "source" (String "web")
      )
  in
  let scores v = Uintmap (IntMap.empty |> IntMap.add 1 (Int v)) in
  (* a: lines 1,2 ; b: lines 2(edited),3(new) ; line 1 deleted *)
  let a =
    mk_order
      [
        "name", String "Test Order";
        ( "lines",
          List
            [
              mk_line 1 "Widget" (10, 0) (599, 2);
              mk_line 2 "Gadget" (3, 0) (1299, 2);
            ] );
        "tags", tags "high";
        "scores", scores 100;
        "flags", List [ Bool true; Bool false ];
      ]
  in
  let b =
    mk_order
      [
        "name", String "Test Order";
        ( "lines",
          List
            [
              mk_line 2 "Gadget" (5, 0) (1299, 2);
              mk_line 3 "Thing" (7, 0) (399, 2);
            ] );
        "tags", tags "low";
        "scores", scores 200;
        "flags", List [ Bool true; Bool true ];
      ]
  in
  let p = diff_fields a b in
  if not (StringMap.mem "id" p) then Alcotest.fail "missing key";
  if StringMap.mem "name" p then Alcotest.fail "unchanged name present";
  (* Lines: child PATCH semantics *)
  ( match StringMap.find_opt "lines" p with
  | Some (List pl) -> (
    let find_i t =
      List.find_opt
        (function
          | Record (_, m) -> StringMap.find_opt "i" m = Some (Uint t)
          | _ -> false
          )
        pl
    in
    (* Line 1 deleted → reference only *)
    ( match find_i 1 with
    | Some (Record r) ->
      if not (is_ref r) then Alcotest.fail "line1: should be ref (delete)"
    | _ -> Alcotest.fail "line1: delete missing"
    );
    (* Line 2 edited → key + changed qty only *)
    ( match find_i 2 with
    | Some (Record (_, m)) ->
      ( match StringMap.find_opt "qty" m with
      | Some (Quantity ((5, 0), None)) -> ()
      | _ -> Alcotest.fail "line2: qty should be (5,0)"
      );
      if StringMap.mem "product" m then Alcotest.fail "line2: unchanged product";
      if StringMap.mem "unit_price" m
      then Alcotest.fail "line2: unchanged unit_price"
    | _ -> Alcotest.fail "line2: edit missing"
    );
    (* Line 3 added → full record *)
    match find_i 3 with
    | Some (Record (_, m)) ->
      if StringMap.find_opt "product" m <> Some (String "Thing")
      then Alcotest.fail "line3: should have product"
    | _ -> Alcotest.fail "line3: add missing"
  )
  | _ -> Alcotest.fail "lines should be a List"
  );
  (* Strmap: changed → present *)
  ( match StringMap.find_opt "tags" p with
  | Some t -> if not (equal t (tags "low")) then Alcotest.fail "tags mismatch"
  | None -> Alcotest.fail "tags should be present"
  );
  (* Uintmap: changed → present *)
  ( match StringMap.find_opt "scores" p with
  | Some s -> if not (equal s (scores 200)) then Alcotest.fail "scores mismatch"
  | None -> Alcotest.fail "scores should be present"
  );
  (* Scalar list: changed → full replacement *)
  ( match StringMap.find_opt "flags" p with
  | Some (List [ Bool true; Bool true ]) -> ()
  | _ -> Alcotest.fail "flags mismatch"
  );
  (* Identical children → lines omitted *)
  let same = mk_order [ "lines", List [ mk_line 1 "X" (1, 0) (1, 0) ] ] in
  let p = diff_fields same same in
  if StringMap.mem "lines" p
  then Alcotest.fail "identical: lines should be omitted";
  (* Nested single record: recursive diff *)
  let nest1 =
    Record
      ( addr_s,
        sm
        |> StringMap.add "id" (Uint 1)
        |> StringMap.add "street" (String "123 Main St")
        |> StringMap.add "city" (String "Montreal")
      )
  in
  let nest2 =
    Record
      ( addr_s,
        sm
        |> StringMap.add "id" (Uint 1)
        |> StringMap.add "street" (String "456 Oak Ave")
        |> StringMap.add "city" (String "Montreal")
      )
  in
  let ra = mk_order [ "tags", nest1 ] in
  let rb = mk_order [ "tags", nest2 ] in
  let p = diff_fields ra rb in
  ( match StringMap.find_opt "tags" p with
  | Some (Record (_, m)) ->
    if not (StringMap.mem "id" m) then Alcotest.fail "nested: missing key";
    ( match StringMap.find_opt "street" m with
    | Some (String "456 Oak Ave") -> ()
    | _ -> Alcotest.fail "nested: street should be changed"
    );
    if StringMap.mem "city" m
    then Alcotest.fail "nested: unchanged city present"
  | _ -> Alcotest.fail "nested record: tags should be a Record patch"
  );
  (* Nested single record: identical → omitted *)
  let rc = mk_order [ "tags", nest1 ] in
  let p = diff_fields rc rc in
  if StringMap.mem "tags" p
  then Alcotest.fail "identical nested: tags should be omitted";
  (* Identical non-empty non-record list → omitted *)
  let fl = List [ Bool true; Bool false ] in
  let fa = mk_order [ "flags", fl ] in
  let p = diff_fields fa fa in
  if StringMap.mem "flags" p
  then Alcotest.fail "identical non-record list: flags should be omitted"
;;

let () =
  Alcotest.run "vof"
    [
      ( "Core",
        [
          Alcotest.test_case "detect_format" `Quick test_detect_format;
          Alcotest.test_case "pp_warn" `Quick test_pp_warn;
        ] );
      ( "Context",
        [
          Alcotest.test_case "make" `Quick test_context_make;
          Alcotest.test_case "schema basic" `Quick test_context_schema_basic;
          Alcotest.test_case "schema retrieval" `Quick
            test_context_schema_retrieval;
          Alcotest.test_case "schema nested" `Quick test_context_schema_nested;
          Alcotest.test_case "lookup_id" `Quick test_context_lookup_id;
          Alcotest.test_case "idx_sym" `Quick test_context_idx_sym;
          Alcotest.test_case "no-update rejects unknown" `Quick
            test_context_no_update_rejects_unknown;
          Alcotest.test_case "save/load roundtrip" `Quick test_context_save_load;
          Alcotest.test_case "save/load qualifiers" `Quick
            test_context_save_load_qualifiers;
          Alcotest.test_case "load nonexistent in update mode" `Quick
            test_context_load_nonexistent_update;
          Alcotest.test_case "schema redefine no-update" `Quick
            test_context_schema_redefine_no_update;
          Alcotest.test_case "schema redefine update" `Quick
            test_context_schema_redefine_update;
        ] );
      ( "Float16",
        [
          Alcotest.test_case "roundtrip all 64K values" `Quick test_float16_conv;
          Alcotest.test_case "rejects unrepresentable" `Quick
            test_float16_rejects;
          Alcotest.test_case "known values" `Quick test_float16_known_values;
          Alcotest.test_case "bits_of_float" `Quick test_float16_bits_of_float;
        ] );
      ( "Ratio",
        [
          Alcotest.test_case "of_string valid" `Quick test_ratio_of_string_known;
          Alcotest.test_case "of_string invalid" `Quick
            test_ratio_of_string_invalid;
          Alcotest.test_case "to_string known" `Quick test_ratio_to_string_known;
          test_ratio_roundtrip;
        ] );
      ( "Datetime",
        [
          test_datetime_pack_unpack_roundtrip;
          Alcotest.test_case "pack known" `Quick test_datetime_pack_known;
          Alcotest.test_case "unpack known" `Quick test_datetime_unpack_known;
          Alcotest.test_case "unpack invalid" `Quick
            test_datetime_unpack_invalid;
          test_datetime_to_human_of_human_roundtrip;
          Alcotest.test_case "to_human known" `Quick
            test_datetime_to_human_known;
          Alcotest.test_case "of_human known" `Quick
            test_datetime_of_human_known;
          Alcotest.test_case "of_human invalid" `Quick
            test_datetime_of_human_invalid;
          test_datetime_of_tm_to_tm_roundtrip;
          Alcotest.test_case "to_tm known" `Quick test_datetime_to_tm_known;
          Alcotest.test_case "of_tm known" `Quick test_datetime_of_tm_known;
        ] );
      ( "Date",
        [
          test_date_pack_unpack_roundtrip;
          Alcotest.test_case "pack known" `Quick test_date_pack_known;
          Alcotest.test_case "unpack known" `Quick test_date_unpack_known;
          Alcotest.test_case "unpack invalid" `Quick test_date_unpack_invalid;
          test_date_to_human_of_human_roundtrip;
          Alcotest.test_case "to_human known" `Quick test_date_to_human_known;
          Alcotest.test_case "of_human known" `Quick test_date_of_human_known;
          Alcotest.test_case "of_human invalid" `Quick
            test_date_of_human_invalid;
          test_date_of_tm_to_tm_roundtrip;
          Alcotest.test_case "to_tm known" `Quick test_date_to_tm_known;
          Alcotest.test_case "of_tm known" `Quick test_date_of_tm_known;
        ] );
      ( "Timestamp",
        [
          test_timestamp_pack_unpack_roundtrip;
          Alcotest.test_case "pack known" `Quick test_timestamp_pack_known;
          Alcotest.test_case "unpack known" `Quick test_timestamp_unpack_known;
          Alcotest.test_case "offset matches spec" `Quick test_timestamp_offset;
        ] );
      ( "Decimal",
        [
          test_decimal_optimize_idempotent;
          test_decimal_optimize_preserves_value;
          test_decimal_optimize_no_trailing_zeros;
          Alcotest.test_case "optimize known" `Quick test_decimal_optimize_known;
          test_decimal_pack_unpack_roundtrip;
          Alcotest.test_case "pack known" `Quick test_decimal_pack_known;
          Alcotest.test_case "unpack known" `Quick test_decimal_unpack_known;
          test_decimal_to_n_of_n_roundtrip;
          Alcotest.test_case "to_n known" `Quick test_decimal_to_n_known;
          Alcotest.test_case "of_n known" `Quick test_decimal_of_n_known;
          test_decimal_of_string_to_string_roundtrip;
          Alcotest.test_case "of_string known" `Quick
            test_decimal_of_string_known;
          Alcotest.test_case "to_string known" `Quick
            test_decimal_to_string_known;
          Alcotest.test_case "of_string ~shift" `Quick
            test_decimal_of_string_shift;
        ] );
      ( "Codec base",
        [ Alcotest.test_case "roundtrip typed" `Quick test_codec_base ] );
      ( "JSON codec",
        [
          Alcotest.test_case "large int encoding" `Quick test_json_large_int;
          Alcotest.test_case "roundtrip" `Quick test_codec_json;
        ] );
      ( "CBOR codec",
        [
          Alcotest.test_case "roundtrip" `Quick test_codec_cbor;
          Alcotest.test_case "roundtrip with magic" `Quick test_codec_cbor_magic;
          Alcotest.test_case "coverage edges" `Quick test_codec_cbor_coverage;
        ] );
      "Binary codec", [ Alcotest.test_case "roundtrip" `Quick test_codec_bin ];
      ( "Structural",
        [
          Alcotest.test_case "equal, is_ref, make_ref" `Quick
            test_equal_is_ref_make_ref;
          Alcotest.test_case "pp smoke" `Quick test_pp_smoke;
        ] );
      ( "Read helpers",
        [
          Alcotest.test_case "each_field + field happy path" `Quick
            test_each_field_happy;
          Alcotest.test_case "each_field + field errors" `Quick
            test_each_field_errors;
          Alcotest.test_case "children patch semantics" `Quick
            test_children_patch;
        ] );
      ( "Diff",
        [
          Alcotest.test_case "non-records return None" `Quick
            test_diff_non_records;
          Alcotest.test_case "scalar fields" `Quick test_diff_scalars;
          Alcotest.test_case "children and collections" `Quick
            test_diff_children_and_collections;
        ] );
    ]
;;
