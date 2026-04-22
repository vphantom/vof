open Vof
open Vof_enc
open Vof_lib

let[@inline] add_byte buf n = Buffer.add_char buf (Char.chr (n land 0xFF))
let[@inline] add_le16 buf n = Buffer.add_uint16_le buf n
let[@inline] add_le32 buf n = Buffer.add_int32_le buf (Int32.of_int n)
let[@inline] add_le64 buf n = Buffer.add_int64_le buf (Int64.of_int n)

let write_uint buf = function
  | n when n < 0 -> invalid_arg "vof_bin: write_uint: negative argument"
  | n when n < 0x80 -> add_byte buf n
  | n when n < 0x4000 ->
    add_byte buf (n land 0x3F lor 0x80);
    add_byte buf (n lsr 6)
  | n when n < 0x10_0000 ->
    add_byte buf (n land 0x0F lor 0xC0);
    add_le16 buf (n lsr 4)
  | n when n < 0x800_0000 ->
    add_byte buf (n land 0x07 lor 0xD0);
    let v = n lsr 3 in
    add_le16 buf (v land 0xFFFF);
    add_byte buf (v lsr 16)
  | n when n < 0x1_0000_0000 -> add_byte buf 216; add_le32 buf n
  | n when n < 0x100_0000_0000 ->
    add_byte buf 217;
    add_le32 buf (n land 0xFFFF_FFFF);
    add_byte buf (n lsr 32)
  | n when n < 0x1_0000_0000_0000 ->
    add_byte buf 218;
    add_le32 buf (n land 0xFFFF_FFFF);
    add_le16 buf (n lsr 32)
  | n when n < 0x100_0000_0000_0000 ->
    add_byte buf 219;
    add_le32 buf (n land 0xFFFF_FFFF);
    let v = n lsr 32 in
    add_le16 buf (v land 0xFFFF);
    add_byte buf (v lsr 16)
  | n -> add_byte buf 220; add_le64 buf n
;;

let[@inline] zigzag_encode i = (i asr (Sys.int_size - 1)) lxor (i lsl 1)
let write_sint buf i = write_uint buf (zigzag_encode i)
let write_null buf = add_byte buf 255

let write_float buf f =
  match Vof_float16.bits_of_float_opt f with
  | Some h -> add_byte buf 221; add_le16 buf h
  | None ->
    let i32 = Int32.bits_of_float f in
    if Float.equal (Int32.float_of_bits i32) f
    then (
      add_byte buf 222;
      Buffer.add_int32_le buf i32
    )
    else (
      add_byte buf 223;
      Buffer.add_int64_le buf (Int64.bits_of_float f)
    )
;;

let write_string buf s =
  let len = String.length s in
  if len <= 7
  then (
    add_byte buf (224 + len);
    Buffer.add_string buf s
  )
  else (add_byte buf 248; write_uint buf len; Buffer.add_string buf s)
;;

let write_data buf d =
  add_byte buf 249;
  write_uint buf (Bytes.length d);
  Buffer.add_bytes buf d
;;

let write_gap buf n =
  if n <= 0
  then ()
  else if n <= 4
  then add_byte buf (243 + n)
  else (add_byte buf 252; write_uint buf n)
;;

let write_list_open buf n =
  if n < 0 then assert false;
  if n <= 11 then add_byte buf (232 + n) else add_byte buf 250
;;

let write_list_close buf n = if n > 11 then add_byte buf 251

let write_list f buf l =
  let rec len_upto n = function
    | [] -> n
    | _ :: rest -> if n > 11 then n else len_upto (n + 1) rest
  in
  let len = len_upto 0 l in
  write_list_open buf len;
  List.iter (f buf) l;
  write_list_close buf len
;;

let write_decimal buf d =
  let packed = Decimal.pack d in
  if packed >= 0
  then write_uint buf packed
  else (add_byte buf 253; write_uint buf (-packed))
;;

let write_strmap f buf sm =
  let len = StringMap.cardinal sm * 2 in
  write_list_open buf len;
  StringMap.iter (fun k v -> write_string buf k; f buf v) sm;
  write_list_close buf len
;;

let write_uintmap f buf im =
  let len = IntMap.cardinal im * 2 in
  write_list_open buf len;
  IntMap.iter (fun k v -> write_uint buf k; f buf v) im;
  write_list_close buf len
;;

let rec encode_val ctx buf = function
  | Null -> write_null buf
  | Bool b -> write_uint buf (if b then 1 else 0)
  | Int i -> write_sint buf i
  | Uint i -> write_uint buf i
  | Float f -> write_float buf f
  | Data d | Ip d -> write_data buf d
  | Decimal d | Percent d -> write_decimal buf d
  | Ratio (n, d) ->
    write_list_open buf 2;
    write_sint buf n;
    write_uint buf d;
    write_list_close buf 2
  | Timestamp ts -> Timestamp.pack ts |> write_sint buf
  | Date d -> Date.pack (d.year, d.month, d.day) |> write_uint buf
  | Datetime dt ->
    Datetime.pack (dt.year, dt.month, dt.day, dt.hour, dt.minute)
    |> write_uint buf
  | Timespan (a, b, c) ->
    write_list_open buf 3;
    write_sint buf a;
    write_sint buf b;
    write_sint buf c;
    write_list_close buf 3
  | String s
  | Raw_bstr s
  | Code s
  | Language s
  | Country s
  | Subdivision s
  | Currency s
  | Tax_code s
  | Unit s -> write_string buf s
  | Text tm -> write_strmap write_string buf tm
  | Amount (d, opt) | Quantity (d, opt) -> (
    match opt with
    | None -> write_decimal buf d
    | Some s ->
      write_list_open buf 2;
      write_decimal buf d;
      write_string buf s;
      write_list_close buf 2
  )
  | Tax (d, tax, curr) -> (
    match curr with
    | Some c ->
      write_list_open buf 3;
      write_decimal buf d;
      write_string buf tax;
      write_string buf c;
      write_list_close buf 3
    | None ->
      write_list_open buf 2;
      write_decimal buf d;
      write_string buf tax;
      write_list_close buf 2
  )
  | Subnet (ip, len) ->
    write_list_open buf 2;
    write_data buf ip;
    write_uint buf len;
    write_list_close buf 2
  | Coords (lat, lon) ->
    write_list_open buf 2;
    write_float buf lat;
    write_float buf lon;
    write_list_close buf 2
  | Strmap sm -> write_strmap (encode_val ctx) buf sm
  | Uintmap im -> write_uintmap (encode_val ctx) buf im
  | List l | Series ([] as l) -> write_list (encode_val ctx) buf l
  | Ndarray (shape, values) ->
    let len = 1 + Array.length values in
    write_list_open buf len;
    write_list write_uint buf shape;
    Array.iter (encode_val ctx buf) values;
    write_list_close buf len
  | Enum (schema, s) | Variant (schema, s, []) ->
    Context.lookup_id ctx schema.path s |> write_uint buf
  | Variant (schema, s, l) ->
    let len = 1 + List.length l in
    write_list_open buf len;
    Context.lookup_id ctx schema.path s |> write_uint buf;
    List.iter (encode_val ctx buf) l;
    write_list_close buf len
  | Record (schema, sm) ->
    let idx = Context.lookup ctx schema.path in
    let index_map k v acc = IntMap.add (Context.idx_id ctx idx k) v acc in
    let im = StringMap.fold index_map sm IntMap.empty in
    let last = ref (-1) in
    let incr_len id _ acc =
      let items = if id = !last + 1 then 1 else 2 in
      last := id;
      acc + items
    in
    let len = IntMap.fold incr_len im 0 in
    write_list_open buf len;
    last := -1;
    let write_field id v =
      let gap = id - !last - 1 in
      if gap > 0 then write_gap buf gap;
      encode_val ctx buf v;
      last := id
    in
    IntMap.iter write_field im; write_list_close buf len
  | Series ((schema, _) :: _ as rl) ->
    let fields = series_fields ctx schema rl in
    let ids = List.map snd fields in
    let len = 1 + (List.length rl * List.length fields) in
    write_list_open buf len;
    write_list (fun buf i -> write_uint buf i) buf ids;
    let write_record (_, sm) =
      List.iter (encode_val ctx buf) (series_row fields sm)
    in
    List.iter write_record rl; write_list_close buf len
  | Raw_gap g -> write_gap buf g
  | _ -> invalid_arg "vof_bin: encode_val: raw types cannot be converted"
;;

let encode_buf ctx ?(buf = Buffer.create 256) v = encode_val ctx buf v; buf

let encode_str ctx v =
  let buf = Buffer.create 256 in
  encode_val ctx buf v; Buffer.contents buf
;;

let decode ?(pos = 0) ?len src =
  let len = Option.value len ~default:(String.length src - pos) in
  if pos < 0 || len <= 0 || pos + len > String.length src
  then invalid_arg "vof_bin: decode: out of range";
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
  let[@inline] read_le16 () =
    let pos = !p in
    if pos + 2 > limit then raise_notrace Exit;
    p := pos + 2;
    Bytes.get_uint16_le raw pos
  in
  let[@inline] read_le32 () =
    let pos = !p in
    if pos + 4 > limit then raise_notrace Exit;
    p := pos + 4;
    Int32.to_int (Bytes.get_int32_le raw pos) land 0xFFFF_FFFF
  in
  let read_le64_capped () =
    let pos = !p in
    if pos + 8 > limit then raise_notrace Exit;
    p := pos + 8;
    let n = Bytes.get_int64_le raw pos in
    if n < 0L || n > Int64.of_int max_int then raise_notrace Exit;
    Int64.to_int n
  in
  let[@inline] slice n =
    let pos = !p in
    if n < 0 || pos + n > limit then raise_notrace Exit;
    p := pos + n;
    String.sub src pos n
  in
  let read_int_rest = function
    | n when n < 128 -> n
    | n when n < 192 ->
      let b = read_byte () in
      (b lsl 6) lor (n - 128)
    | n when n < 208 ->
      let w = read_le16 () in
      (w lsl 4) lor (n - 192)
    | n when n < 216 ->
      let lo = read_le16 () in
      let hi = read_byte () in
      ((lo lor (hi lsl 16)) lsl 3) lor (n - 208)
    | 216 -> read_le32 ()
    | 217 ->
      let lo = read_le32 () in
      let hi = read_byte () in
      lo lor (hi lsl 32)
    | 218 ->
      let lo = read_le32 () in
      let hi = read_le16 () in
      lo lor (hi lsl 32)
    | 219 ->
      let lo = read_le32 () in
      let mid = read_le16 () in
      let hi = read_byte () in
      lo lor (mid lsl 32) lor (hi lsl 48)
    | 220 -> read_le64_capped ()
    | _ -> raise_notrace Exit
  in
  let read_uint () =
    let c = read_byte () in
    if c >= 221 then raise_notrace Exit;
    read_int_rest c
  in
  let rec item () =
    let c = read_byte () in
    match c with
    | n when n < 221 -> Raw_int (read_int_rest c)
    | 221 -> Float (Vof_float16.float_of_bits (read_le16 ()))
    | 222 ->
      let pos = !p in
      if pos + 4 > limit then raise_notrace Exit;
      p := pos + 4;
      Float (Int32.float_of_bits (Bytes.get_int32_le raw pos))
    | 223 ->
      let pos = !p in
      if pos + 8 > limit then raise_notrace Exit;
      p := pos + 8;
      Float (Int64.float_of_bits (Bytes.get_int64_le raw pos))
    | n when n < 232 -> Raw_bstr (slice (c - 224))
    | n when n < 244 -> Raw_list (List.init (c - 232) (fun _ -> item ()))
    | n when n < 248 -> Raw_gap (c - 243)
    | 248 | 249 -> Raw_bstr (slice (read_uint ()))
    | 250 ->
      let[@tail_mod_cons] rec read_open () =
        if peek () = 251
        then (incr p; [])
        else (
          let v = item () in
          v :: read_open ()
        )
      in
      Raw_list (read_open ())
    | 251 -> raise_notrace Exit
    | 252 -> Raw_gap (read_uint ())
    | 253 -> Raw_tag (-1, item ())
    | 254 ->
      let t = read_uint () in
      Raw_tag (t, item ())
    | _ -> Null
  in
  try Some (item (), !p) with Exit -> None
;;
