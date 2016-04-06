type 'rw context
type pts = float
type width = int
type height = int
type 'media_info frame
type video = {
  v_width  : int;
  v_height : int;
}
type audio = {
  a_samplerate : int;
  a_channels   : int;
  a_layout     : int option;
}
type data
type 'a media_new_info =
  | CreateVideo : video -> [`Video] media_new_info
  | CreateAudio : audio -> [`Audio] media_new_info
  | CreateData  : data  -> [`Data]  media_new_info
type 'a media_type =
  | Video : [`Video] media_type
  | Audio : [`Audio] media_type
  | Data  : [`Data]  media_type
type 'rw rw = [<`Read | `Write] as 'rw
type ('media_info, 'rw) stream constraint 'rw = [<`Read | `Write]
type 'format bitmap = (int32, Bigarray.int32_elt, Bigarray.c_layout) Bigarray.Array1.t

type avmedia_type =
| AVMEDIA_TYPE_UNKNOWN
| AVMEDIA_TYPE_VIDEO
| AVMEDIA_TYPE_AUDIO
| AVMEDIA_TYPE_DATA
| AVMEDIA_TYPE_SUBTITLE
| AVMEDIA_TYPE_ATTACHMENT
(* | AVMEDIA_TYPE_NB *)

let read = `Read
let write = `Write

type index = int

type ffmpeg_exception =
  | ContextAlloc
  | Open
  | FileIO
  | StreamInfo
  | WriteHeader
  | Memory
  | Logic
  | Encode

exception Exception of ffmpeg_exception * int
