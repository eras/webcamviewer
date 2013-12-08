#include <stdlib.h>
#include <stdio.h>
#include <jpeglib.h>
#include <setjmp.h>
#include <assert.h>

#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <caml/bigarray.h>

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
jpeg_decode(value frame)
{
  CAMLparam1(frame);
  CAMLlocal1(result);
  CAMLlocal1(rgb_data);

  struct jpeg_source_mgr src;
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

  result = caml_alloc_tuple(3);
  if (setjmp(custom_dec.decode_env) == 0) {
    jpeg_read_header(dec, TRUE);

    jpeg_start_decompress(dec);

    int size = dec->output_width * dec->output_height * 3;
    int pitch = dec->output_width * 3;
    rgb_data = alloc_bigarray_dims(CAML_BA_UINT8 | CAML_BA_C_LAYOUT, 1,
				 NULL, size);
    caml_modify(&Field(result, 0), Val_int(dec->output_width));
    caml_modify(&Field(result, 1), Val_int(dec->output_height));
    caml_modify(&Field(result, 2), rgb_data);
    JSAMPLE* begin = (void*) Data_bigarray_val(rgb_data);
    JSAMPLE* buffer = begin;
    const JSAMPLE* end = (void*) (((char*) Data_bigarray_val(rgb_data)) + size);

    if (setjmp(custom_dec.decode_env) == 0) {
      while (dec->output_scanline < dec->output_height) {
	assert(buffer + pitch <= end);
	jpeg_read_scanlines(dec, &buffer, 1);
	buffer += pitch;
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
  } else {
    // uh oh 2
    printf("header decoding error\n");

    caml_modify(&Field(result, 0), Val_int(0));
    caml_modify(&Field(result, 1), Val_int(0));
    rgb_data = alloc_bigarray_dims(CAML_BA_UINT8 | CAML_BA_C_LAYOUT, 1,
                                   NULL, 0);
  }

  jpeg_destroy_decompress(dec);

  CAMLreturn(result);
}

