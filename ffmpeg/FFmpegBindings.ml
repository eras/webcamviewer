open Batteries
open FFmpegTypes

let make_mapper xs =
  let flipped = List.map (fun (a, b) -> (b, a)) xs in
  (flip List.assoc xs, flip List.assoc flipped)

module Types (S : Cstubs_structs.TYPE) =
struct
  let avmedia_type_unknown    = S.constant "AVMEDIA_TYPE_UNKNOWN" S.int64_t
  let avmedia_type_video      = S.constant "AVMEDIA_TYPE_VIDEO" S.int64_t
  let avmedia_type_audio      = S.constant "AVMEDIA_TYPE_AUDIO" S.int64_t
  let avmedia_type_data       = S.constant "AVMEDIA_TYPE_DATA" S.int64_t
  let avmedia_type_subtitle   = S.constant "AVMEDIA_TYPE_SUBTITLE" S.int64_t
  let avmedia_type_attachment = S.constant "AVMEDIA_TYPE_ATTACHMENT" S.int64_t
  (* let avmedia_type_nb         = S.constant "AVMEDIA_TYPE_NB" S.int64_t  *)

  (* let avmedia_type = S.enum "AVMediaType" [ *)
  (*     AVMEDIA_TYPE_UNKNOWN    , avmedia_type_unknown; *)
  (*     AVMEDIA_TYPE_VIDEO      , avmedia_type_video; *)
  (*     AVMEDIA_TYPE_AUDIO      , avmedia_type_audio; *)
  (*     AVMEDIA_TYPE_DATA       , avmedia_type_data; *)
  (*     AVMEDIA_TYPE_SUBTITLE   , avmedia_type_subtitle; *)
  (*     AVMEDIA_TYPE_ATTACHMENT , avmedia_type_attachment; *)
  (*     (\* AVMEDIA_TYPE_NB         , avmedia_type_nb; *\) *)
    (* ] *)
  let avmedia_type_to_c, avmedia_type_of_c  = make_mapper [
      AVMEDIA_TYPE_UNKNOWN    , avmedia_type_unknown;
      AVMEDIA_TYPE_VIDEO      , avmedia_type_video;
      AVMEDIA_TYPE_AUDIO      , avmedia_type_audio;
      AVMEDIA_TYPE_DATA       , avmedia_type_data;
      AVMEDIA_TYPE_SUBTITLE   , avmedia_type_subtitle;
      AVMEDIA_TYPE_ATTACHMENT , avmedia_type_attachment;
      (* AVMEDIA_TYPE_NB         , avmedia_type_nb; *)
    ]
end

