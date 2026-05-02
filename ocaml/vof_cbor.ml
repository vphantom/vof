open Vof
open Vof_enc
open Vof_lib

let[@inline] add_byte buf n = Buffer.add_char buf (Char.chr (n land 0xFF))
let[@inline] add_be16 buf n = Buffer.add_uint16_be buf n
let[@inline] add_be32 buf n = Buffer.add_int32_be buf n
let[@inline] add_be64 buf n = Buffer.add_int64_be buf n

let write_head buf major n =
  let m = major lsl 5 in
  match n with
  | n when n < 0 -> invalid_arg "Vof_cbor.write_head: negative argument"
  | n when n <= 23 -> add_byte buf (m lor n)
  | n when n <= 0xFF ->
    add_byte buf (m lor 24);
    add_byte buf n
  | n when n <= 0xFFFF ->
    add_byte buf (m lor 25);
    add_be16 buf n
  | n when n <= 0xFFFF_FFFF ->
    add_byte buf (m lor 26);
    Int32.of_int n |> add_be32 buf
  | n ->
    add_byte buf (m lor 27);
    Int64.of_int n |> add_be64 buf
;;

let write_magic buf = add_be16 buf 0xD9D9; add_byte buf 0xF7
let write_null buf = add_byte buf 0xF6

let write_bool buf = function
  | true -> add_byte buf 0xF5
  | false -> add_byte buf 0xF4
;;

let write_int buf i =
  if i >= 0 then write_head buf 0 i else write_head buf 1 (-1 - i)
;;

let write_uint buf i =
  if i < 0 then invalid_arg "Vof_cbor.write_uint: negative argument";
  write_head buf 0 i
;;

let write_float buf f =
  match Vof_float16.bits_of_float_opt f with
  | Some h -> add_byte buf 0xF9; add_be16 buf h
  | None ->
    let i32 = Int32.bits_of_float f in
    if Float.equal (Int32.float_of_bits i32) f
    then (add_byte buf 0xFA; add_be32 buf i32)
    else (
      add_byte buf 0xFB;
      add_be64 buf (Int64.bits_of_float f)
    )
;;

let write_bytes buf s =
  write_head buf 2 (Bytes.length s);
  Buffer.add_bytes buf s
;;

let write_text buf s =
  write_head buf 3 (String.length s);
  Buffer.add_string buf s
;;

let write_array_head buf l =
  if l < 0 || l > 23 then invalid_arg "Vof_cbor.write_array_head: out of range";
  write_head buf 4 l
;;

let write_array_open buf l =
  if l < 0 then assert false;
  if l < 24 then write_head buf 4 l else add_byte buf 0x9F
;;

let write_array_close buf l = if l >= 24 then add_byte buf 0xFF

let write_map_open buf l =
  if l < 0 then assert false;
  if l < 24 then write_head buf 5 l else add_byte buf 0xBF
;;

let write_map_close buf l = if l >= 24 then add_byte buf 0xFF

let write_array f buf l =
  let len = List.length l in
  if len <= 23 then write_head buf 4 len else add_byte buf 0x9F;
  List.iter (f buf) l;
  if len > 23 then add_byte buf 0xFF
;;

let write_strmap f buf sm =
  let module SM = StringMap in
  let len = SM.cardinal sm in
  if len <= 23 then write_head buf 5 len else add_byte buf 0xBF;
  SM.iter (fun k v -> write_text buf k; f buf v) sm;
  if len > 23 then add_byte buf 0xFF
;;

let write_uintmap f buf im =
  let module IM = IntMap in
  let len = IM.cardinal im in
  if len <= 23 then write_head buf 5 len else add_byte buf 0xBF;
  IM.iter (fun k v -> write_int buf k; f buf v) im;
  if len > 23 then add_byte buf 0xFF
;;

let decode ?(pos = 0) ?len src =
  let len = Option.value len ~default:(String.length src - pos) in
  if pos < 0 || len <= 0 || pos + len > String.length src
  then invalid_arg "Vof_cbor.decode: out of range";
  let limit = pos + len in
  let raw = Bytes.unsafe_of_string src in
  let p = ref pos in
  let[@inline] peek () =
    if !p >= limit then raise_notrace Exit;
    Bytes.unsafe_get raw !p |> Char.code
  in
  let[@inline] read_byte () =
    let pos = !p in
    if pos >= limit then raise_notrace Exit;
    incr p;
    Bytes.unsafe_get raw pos |> Char.code
  in
  let[@inline] read_be16 () =
    let pos = !p in
    if pos + 2 > limit then raise_notrace Exit;
    p := pos + 2;
    Bytes.get_uint16_be raw pos
  in
  let[@inline] read_be32 () =
    let pos = !p in
    if pos + 4 > limit then raise_notrace Exit;
    p := pos + 4;
    Int32.to_int (Bytes.get_int32_be raw pos) land 0xFFFF_FFFF
  in
  let[@inline] read_be64 () =
    if !p + 8 > limit then raise_notrace Exit;
    let n = Bytes.get_int64_be raw !p in
    p := !p + 8;
    if n < 0L || n > Int64.of_int max_int then raise_notrace Exit;
    Int64.to_int n
  in
  let[@inline] slice n =
    let pos = !p in
    if pos + n > limit then raise_notrace Exit;
    p := pos + n;
    String.sub src pos n
  in
  let arg = function
    | a when a < 24 -> a
    | 24 -> read_byte ()
    | 25 -> read_be16 ()
    | 26 -> read_be32 ()
    | 27 -> read_be64 ()
    | _ -> raise_notrace Exit
  in
  let indef_string major =
    let buf = Buffer.create 64 in
    while peek () <> 0xFF do
      let b = read_byte () in
      if b lsr 5 <> major then raise_notrace Exit;
      let n = arg (b land 0x1F) in
      Buffer.add_string buf (slice n)
    done;
    incr p;
    Buffer.contents buf
  in
  let read_indef read_one =
    let acc = ref [] in
    while peek () <> 0xFF do
      acc := read_one () :: !acc
    done;
    incr p;
    List.rev !acc
  in
  let rec item () =
    let b = read_byte () in
    let major = b lsr 5 in
    let additional = b land 0x1F in
    match major with
    | 0 -> Raw_bint (arg additional)
    | 1 -> Raw_bint (-1 - arg additional)
    | 2 | 3 ->
      if additional = 31
      then Raw_bstr (indef_string major)
      else Raw_bstr (slice (arg additional))
    | 4 ->
      if additional = 31
      then Raw_blist (read_indef item)
      else Raw_blist (List.init (arg additional) (fun _ -> item ()))
    | 5 ->
      if additional = 31
      then Raw_blist (read_indef item)
      else Raw_blist (List.init (2 * arg additional) (fun _ -> item ()))
    | 6 ->
      let _tag = arg additional in
      item ()
    | 7 -> (
      match additional with
      | 20 -> Bool false
      | 21 -> Bool true
      | 22 -> Null
      | 25 -> Float (Vof_float16.float_of_bits (read_be16 ()))
      | 26 ->
        if !p + 4 > limit then raise_notrace Exit;
        let n = Bytes.get_int32_be raw !p in
        p := !p + 4;
        Float (Int32.float_of_bits n)
      | 27 ->
        if !p + 8 > limit then raise_notrace Exit;
        let n = Bytes.get_int64_be raw !p in
        p := !p + 8;
        Float (Int64.float_of_bits n)
      | _ -> raise_notrace Exit
    )
    | _ -> raise_notrace Exit
  in
  try Some (item (), !p) with Exit -> None
;;

let rec encode_val ctx buf = function
  | Null -> write_null buf
  | Bool b -> write_bool buf b
  | Int i | Raw_bint i -> write_int buf i
  | Uint i -> write_uint buf i
  | Float f -> write_float buf f
  | String s | Raw_bstr s -> write_text buf s
  | Data d | Ip d -> write_bytes buf d
  | Decimal d -> Decimal.to_n d |> write_int buf
  | Ratio (n, d) -> write_array_head buf 2; write_int buf n; write_uint buf d
  | Percent d -> Decimal.to_n d |> write_int buf
  | Timestamp ts -> write_int buf ts
  | Date d ->
    write_array_head buf 3;
    write_uint buf d.year;
    write_uint buf d.month;
    write_uint buf d.day
  | Datetime dt ->
    write_array_head buf 5;
    write_uint buf dt.year;
    write_uint buf dt.month;
    write_uint buf dt.day;
    write_uint buf dt.hour;
    write_uint buf dt.minute
  | Timespan (a, b, c) ->
    write_array_head buf 3; write_int buf a; write_int buf b; write_int buf c
  | Code s
  | Language s
  | Country s
  | Subdivision s
  | Currency s
  | Tax_code s
  | Unit s -> write_text buf s
  | Text tm -> write_strmap write_text buf tm
  | Amount (d, opt) -> (
    let dec = Decimal.to_n d in
    match opt with
    | None -> write_int buf dec
    | Some c -> write_array_head buf 2; write_int buf dec; write_text buf c
  )
  | Tax (d, tax, curr) -> (
    let dec = Decimal.to_n d in
    match curr with
    | Some c ->
      write_array_head buf 3;
      write_int buf dec;
      write_text buf tax;
      write_text buf c
    | None -> write_array_head buf 2; write_int buf dec; write_text buf tax
  )
  | Quantity (d, opt) -> (
    let dec = Decimal.to_n d in
    match opt with
    | None -> write_int buf dec
    | Some u -> write_array_head buf 2; write_int buf dec; write_text buf u
  )
  | Subnet (ip, len) ->
    write_array_head buf 2; write_bytes buf ip; write_int buf len
  | Coords (lat, lon) ->
    write_array_head buf 2; write_float buf lat; write_float buf lon
  | Strmap sm -> write_strmap (encode_val ctx) buf sm
  | Uintmap im -> write_uintmap (encode_val ctx) buf im
  | List l | Series ([] as l) -> write_array (encode_val ctx) buf l
  | Ndarray (shape, values) ->
    let len = 1 + Array.length values in
    write_array_open buf len;
    write_array write_int buf shape;
    Array.iter (encode_val ctx buf) values;
    write_array_close buf len
  | Enum (schema, s) | Variant (schema, s, []) ->
    Context.lookup_id ctx schema.path s |> write_int buf
  | Variant (schema, s, l) ->
    write_array_head buf (1 + List.length l);
    Context.lookup_id ctx schema.path s |> write_int buf;
    List.iter (encode_val ctx buf) l
  | Record (schema, sm) ->
    let idx = Context.lookup ctx schema.path in
    let index_map k v acc = IntMap.add (Context.idx_id ctx idx k) v acc in
    let im = StringMap.fold index_map sm IntMap.empty in
    let len = IntMap.cardinal im in
    write_map_open buf len;
    IntMap.iter (fun id v -> write_int buf id; encode_val ctx buf v) im;
    write_map_close buf len
  | Series ((schema, _) :: _ as rl) ->
    let fields = series_fields ctx schema rl in
    let ids = List.map snd fields in
    let nf = List.length fields in
    let len = 1 + List.length rl in
    write_array_open buf len;
    write_array write_int buf ids;
    let write_record (_, sm) =
      write_array_open buf nf;
      List.iter (encode_val ctx buf) (series_row fields sm);
      write_array_close buf nf
    in
    List.iter write_record rl; write_array_close buf len
  | _ -> invalid_arg "Vof_cbor.encode_val: raw types cannot be converted"
;;

let encode_buf ctx ?(magic = false) ?(buf = Buffer.create 256) v =
  if magic then write_magic buf;
  encode_val ctx buf v;
  buf
;;

let encode_str ctx ?(magic = false) v =
  let buf = Buffer.create 256 in
  if magic then write_magic buf;
  encode_val ctx buf v;
  Buffer.contents buf
;;
