open Vof

let series_fields ctx schema records =
  let idx = Context.lookup ctx schema.path in
  let collect acc (_, sm) =
    StringMap.fold (fun k _ a -> StringMap.add k () a) sm acc
  in
  let all = List.fold_left collect StringMap.empty records in
  let pairs =
    StringMap.fold
      (fun name () acc -> (name, Context.idx_id ctx idx name) :: acc)
      all []
  in
  List.sort (fun (_, a) (_, b) -> Int.compare a b) pairs
;;

let series_row fields sm =
  List.map
    (fun (name, _) ->
      match StringMap.find_opt name sm with
      | Some v -> v
      | None -> Null
    )
    fields
;;
