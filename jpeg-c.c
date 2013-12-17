#include <stdlib.h>
#include <stdio.h>
#include <setjmp.h>
#include <assert.h>

#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <caml/bigarray.h>

#ifdef LIBJPEG
#include <jpeglib.h>

static void
ojpeg_init_source(j_decompress_ptr dec)
{
  (void) dec;
}

static boolean
ojpeg_fill_input_buffer(j_decompress_ptr dec)
{
  jpeg_abort_decompress(dec);
  return 0;
}

static void
ojpeg_skip_input_data(j_decompress_ptr dec, long ofs)
{
  dec->src->next_input_byte += ofs;
}

static boolean
ojpeg_resync_to_restart(j_decompress_ptr dec, int ofs)
{
  (void) dec;
  (void) ofs;
  return 0;
}

static void
ojpeg_term_source(j_decompress_ptr dec)
{
  (void) dec;
}

struct custom_jpeg_decompress_struct {
  struct jpeg_decompress_struct jpeg;
  jmp_buf decode_env;
};

static void
ojpeg_error_exit(j_common_ptr cinfo)
{
  struct custom_jpeg_decompress_struct* custom_dec = (void*) cinfo;
  longjmp(custom_dec->decode_env, 1);
}

value
jpeg_decode(value pixel_format, value frame)
{
  CAMLparam2(pixel_format, frame);
  CAMLlocal3(image, rgb_data, result_option);

  struct jpeg_source_mgr src;

  result_option = Val_int(0);

  void* orig = Data_bigarray_val(frame);
  src.next_input_byte	= orig;
  src.bytes_in_buffer	= Caml_ba_array_val(frame)->dim[0];
  src.init_source	= ojpeg_init_source;
  src.fill_input_buffer = &ojpeg_fill_input_buffer;
  src.skip_input_data	= &ojpeg_skip_input_data;
  src.resync_to_restart	= &ojpeg_resync_to_restart;
  src.term_source	= &ojpeg_term_source;

  struct custom_jpeg_decompress_struct custom_dec = {
    jpeg : { 0 }
  };
  struct jpeg_decompress_struct* dec = &custom_dec.jpeg;
  jpeg_create_decompress(dec);
  struct jpeg_error_mgr error;
  dec->err = jpeg_std_error(&error);
  dec->err->error_exit = &ojpeg_error_exit;
  dec->src = &src;

  image = caml_alloc_tuple(4);
  caml_modify(&Field(image, 2), pixel_format);
  if (setjmp(custom_dec.decode_env) == 0) {
    jpeg_read_header(dec, TRUE);

    jpeg_start_decompress(dec);

    int bytes_per_pixel = Int_val(Field(pixel_format, 0));

    int size = dec->output_width * dec->output_height * bytes_per_pixel;
    int pitch = dec->output_width * bytes_per_pixel;
    rgb_data = alloc_bigarray_dims(CAML_BA_UINT8 | CAML_BA_C_LAYOUT, 1,
				 NULL, size);
    caml_modify(&Field(image, 0), Val_int(dec->output_width));
    caml_modify(&Field(image, 1), Val_int(dec->output_height));
    JSAMPLE* begin = (void*) Data_bigarray_val(rgb_data);
    JSAMPLE* buffer = begin;
    const JSAMPLE* end = (void*) (((char*) Data_bigarray_val(rgb_data)) + size);

    if (setjmp(custom_dec.decode_env) == 0) {
      switch (bytes_per_pixel) {
      case 3: {
        while (dec->output_scanline < dec->output_height) {
          assert(buffer + pitch <= end);
          jpeg_read_scanlines(dec, &buffer, 1);
          buffer += pitch;
        }
      } break;
      case 4: {
        JSAMPLE tmp_buffer[dec->output_width * 3];
        JSAMPLE* tmp_buffer_ptr = tmp_buffer;
        while (dec->output_scanline < dec->output_height) {
          unsigned c;
          assert(buffer + pitch <= end);
          jpeg_read_scanlines(dec, &tmp_buffer_ptr, 1);
          JSAMPLE* src = tmp_buffer;
          JSAMPLE* dst = buffer;
          for (c = 0; c < dec->output_width; ++c) {
            *(dst++) = *(src++);
            *(dst++) = *(src++);
            *(dst++) = *(src++);
            *(dst++) = 0;
          }
          buffer += pitch;
        }
      } break;
      }
      jpeg_finish_decompress(dec);
    } else {
      // uh oh. well, just keep on going and zero the rest.
      printf("decoding error\n");
      while (buffer < end) {
	*buffer = 0;
	++buffer;
      }
    }
    result_option = caml_alloc(1, 0);
    Store_field(result_option, 0, image);
  } else {
    // uh oh. returning None
    printf("header decoding error\n");
  }
  caml_modify(&Field(image, 3), rgb_data);

  jpeg_destroy_decompress(dec);

  CAMLreturn(result_option);
}
#endif

#ifdef TURBOJPEG
#include <turbojpeg.h>

value
jpeg_decode(value pixel_format, value frame)
{
  CAMLparam2(pixel_format, frame);
  CAMLlocal3(image, rgb_data, result_option);

  tjhandle tj = tjInitDecompress();

  int width, height;
  int jpegSubsamp;

  unsigned char* data = Data_bigarray_val(frame);
  unsigned long data_size = Caml_ba_array_val(frame)->dim[0];

  result_option = Val_int(0);
  image = caml_alloc_tuple(4);
  caml_modify(&Field(image, 2), pixel_format);

  if (tjDecompressHeader2(tj, data, data_size, &width, &height, &jpegSubsamp) == 0) {
    int bytes_per_pixel = Int_val(Field(pixel_format, 0));
    int size = width * height * bytes_per_pixel;
    int pitch = width * bytes_per_pixel;
    enum TJPF tj_pixel_format;

    rgb_data = alloc_bigarray_dims(CAML_BA_UINT8 | CAML_BA_C_LAYOUT, 1,
                                   NULL, size);
    caml_modify(&Field(image, 0), Val_int(width));
    caml_modify(&Field(image, 1), Val_int(height));
    caml_modify(&Field(image, 3), rgb_data);
    
    switch (bytes_per_pixel) {
    case 3: {
      tj_pixel_format = TJPF_RGB;
    } break;
    case 4: {
      tj_pixel_format = TJPF_RGBX;
    } break;
    default:
      assert(0);
    }

    if (tjDecompress2(tj, data, data_size, (void*) Data_bigarray_val(rgb_data),
                      width, pitch, height, tj_pixel_format, 0) == 0) {
      // all ok!
      result_option = caml_alloc(1, 0);
      Store_field(result_option, 0, image);
    } else {
      // failed :(
    }

    tjDestroy(tj);
  } else {
    // failed :(
  }

  CAMLreturn(result_option);
}
#endif
