#include <assert.h>

#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libswscale/swscale.h>
#include <libavutil/pixfmt.h>

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
  AVFormatContext*   outputCtx;
  char*              filename;
};

struct Stream {
  struct Context*    ctx;
  AVStream*          avstream;
  struct SwsContext* swsCtx;
};

#define USER_PIXFORMAT AV_PIX_FMT_RGB32

value
ffmpeg_create(value filename_)
{
  CAMLparam1(filename_);

  av_register_all(); // this is fast to redo
  
  struct Context* ctx = malloc(sizeof(struct Context));
  ctx->filename = strdup((char*) filename_);
    
  int ret;
  caml_enter_blocking_section();
  ret = avformat_alloc_output_context2(&ctx->outputCtx, NULL, NULL, (char*) filename_);
  assert(ret >= 0);

  caml_leave_blocking_section();
  CAMLreturn((value) ctx);
}

value
ffmpeg_open(value ctx_)
{
  CAMLparam1(ctx_);
  struct Context* ctx = (void*) ctx_;
  int ret;
  caml_enter_blocking_section();
  ret = avio_open(&ctx->outputCtx->pb, ctx->filename, AVIO_FLAG_WRITE);
  assert(ret >= 0);

  ret = avformat_write_header(ctx->outputCtx, NULL);
  caml_leave_blocking_section();
  assert(ret >= 0);
  CAMLreturn(Val_unit);
}


value
ffmpeg_close(value ctx_)
{
  CAMLparam1(ctx_);
  struct Context* ctx = (void*) ctx_;

  caml_enter_blocking_section();
  av_write_trailer(ctx->outputCtx);
  //avcodec_close(ctx->avstream->codec); ??
  avformat_free_context(ctx->outputCtx);
  free(ctx);
  caml_leave_blocking_section();
  CAMLreturn(Val_unit);
}

value
ffmpeg_write(value stream_, value rgbaFrame_)
{
  CAMLparam2(stream_, rgbaFrame_);
  struct Stream* stream = (void*) stream_;
  AVFrame* rgbaFrame = (void*) rgbaFrame_;
  int ret;
  AVFrame* yuvFrame = av_frame_alloc();
  assert(yuvFrame);

  yuvFrame->format = AV_PIX_FMT_YUV420P;
  yuvFrame->width = rgbaFrame->width;
  yuvFrame->height = rgbaFrame->height;

  ret = av_frame_get_buffer(yuvFrame, 32);
  assert(ret >= 0);

  ret = av_frame_make_writable(yuvFrame);
  assert(ret >= 0);

  yuvFrame->pts = rgbaFrame->pts;

  caml_enter_blocking_section();
    
  sws_scale(stream->swsCtx,
            (const uint8_t * const *) rgbaFrame->data,
            rgbaFrame->linesize,
            0, stream->avstream->codec->height, yuvFrame->data, yuvFrame->linesize);
    
  AVPacket packet = { 0 };
  av_init_packet(&packet);
  int gotIt = 0;
  ret = avcodec_encode_video2(stream->avstream->codec, &packet, yuvFrame, &gotIt);
  assert(ret >= 0);
  if (gotIt) {
    packet.stream_index = 0;
    ret = av_interleaved_write_frame(stream->ctx->outputCtx, &packet);
    assert(ret >= 0);
  }

  av_frame_free(&yuvFrame);

  caml_leave_blocking_section();

  CAMLreturn(Val_unit);
}

value
ffmpeg_stream_new_video(value ctx_, value video_info_)
{
  CAMLparam2(ctx_, video_info_);
  struct Context* ctx = (void*) ctx_;
  AVCodec* codec = avcodec_find_encoder(AV_CODEC_ID_H264);
  struct Stream* stream = malloc(sizeof(struct Stream));
  int ret;

  stream->ctx = ctx;
  stream->avstream = avformat_new_stream(ctx->outputCtx, codec);

  stream->avstream->codec->codec_id = AV_CODEC_ID_H264;
  /* stream->avstream->codec->rc_min_rate = 50000; */
  /* stream->avstream->codec->rc_max_rate = 200000; */
  /* stream->avstream->codec->bit_rate = 10000; */
  stream->avstream->codec->width    = Int_val(Field(video_info_, 0));
  stream->avstream->codec->height   = Int_val(Field(video_info_, 1));
  stream->avstream->codec->pix_fmt  = AV_PIX_FMT_YUV420P;
  //stream->avstream->codec->gop_size = 30;

  stream->avstream->codec->flags   |= AV_CODEC_FLAG_GLOBAL_HEADER;

  stream->avstream->time_base = (AVRational) {1, 10000};

  AVDictionary* codecOpts = NULL;
  /* av_dict_set(&codecOpts, "profile", "baseline", 0); */
  /* av_dict_set(&codecOpts, "crf", "3", 0); */
  /* av_dict_set(&codecOpts, "vbr", "1", 0); */
  //av_dict_set(&codecOpts, "x264-params", "bitrate=2", 0);
  //av_dict_set(&codecOpts, "x264-params", "crf=40:keyint=60:vbv_bufsize=40000:vbv_maxrate=150000", 0);
  av_dict_set(&codecOpts, "x264-params", "crf=36:keyint=60", 0);

  caml_enter_blocking_section();
  ret = avcodec_open2(stream->avstream->codec, codec, &codecOpts);
  assert(ret >= 0);

  assert(stream->avstream->codec->pix_fmt == AV_PIX_FMT_YUV420P);

  stream->swsCtx =
    sws_getContext(stream->avstream->codec->width, stream->avstream->codec->height, USER_PIXFORMAT,
                   stream->avstream->codec->width, stream->avstream->codec->height, stream->avstream->codec->pix_fmt,
                   0, NULL, NULL, NULL);
  caml_leave_blocking_section();

  CAMLreturn((value) stream);
}

value
ffmpeg_stream_new(value ctx_, value media_kind_)
{
  CAMLparam2(ctx_, media_kind_);
  CAMLlocal1(ret);

  if (Tag_val(media_kind_) == 0) {
    ret = ffmpeg_stream_new_video(ctx_, Field(media_kind_, 0));
  }

  CAMLreturn(ret);
}

value
ffmpeg_stream_close(value stream_)
{
  CAMLparam1(stream_);
  struct Stream* stream = (struct Stream*) stream_;

  if (stream->avstream->codec->flags & AV_CODEC_CAP_DELAY) {
    int gotIt;
    AVPacket packet = { 0 };
    do {
      int ret = avcodec_encode_video2(stream->avstream->codec, &packet, NULL, &gotIt);
      assert(ret >= 0);
      if (gotIt) {
        packet.stream_index = 0;
        ret = av_interleaved_write_frame(stream->ctx->outputCtx, &packet);
        assert(ret >= 0);
      }
    } while (gotIt);
  }

  avcodec_close(stream->avstream->codec);
  if (stream->swsCtx) {
    sws_freeContext(stream->swsCtx);
  }

  CAMLreturn(Val_unit);
}

value
ffmpeg_frame_new(value stream_, value pts_)
{
  CAMLparam2(stream_, pts_);
  struct Stream* stream = (void*) stream_;
  double pts = Double_val(pts_);
  AVFrame* frame = av_frame_alloc();
  frame->format = USER_PIXFORMAT; // 0xrrggbbaa
  frame->width = stream->avstream->codec->width;
  frame->height = stream->avstream->codec->height;

  int ret;
  ret = av_frame_get_buffer(frame, 32);
  assert(ret >= 0);

  ret = av_frame_make_writable(frame);
  assert(ret >= 0);

  frame->pts = pts = (int64_t) (stream->avstream->time_base.den * pts);

  CAMLreturn((value) frame);
}

value
ffmpeg_frame_buffer(value frame_)
{
  CAMLparam1(frame_);
  AVFrame* frame = ((AVFrame*) frame_);
  CAMLreturn(caml_ba_alloc_dims(CAML_BA_INT32, 1,
                                frame->data[0],
                                frame->linesize[0] * frame->height));
}

value
ffmpeg_frame_free(value frame)
{
  CAMLparam1(frame);
  av_frame_free((void*) &frame);
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
