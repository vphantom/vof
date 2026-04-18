let test_float16_conv () =
  for bits = 0 to 65535 do
    let f = Vof_float16.float_of_bits bits in
    match Float.is_nan f with
    | true -> (
      let sign = (bits lsr 15) land 1 in
      let expected = (sign lsl 15) lor 0x7E00 in
      match Vof_float16.bits_of_float_opt f with
      | Some result -> assert (result = expected)
      | None -> assert false
    )
    | false -> (
      match Vof_float16.bits_of_float_opt f with
      | Some result -> assert (result = bits)
      | None ->
        Printf.eprintf "FAIL: bits=0x%04X float=%h\n" bits f;
        assert false
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
    ]
  in
  List.iter
    (fun f ->
      match Vof_float16.bits_of_float_opt f with
      | None -> ()
      | Some bits ->
        Printf.eprintf "FAIL: %h should not encode, got 0x%04X\n" f bits;
        assert false
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
      then (
        Printf.eprintf "FAIL decode: bits=0x%04X expected=%h got=%h\n" bits
          expected got;
        assert false
      )
    )
    decode_cases;
  (* Negative zero: bit comparison since -0.0 = 0.0 in OCaml *)
  let nz = Vof_float16.float_of_bits 0x8000 in
  assert (Int64.bits_of_float nz = Int64.bits_of_float (-0.0));
  (* NaN: just check it is NaN *)
  assert (Float.is_nan (Vof_float16.float_of_bits 0x7E00));
  assert (Float.is_nan (Vof_float16.float_of_bits 0xFE00));
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
      then (
        Printf.eprintf "FAIL encode: float=%h expected=%s got=%s\n" f
          ( match expected with
          | Some v -> Printf.sprintf "0x%04X" v
          | None -> "None"
          )
          ( match got with
          | Some v -> Printf.sprintf "0x%04X" v
          | None -> "None"
          );
        assert false
      )
    )
    encode_cases
;;

let test_float16_bits_of_float () =
  (* Succeeds on representable values *)
  assert (Vof_float16.bits_of_float 1.0 = 0x3C00);
  assert (Vof_float16.bits_of_float 0.0 = 0x0000);
  assert (Vof_float16.bits_of_float (-0.0) = 0x8000);
  assert (Vof_float16.bits_of_float 65504.0 = 0x7BFF);
  assert (Vof_float16.bits_of_float infinity = 0x7C00);
  (* Raises on non-representable values *)
  let should_raise f =
    match Vof_float16.bits_of_float f with
    | _ ->
      Printf.eprintf "FAIL: bits_of_float %h should have raised\n" f;
      assert false
    | exception _ -> ()
  in
  should_raise 3.14159;
  should_raise 65536.0;
  should_raise Float.min_float
;;

let () =
  test_float16_conv ();
  test_float16_rejects ();
  test_float16_known_values ();
  test_float16_bits_of_float ();
  print_endline "All float16 tests passed."
;;
