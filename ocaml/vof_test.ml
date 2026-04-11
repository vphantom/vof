let test_float16_conv () =
  for bits = 0 to 65535 do
    let f = Float16.to_float bits in
    match Float.is_nan f with
    | true -> (
      let sign = (bits lsr 15) land 1 in
      let expected = (sign lsl 15) lor 0x7E00 in
      match Float16.of_float_opt f with
      | Some result -> assert (result = 0x7E00 || result = 0xFE00)
      | None -> assert false
    )
    | false -> (
      match Float16.of_float_opt f with
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
      match Float16.of_float_opt f with
      | None -> ()
      | Some bits ->
        Printf.eprintf "FAIL: %h should not encode, got 0x%04X\n" f bits;
        assert false
    )
    should_reject
;;
