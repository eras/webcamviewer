#include <assert.h>

#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libswscale/swscale.h>
#include <libavutil/pixfmt.h>
#include <libswresample/swresample.h>
#include <libavutil/channel_layout.h>
#include <libavutil/opt.h>

#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <caml/bigarray.h>
#include <caml/threads.h>

void
rgbaFillBox(AVFrame* frame, int x0, int y0, int x1, int y1)
{
  for (int y = y0; y <= y1; ++y) {
    for (int x = x0; x <= x1; ++x) {
      frame->data[0][y * frame->linesize[0] + x * 4 + 0] = 255;
      frame->data[0][y * frame->linesize[0] + x * 4 + 1] = 255;
      frame->data[0][y * frame->linesize[0] + x * 4 + 2] = 255;
      frame->data[0][y * frame->linesize[0] + x * 4 + 3] = 0;
    }
  }
}

void
rgbaClear(AVFrame* frame)
{
  memset(frame->data[0], 0, frame->height * frame->linesize[0]);
}

struct Context {
  AVFormatContext*   fmtCtx;
  char*              filename;
};

static struct custom_operations context_ops = {
  "ffmpeg.Context",
  custom_finalize_default,
  custom_compare_default,
  custom_hash_default,
  custom_serialize_default,
  custom_deserialize_default
};

struct Context*
Context_val(value v)
{
  return (struct Context *) Data_custom_val(v);
}

enum StreamType {
  STREAM_VIDEO,
  STREAM_AUDIO
};

struct StreamAux {
  enum StreamType    type;
  AVStream*          avstream;
  struct SwsContext* swsCtx;
  struct SwrContext* swrCtx;
};

#define StreamAux_val(v) ((struct StreamAux *) Data_custom_val(v))

#define StreamSize              2
#define Stream_context_direct_val(v)   Field(v, 0)

struct Context*
Stream_context_val(value v)
{
  return Context_val(Stream_context_direct_val(v));
}

#define Stream_aux_direct_val(v) Field(v, 1)
//#define Stream_aux_val(v)       Stream_aux_val(Stream_aux_direct_val(v))

struct StreamAux*
Stream_aux_val(value v)
{
  return StreamAux_val(Stream_aux_direct_val(v));
}

static struct custom_operations streamaux_ops = {
  "ffmpeg.StreamAux",
  custom_finalize_default,
  custom_compare_default,
  custom_hash_default,
  custom_serialize_default,
  custom_deserialize_default
};

#define Stream_val(v) ((struct Stream *) Data_custom_val(v))

static struct custom_operations avframe_ops = {
  "ffmpeg.AVFrame",
  custom_finalize_default,
  custom_compare_default,
  custom_hash_default,
  custom_serialize_default,
  custom_deserialize_default
};

#define AVFrame_val(v) (*((struct AVFrame **) Data_custom_val(v)))

#define AVStream_val(v) (*((struct AVStream **) Data_custom_val(v)))

#define USER_PIXFORMAT AV_PIX_FMT_RGB32

static
value
wrap_ptr(struct custom_operations *custom, void* ptr)
{
  value v = alloc_custom(custom, sizeof(void*), 0, 1);
  * (void**) Data_custom_val(v) = ptr;
  return v;
}

value
ffmpeg_create(value filename_)
{
  CAMLparam1(filename_);

  av_register_all(); // this is fast to redo

  value ctx = caml_alloc_custom(&context_ops, sizeof(struct Context), 0, 1);
  Context_val(ctx)->filename = strdup((char*) filename_);

  int ret;
  AVFormatContext* fmtCtx;
  caml_enter_blocking_section();
  ret = avformat_alloc_output_context2(&fmtCtx, NULL, NULL, (char*) filename_);
  assert(ret >= 0);

  caml_leave_blocking_section();
  Context_val(ctx)->fmtCtx = fmtCtx;
  CAMLreturn(ctx);
}

value
ffmpeg_open_input(value filename_)
{
  CAMLparam1(filename_);

  av_register_all(); // this is fast to redo

  value ctx = caml_alloc_custom(&context_ops, sizeof(struct Context), 0, 1);
  Context_val(ctx)->filename = strdup((char*) filename_);

  int ret;
  AVFormatContext* fmtCtx;
  char* filename = Context_val(ctx)->filename;
  caml_enter_blocking_section();
  ret = avformat_open_input(&fmtCtx, filename, NULL, NULL);
  assert(ret >= 0);

  ret = avformat_find_stream_info(fmtCtx, NULL);
  assert(ret >= 0);

  caml_leave_blocking_section();
  Context_val(ctx)->fmtCtx = fmtCtx;
  CAMLreturn(ctx);
}

value
ffmpeg_open(value ctx)
{
  CAMLparam1(ctx);
  int ret;
  char* filename = Context_val(ctx)->filename;
  AVIOContext** pb = &Context_val(ctx)->fmtCtx->pb;
  AVFormatContext* fmtCtx = Context_val(ctx)->fmtCtx;

  caml_enter_blocking_section();
  ret = avio_open(pb, filename, AVIO_FLAG_WRITE);
  assert(ret >= 0);

  ret = avformat_write_header(fmtCtx, NULL);
  caml_leave_blocking_section();
  assert(ret >= 0);
  CAMLreturn(Val_unit);
}


value
ffmpeg_close(value ctx)
{
  CAMLparam1(ctx);

  AVFormatContext* fmtCtx = Context_val(ctx)->fmtCtx;
  caml_enter_blocking_section();
  av_write_trailer(fmtCtx);
  //avcodec_close(Context_val(ctx)->avstream->codec); ??
  avformat_free_context(fmtCtx);
  caml_leave_blocking_section();
  Context_val(ctx)->fmtCtx = NULL;
  free(Context_val(ctx)->filename);
  Context_val(ctx)->filename = NULL;
  CAMLreturn(Val_unit);
}

value
ffmpeg_write(value stream, value rgbaFrame)
{
  CAMLparam2(stream, rgbaFrame);
  int ret;
  AVFrame* yuvFrame = av_frame_alloc();
  assert(yuvFrame);

  struct StreamAux streamAux = *Stream_aux_val(stream);
  AVFormatContext* fmtCtx = Stream_context_val(stream)->fmtCtx;

  yuvFrame->format = AV_PIX_FMT_YUV420P;
  yuvFrame->width = AVFrame_val(rgbaFrame)->width;
  yuvFrame->height = AVFrame_val(rgbaFrame)->height;

  ret = av_frame_get_buffer(yuvFrame, 32);
  assert(ret >= 0);

  ret = av_frame_make_writable(yuvFrame);
  assert(ret >= 0);

  yuvFrame->pts = AVFrame_val(rgbaFrame)->pts;

  caml_enter_blocking_section();

  sws_scale(streamAux.swsCtx,
            (const uint8_t * const *) AVFrame_val(rgbaFrame)->data,
            AVFrame_val(rgbaFrame)->linesize,
            0, streamAux.avstream->codec->height, yuvFrame->data, yuvFrame->linesize);

  AVPacket packet = { 0 };
  av_init_packet(&packet);
  int gotIt = 0;
  ret = avcodec_encode_video2(streamAux.avstream->codec, &packet, yuvFrame, &gotIt);
  assert(ret >= 0);
  if (gotIt) {
    packet.stream_index = 0;
    ret = av_interleaved_write_frame(fmtCtx, &packet);
    assert(ret >= 0);
  }

  av_frame_free(&yuvFrame);

  caml_leave_blocking_section();

  CAMLreturn(Val_unit);
}

value
ffmpeg_stream_new_video(value ctx, value video_info_)
{
  CAMLparam2(ctx, video_info_);
  AVCodec* codec = avcodec_find_encoder(AV_CODEC_ID_H264);
  value stream = caml_alloc_tuple(StreamSize);
  int ret;

  Stream_aux_direct_val(stream) = caml_alloc_custom(&streamaux_ops, sizeof(struct StreamAux), 0, 1);
  Stream_aux_val(stream)->type = Val_int(STREAM_VIDEO);
  Stream_context_direct_val(stream) = ctx;
  Stream_aux_val(stream)->avstream = avformat_new_stream(Context_val(ctx)->fmtCtx, codec);

  Stream_aux_val(stream)->avstream->codec->codec_id = AV_CODEC_ID_H264;
  /* Stream_aux_val(stream)->avstream->codec->rc_min_rate = 50000; */
  /* Stream_aux_val(stream)->avstream->codec->rc_max_rate = 200000; */
  /* Stream_aux_val(stream)->avstream->codec->bit_rate = 10000; */
  Stream_aux_val(stream)->avstream->codec->width    = Int_val(Field(video_info_, 0));
  Stream_aux_val(stream)->avstream->codec->height   = Int_val(Field(video_info_, 1));
  Stream_aux_val(stream)->avstream->codec->pix_fmt  = AV_PIX_FMT_YUV420P;
  //Stream_aux_val(stream)->avstream->codec->gop_size = 30;

  if (Context_val(ctx)->fmtCtx->oformat->flags & AVFMT_GLOBALHEADER) {
    Stream_aux_val(stream)->avstream->codec->flags   |= AV_CODEC_FLAG_GLOBAL_HEADER;
  }

  Stream_aux_val(stream)->avstream->time_base = (AVRational) {1, 10000};

  AVDictionary* codecOpts = NULL;
  /* av_dict_set(&codecOpts, "profile", "baseline", 0); */
  /* av_dict_set(&codecOpts, "crf", "3", 0); */
  /* av_dict_set(&codecOpts, "vbr", "1", 0); */
  //av_dict_set(&codecOpts, "x264-params", "bitrate=2", 0);
  //av_dict_set(&codecOpts, "x264-params", "crf=40:keyint=60:vbv_bufsize=40000:vbv_maxrate=150000", 0);
  av_dict_set(&codecOpts, "x264-params", "crf=36:keyint=60", 0);

  //caml_enter_blocking_section();
  ret = avcodec_open2(Stream_aux_val(stream)->avstream->codec, codec, &codecOpts);
  assert(ret >= 0);

  assert(Stream_aux_val(stream)->avstream->codec->pix_fmt == AV_PIX_FMT_YUV420P);

  Stream_aux_val(stream)->swsCtx =
    sws_getContext(Stream_aux_val(stream)->avstream->codec->width, Stream_aux_val(stream)->avstream->codec->height, USER_PIXFORMAT,
                   Stream_aux_val(stream)->avstream->codec->width, Stream_aux_val(stream)->avstream->codec->height, Stream_aux_val(stream)->avstream->codec->pix_fmt,
                   0, NULL, NULL, NULL);
  //caml_leave_blocking_section();

  CAMLreturn((value) stream);
}

value
ffmpeg_stream_new_audio(value ctx, value audio_info_)
{
  CAMLparam2(ctx, audio_info_);
  AVCodec* codec = avcodec_find_encoder(AV_CODEC_ID_AAC);
  value stream = caml_alloc_tuple(StreamSize);
  int ret;

  Stream_aux_direct_val(stream) = caml_alloc_custom(&streamaux_ops, sizeof(struct StreamAux), 0, 1);
  Stream_aux_val(stream)->type = Val_int(STREAM_AUDIO);
  Stream_context_direct_val(stream) = ctx;
  Stream_aux_val(stream)->avstream = avformat_new_stream(Context_val(ctx)->fmtCtx, codec);

  Stream_aux_val(stream)->avstream->codec->codec_id    = AV_CODEC_ID_AAC;
  Stream_aux_val(stream)->avstream->codec->sample_rate = Int_val(Field(audio_info_, 0));
  Stream_aux_val(stream)->avstream->codec->channels    = Int_val(Field(audio_info_, 1));
  Stream_aux_val(stream)->avstream->codec->sample_fmt  = codec->sample_fmts ? codec->sample_fmts[0] : AV_SAMPLE_FMT_FLTP;
  Stream_aux_val(stream)->avstream->codec->channel_layout = AV_CH_LAYOUT_STEREO;
  //Stream_aux_val(stream)->avstream->codec->channels    = av_get_channel_layout_nb_channels(Stream_aux_val(stream)->avstream->codec->channel_layout);

  if (Context_val(ctx)->fmtCtx->oformat->flags & AVFMT_GLOBALHEADER) {
    Stream_aux_val(stream)->avstream->codec->flags   |= AV_CODEC_FLAG_GLOBAL_HEADER;
  }

  Stream_aux_val(stream)->avstream->time_base = (AVRational) {1, 10000};

  AVDictionary* codecOpts = NULL;

  //caml_enter_blocking_section();
  ret = avcodec_open2(Stream_aux_val(stream)->avstream->codec, codec, &codecOpts);
  assert(ret >= 0);

  if (Stream_aux_val(stream)->avstream->codec->sample_fmt != AV_SAMPLE_FMT_S16) {
    Stream_aux_val(stream)->swrCtx = swr_alloc();
    assert(Stream_aux_val(stream)->swrCtx);

    av_opt_set_int       (Stream_aux_val(stream)->swrCtx, "in_channel_count",   Stream_aux_val(stream)->avstream->codec->channels, 0);
    av_opt_set_int       (Stream_aux_val(stream)->swrCtx, "in_sample_rate",     Stream_aux_val(stream)->avstream->codec->sample_rate, 0);
    av_opt_set_sample_fmt(Stream_aux_val(stream)->swrCtx, "in_sample_fmt",      AV_SAMPLE_FMT_S16, 0);
    av_opt_set_int       (Stream_aux_val(stream)->swrCtx, "out_channel_count",  Stream_aux_val(stream)->avstream->codec->channels, 0);
    av_opt_set_int       (Stream_aux_val(stream)->swrCtx, "out_sample_rate",    Stream_aux_val(stream)->avstream->codec->sample_rate, 0);
    av_opt_set_sample_fmt(Stream_aux_val(stream)->swrCtx, "out_sample_fmt",     Stream_aux_val(stream)->avstream->codec->sample_fmt, 0);
  }
  
  //caml_leave_blocking_section();

  CAMLreturn((value) stream);
}

value
ffmpeg_stream_new(value ctx, value media_kind_)
{
  CAMLparam2(ctx, media_kind_);
  CAMLlocal1(ret);

  switch (Tag_val(media_kind_)) {
  case 0: {
    ret = ffmpeg_stream_new_video(ctx, Field(media_kind_, 0));
  } break;
  case 1: {
    ret = ffmpeg_stream_new_audio(ctx, Field(media_kind_, 0));
  } break;
  }
  
  CAMLreturn(ret);
}

value
ffmpeg_stream_close(value stream)
{
  CAMLparam1(stream);

  if (Stream_aux_val(stream)->avstream->codec->flags & AV_CODEC_CAP_DELAY) {
    int gotIt;
    AVPacket packet = { 0 };
    do {
      int ret = avcodec_encode_video2(Stream_aux_val(stream)->avstream->codec, &packet, NULL, &gotIt);
      assert(ret >= 0);
      if (gotIt) {
        packet.stream_index = 0;
        ret = av_interleaved_write_frame(Stream_context_val(stream)->fmtCtx, &packet);
        assert(ret >= 0);
      }
    } while (gotIt);
  }

  avcodec_close(Stream_aux_val(stream)->avstream->codec);
  if (Stream_aux_val(stream)->swsCtx) {
    sws_freeContext(Stream_aux_val(stream)->swsCtx);
  }

  CAMLreturn(Val_unit);
}

value
ffmpeg_frame_new(value stream, value pts_)
{
  CAMLparam2(stream, pts_);
  double pts = Double_val(pts_);
  value frame = wrap_ptr(&avframe_ops, av_frame_alloc());
  AVFrame_val(frame)->format = USER_PIXFORMAT; // 0xrrggbbaa
  AVFrame_val(frame)->width = Stream_aux_val(stream)->avstream->codec->width;
  AVFrame_val(frame)->height = Stream_aux_val(stream)->avstream->codec->height;

  int ret;
  ret = av_frame_get_buffer(AVFrame_val(frame), 32);
  assert(ret >= 0);

  ret = av_frame_make_writable(AVFrame_val(frame));
  assert(ret >= 0);

  AVFrame_val(frame)->pts = pts = (int64_t) (Stream_aux_val(stream)->avstream->time_base.den * pts);

  CAMLreturn((value) frame);
}

value
ffmpeg_frame_buffer(value frame)
{
  CAMLparam1(frame);
  CAMLreturn(caml_ba_alloc_dims(CAML_BA_INT32, 1,
                                AVFrame_val(frame)->data[0],
                                AVFrame_val(frame)->linesize[0] * AVFrame_val(frame)->height));
}

value
ffmpeg_frame_free(value frame)
{
  CAMLparam1(frame);
  AVFrame *ptr = AVFrame_val(frame);
  av_frame_free(&ptr);
  AVFrame_val(frame) = NULL;
  CAMLreturn(Val_unit);
}

value
ffmpeg_demo(value arg)
{
  CAMLlocal3(rgbaFrame, ctx, stream);

#if 0
  ctx = ffmpeg_create(caml_copy_string("foo.mp4"));
  stream = ffmpeg_new_Stream(caml_copy_string("foo.mp4"), Val_int(640), Val_int(480));
  ctx = ffmpeg_open(caml_copy_string("foo.mp4"), Val_int(640), Val_int(480));

  for (int c = 0; c < 400; ++c) {
    rgbaFrame = ffmpeg_frame_new(ctx, caml_copy_int64(100 * c));
    assert(rgbaFrame);

    rgbaClear((AVFrame*) rgbaFrame);
    rgbaFillBox((AVFrame*) rgbaFrame, 100 + 10 * c, 100, 200 + 10 * c, 200);

    ffmpeg_write(ctx, rgbaFrame);
    ffmpeg_frame_free(rgbaFrame);
  }
  ffmpeg_close(ctx);
#endif

  return Val_int(0);
}
