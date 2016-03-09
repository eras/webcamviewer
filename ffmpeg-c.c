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
  AVStream*          stream;
  struct SwsContext* swsCtx;
  int                width;
  int                height;
};

#define USER_PIXFORMAT AV_PIX_FMT_RGB32

value
ffmpeg_open(value filename_, value width_, value height_)
{
  CAMLparam3(filename_, width_, height_);

  av_register_all(); // this is fast to redo
  
  struct Context* ctx = malloc(sizeof(struct Context));
  int width = Int_val(width_);
  int height = Int_val(height_);
    
  int ret;
  avformat_alloc_output_context2(&ctx->outputCtx, NULL, NULL, (char*) filename_);

  
  ctx->width = width;
  ctx->height = height;
  
  AVCodec* codec = avcodec_find_encoder(AV_CODEC_ID_H264);
  ctx->stream = avformat_new_stream(ctx->outputCtx, codec);

  ctx->stream->codec->codec_id = AV_CODEC_ID_H264;
  /* ctx->stream->codec->rc_min_rate = 50000; */
  /* ctx->stream->codec->rc_max_rate = 200000; */
  /* ctx->stream->codec->bit_rate = 10000; */
  ctx->stream->codec->width    = ctx->width;
  ctx->stream->codec->height   = ctx->height;
  ctx->stream->codec->pix_fmt  = AV_PIX_FMT_YUV420P;
  //ctx->stream->codec->gop_size = 30;

  ctx->stream->codec->flags   |= AV_CODEC_FLAG_GLOBAL_HEADER;

  ctx->stream->time_base = (AVRational) {1, 10000};

  AVDictionary* codecOpts = NULL;
  /* av_dict_set(&codecOpts, "profile", "baseline", 0); */
  /* av_dict_set(&codecOpts, "crf", "3", 0); */
  /* av_dict_set(&codecOpts, "vbr", "1", 0); */
  //av_dict_set(&codecOpts, "x264-params", "bitrate=2", 0);
  //av_dict_set(&codecOpts, "x264-params", "crf=40:keyint=60:vbv_bufsize=40000:vbv_maxrate=150000", 0);
  av_dict_set(&codecOpts, "x264-params", "crf=36:keyint=60", 0);
  
  ret = avcodec_open2(ctx->stream->codec, codec, &codecOpts);
  assert(ret >= 0);
  
(ctx->stream->codec->pix_fmt == AV_PIX_FMT_YUV420P);
               
  ret = avio_open(&ctx->outputCtx->pb, (char*) filename_, AVIO_FLAG_WRITE);
  assert(ret >= 0);

  ret = avformat_write_header(ctx->outputCtx, NULL);
  assert(ret >= 0);

  ctx->swsCtx =
    sws_getContext(ctx->stream->codec->width, ctx->stream->codec->height, USER_PIXFORMAT,
                   ctx->stream->codec->width, ctx->stream->codec->height, ctx->stream->codec->pix_fmt,
                   0, NULL, NULL, NULL);

  CAMLreturn((value) ctx);
}

value
ffmpeg_close(value ctx_)
{
  CAMLparam1(ctx_);
  struct Context* ctx = (void*) ctx_; 
 av_write_trailer(ctx->outputCtx);
  avcodec_close(ctx->stream->codec);
  avformat_free_context(ctx->outputCtx);
  sws_freeContext(ctx->swsCtx);
  free(ctx);
  CAMLreturn(Val_unit);
}

value
ffmpeg_write(value ctx_, value rgbaFrame_)
{
  CAMLparam2(ctx_, rgbaFrame_);
  struct Context* ctx = (void*) ctx_;
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
    
  sws_scale(ctx->swsCtx,
            (const uint8_t * const *) rgbaFrame->data,
            rgbaFrame->linesize,
            0, ctx->stream->codec->height, yuvFrame->data, yuvFrame->linesize);
    
  AVPacket packet = { 0 };
  av_init_packet(&packet);
  int gotIt = 0;
  ret = avcodec_encode_video2(ctx->stream->codec, &packet, yuvFrame, &gotIt);
  assert(ret >= 0);
  if (gotIt) {
    packet.stream_index = 0;
    ret = av_interleaved_write_frame(ctx->outputCtx, &packet);
    assert(ret >= 0);
  }

  av_frame_free(&yuvFrame);

  caml_leave_blocking_section();

  CAMLreturn(Val_unit);
}

value
ffmpeg_frame_new(value ctx_, value pts_)
{
  CAMLparam2(ctx_, pts_);
  struct Context* ctx = (void*) ctx_;
  int64_t pts = Int64_val(pts_);
  AVFrame* frame = av_frame_alloc();
  frame->format = USER_PIXFORMAT; // 0xrrggbbaa
  frame->width = ctx->width;
  frame->height = ctx->height;

  int ret;
  ret = av_frame_get_buffer(frame, 32);
  assert(ret >= 0);

  ret = av_frame_make_writable(frame);
  assert(ret >= 0);

  frame->pts = pts;

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
  CAMLlocal2(rgbaFrame, ctx);
  
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

  return Val_int(0);
}
