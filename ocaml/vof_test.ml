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

let () =
  Alcotest.run "vof"
    [
      ( "Float16",
        [
          Alcotest.test_case "roundtrip all 64K values" `Quick test_float16_conv;
          Alcotest.test_case "rejects unrepresentable" `Quick
            test_float16_rejects;
          Alcotest.test_case "known values" `Quick test_float16_known_values;
          Alcotest.test_case "bits_of_float" `Quick test_float16_bits_of_float;
        ] );
    ]
;;
