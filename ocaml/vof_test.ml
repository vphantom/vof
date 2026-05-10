(** TODO:

    - [Vof_json]
    - [Vof_cbor]
    - [Vof_bin]
    - [Vof.Read] + [equal], [diff], [pp] (thus also [pp_ref]), [make_ref]
    - Services: [make_query] parsing, selection, filters, [build_msg],
      [msg_add], [msg_record]

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
  let idx = Vof.Context.lookup ctx "com.test.order" in
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

let () =
  Alcotest.run "vof"
    [
      "Core", [ Alcotest.test_case "detect_format" `Quick test_detect_format ];
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
    ]
;;
