/* tinfl.h version cha - public domain inflate with zlib header
 * parsing/adler32 checking (inflate-only subset of miniz.c)
 *
 * See "unlicense" statement at the end of this file.
 * Rich Geldreich <richgel99@gmail.com>, last updated Oct. 19, 2013
 *
 * Implements the decompression side of RFC 1950:
 * http://www.ietf.org/rfc/rfc1950.txt
 * and RFC 1951: http://www.ietf.org/rfc/rfc1951.txt
 *
 * The entire decompressor coroutine function is implemented in a
 * *single* C function: tinfl_decompress().
 *
 *
 * (bptato) Upstream got relicensed to MIT, so I derived this from the
 * last Google Code release (1.16b).  This version remains in the public
 * domain.
 *
 * Changes to the original tinfl.h:
 *
 * - Avoid NULL ptr arithmetic UB.  (Andrius Mitkus)
 * - Fix heap overflow to user buffer in tinfl_decompress.  (Martin
 *   Raiber)
 * - Change TINFL_HEADER_FILE_ONLY to TINFL_IMPLEMENTATION with stb
 *   semantics.
 * - Change MINIZ_* to TINFL_* for consistency.
 * - Remove unaligned loads and stores option, as it invokes undefined
 *   behavior.
 * - Replace bespoke int definitions with stdint.h.
 * - Always use 64-bit bit buffers.
 * - Reformat and re-indent code.
 * - Remove high-level API.
 * - Remove tinfl_get_adler32 macro.
 * - Remove TINFL_FLAG_COMPUTE_ADLER32.  (Now it is always computed.)
 * - Remove TINFL_USE_64BIT_BITBUF.  (Now it is always enabled.)
 * - Gzip header support.  (This includes a crc32 table of 1k size.)
 */
#ifndef TINFL_HEADER_INCLUDED
#define TINFL_HEADER_INCLUDED

#include <stdlib.h>
#include <stdint.h>

/*
 * Decompression flags used by tinfl_decompress().
 *
 * By default, the input is a raw deflate stream.
 *
 * TINFL_FLAG_PARSE_ZLIB_HEADER: If set, the input has a valid
 * zlib header and ends with an adler32 checksum (it's a valid zlib
 * stream).
 *
 * TINFL_FLAG_PARSE_GZIP_HEADER: If set, the input has a valid gzip
 * header and ends with a crc32 checksum and isize (is a valid gzip
 * stream).
 *
 * TINFL_FLAG_HAS_MORE_INPUT: If set, there are more input bytes
 * available beyond the end of the supplied input buffer. If clear, the
 * input buffer contains all remaining input.
 *
 * TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF: If set, the output buffer
 * is large enough to hold the entire decompressed stream. If clear, the
 * output buffer is at least the size of the dictionary (typically
 * 32KB).
 */
enum {
	TINFL_FLAG_PARSE_ZLIB_HEADER			= 0x01,
	TINFL_FLAG_PARSE_GZIP_HEADER			= 0x02,
	TINFL_FLAG_HAS_MORE_INPUT			= 0x04,
	TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF	= 0x08
};

struct tinfl_decompressor_tag;
typedef struct tinfl_decompressor_tag tinfl_decompressor;

/* Max size of LZ dictionary. */
#define TINFL_LZ_DICT_SIZE 32768

/* Return status. Flags below 0 indicate a failure. */

typedef enum {
	/*
	 * This flag indicates the inflator needs 1 or more input bytes
	 * to make forward progress, but the caller is indicating that
	 * no more are available. The compressed data is probably
	 * corrupted.  If you call the inflator again with more bytes
	 * it'll try to continue processing the input but this is a
	 * BAD sign (either the data is corrupted or you called it
	 * incorrectly).
	 *
	 * If you call it again with no input you'll just get
	 * TINFL_STATUS_FAILED_CANNOT_MAKE_PROGRESS again.
	 */
	TINFL_STATUS_FAILED_CANNOT_MAKE_PROGRESS = -5,

	/*
	 * This flag indicates that one or more of the input parameters
	 * was obviously bogus.  (You can try calling it again, but if
	 * you get this error the calling code is wrong.)
	 */
	TINFL_STATUS_BAD_PARAM = -4,

	/*
	 * This flag indicates the inflator is finished but either
	 * the specified size in the GZIP header didn't match the actual
	 * data size, or the crc32 check failed.  If you call it again
	 * it'll return TINFL_STATUS_DONE.
	 */
	TINFL_STATUS_ISIZE_OR_CRC32_MISMATCH = -3,

	/*
	 * This flag indicates the inflator is finished but the adler32
	 * check of the uncompressed data didn't match. If you call it
	 * again it'll return TINFL_STATUS_DONE.
	 */
	TINFL_STATUS_ADLER32_MISMATCH = -2,

	/*
	 * This flag indicates the inflator has somehow failed (bad
	 * code, corrupted input, etc.). If you call it again without
	 * resetting via tinfl_init() it it'll just keep on returning
	 * the same status failure code.
	 */
	TINFL_STATUS_FAILED = -1,

	/*
	 * This flag indicates the inflator has returned every byte of
	 * uncompressed data that it can, has consumed every byte that
	 * it needed, has successfully reached the end of the deflate
	 * stream, andif zlib headers and adler32 checking enabled that
	 * it has successfully checked the uncompressed data's adler32.
	 * If you call it again you'll just get TINFL_STATUS_DONE over
	 * and over again.
	 */
	TINFL_STATUS_DONE = 0,

	/*
	 * This flag indicates the inflator MUST have more input data
	 * (even 1 byte) before it can make any more forward progress,
	 * or you need to clear the TINFL_FLAG_HAS_MORE_INPUT flag on
	 * the next call if you don't have any more source data.
	 *
	 * If the source data was somehow corrupted it's also possible
	 * (but unlikely) for the inflator to keep on demanding input to
	 * proceed, so be sure to properly set the
	 * TINFL_FLAG_HAS_MORE_INPUT flag.
	 */
	TINFL_STATUS_NEEDS_MORE_INPUT = 1,

	/*
	 * This flag indicates the inflator definitely has 1 or more
	 * bytes of uncompressed data available, but it cannot write
	 * this data into the output buffer.
	 *
	 * Note if the source compressed data was corrupted it's
	 * possible for the inflator to return a lot of uncompressed
	 * data to the caller.  I've been assuming you know how much
	 * uncompressed data to expect (either exact or worst case) and
	 * will stop calling the inflator and fail after receiving too
	 * much.  In pure streaming scenarios where you have no idea how
	 * many bytes to expect this may not be possible so I may need
	 * to add some code to address this.
	 */
	TINFL_STATUS_HAS_MORE_OUTPUT = 2
} tinfl_status;

/* Initializes the decompressor to its initial state. */
#define tinfl_init(r) do { (r)->m_state = 0; } while (0)

/*
 * Main low-level decompressor coroutine function. This is the only
 * function actually needed for decompression. All the other functions
 * are just high-level helpers for improved usability.
 *
 * This is a universal API, i.e. it can be used as a building block to
 * build any desired higher level decompression API. In the limit case,
 * it can be called once per every byte input or output.
 */
tinfl_status tinfl_decompress(tinfl_decompressor *r,
			      const uint8_t *pIn_buf_next, size_t *pIn_buf_size,
			      uint8_t *pOut_buf_start, uint8_t *pOut_buf_next,
			      size_t *pOut_buf_size,
			      const uint32_t decomp_flags);

/* Internal/private bits follow. */
enum {
	TINFL_MAX_HUFF_TABLES = 3,
	TINFL_MAX_HUFF_SYMBOLS_0 = 288,
	TINFL_MAX_HUFF_SYMBOLS_1 = 32,
	TINFL_MAX_HUFF_SYMBOLS_2 = 19,
	TINFL_FAST_LOOKUP_BITS = 10,
	TINFL_FAST_LOOKUP_SIZE = 1 << TINFL_FAST_LOOKUP_BITS
};

enum {
	TINFL_GZIP_FTEXT = 0x1,
	TINFL_GZIP_FHCRC = 0x2,
	TINFL_GZIP_FEXTRA = 0x4,
	TINFL_GZIP_FNAME = 0x8,
	TINFL_GZIP_FCOMMENT = 0x10
};

typedef struct {
	uint8_t m_code_size[TINFL_MAX_HUFF_SYMBOLS_0];
	int16_t m_look_up[TINFL_FAST_LOOKUP_SIZE];
	int16_t m_tree[TINFL_MAX_HUFF_SYMBOLS_0 * 2];
} tinfl_huff_table;

#define TINFL_BITBUF_SIZE (64)

struct tinfl_decompressor_tag
{
	uint32_t m_state;
	uint32_t m_num_bits;
	uint32_t m_zhdr0, m_zhdr1;
	uint32_t m_g_isize;
	uint32_t m_checksum, m_checksum_current;
	uint32_t m_final;
	uint32_t m_type;
	uint32_t m_dist;
	uint32_t m_counter;
	uint32_t m_num_extra;
	uint32_t m_table_sizes[TINFL_MAX_HUFF_TABLES];
	uint64_t m_bit_buf;
	size_t m_dist_from_out_buf_start;
	tinfl_huff_table m_tables[TINFL_MAX_HUFF_TABLES];
	uint8_t m_raw_header[4];
	uint8_t m_len_codes[TINFL_MAX_HUFF_SYMBOLS_0 +
			    TINFL_MAX_HUFF_SYMBOLS_1 + 137];
	unsigned char m_gz_header[10];
};

#endif /* TINFL_HEADER_INCLUDED */

/* End of Header: Implementation follows. */

#ifdef TINFL_IMPLEMENTATION

#include <string.h>

#define MZ_MAX(a,b) (((a)>(b))?(a):(b))
#define MZ_MIN(a,b) (((a)<(b))?(a):(b))
#define MZ_CLEAR_OBJ(obj) memset(&(obj), 0, sizeof(obj))
#define MZ_READ_LE32(p) \
	((uint32_t)(((const uint8_t *)(p))[0]) | \
	((uint32_t)(((const uint8_t *)(p))[1]) << 8U) | \
	((uint32_t)(((const uint8_t *)(p))[2]) << 16U) | \
	((uint32_t)(((const uint8_t *)(p))[3]) << 24U))

#define TINFL_MEMCPY(d, s, l) memcpy(d, s, l)
#define TINFL_MEMSET(p, c, l) memset(p, c, l)

#define TINFL_CR_BEGIN switch(r->m_state) { case 0:

#define TINFL_CR_RETURN(state_index, result) \
	do { \
		status = result; \
		r->m_state = state_index; \
		goto common_exit; \
	case state_index:; \
	} while (0)

#define TINFL_CR_RETURN_FOREVER(state_index, result) \
	do { \
		for (;;) \
			TINFL_CR_RETURN(state_index, result); \
	} while (0)

#define TINFL_CR_FINISH }

#define TINFL_GET_BYTE(state_index, c) \
	do { \
		while (pIn_buf_cur >= pIn_buf_end) { \
			TINFL_CR_RETURN(state_index, \
				(decomp_flags & TINFL_FLAG_HAS_MORE_INPUT) ? \
				TINFL_STATUS_NEEDS_MORE_INPUT : \
				TINFL_STATUS_FAILED_CANNOT_MAKE_PROGRESS); \
		} \
		c = *pIn_buf_cur++; \
	} while (0)

#define TINFL_NEED_BITS(state_index, n) \
	do { \
		unsigned c; \
		TINFL_GET_BYTE(state_index, c); \
		bit_buf |= (((uint64_t)c) << num_bits); \
		num_bits += 8; \
	} while (num_bits < (unsigned)(n))

#define TINFL_SKIP_BITS(state_index, n) \
	do { \
		if (num_bits < (unsigned)(n)) \
			TINFL_NEED_BITS(state_index, n); \
		bit_buf >>= (n); \
		num_bits -= (n); \
	} while (0)

#define TINFL_GET_BITS(state_index, b, n) \
	do { \
		if (num_bits < (unsigned)(n)) \
			TINFL_NEED_BITS(state_index, n); \
		b = bit_buf & ((1 << (n)) - 1); \
		bit_buf >>= (n); \
		num_bits -= (n); \
	} while (0)

/*
 * TINFL_HUFF_BITBUF_FILL() is only used rarely, when the number of
 * bytes remaining in the input buffer falls below 2.
 *
 * It reads just enough bytes from the input stream that are needed
 * to decode the next Huffman code (and absolutely no more). It works by
 * trying to fully decode a Huffman code by using whatever bits are
 * currently present in the bit buffer. If this fails, it reads another
 * byte, and tries again until it succeeds or until the bit buffer
 * contains >=15 bits (deflate's max. Huffman code size).
 */
#define TINFL_HUFF_BITBUF_FILL(state_index, pHuff) \
	do { \
		temp = (pHuff)->m_look_up[bit_buf & \
					  (TINFL_FAST_LOOKUP_SIZE - 1)]; \
		if (temp >= 0) { \
			code_len = temp >> 9; \
			if ((code_len) && (num_bits >= code_len)) \
				break; \
		} else if (num_bits > TINFL_FAST_LOOKUP_BITS) { \
			code_len = TINFL_FAST_LOOKUP_BITS; \
			do { \
				temp = (pHuff)->m_tree[~temp + \
					((bit_buf >> code_len++) & 1)]; \
			} while ((temp < 0) && (num_bits >= (code_len + 1))); \
			if (temp >= 0) \
				break; \
		} \
		TINFL_GET_BYTE(state_index, c); \
		bit_buf |= (((uint64_t)c) << num_bits); \
		num_bits += 8; \
	} while (num_bits < 15);

/*
 * TINFL_HUFF_DECODE() decodes the next Huffman coded symbol. It's more
 * complex than you would initially expect because the zlib API expects
 * the decompressor to never read beyond the final byte of the deflate
 * stream. (In other words, when this macro wants to read another byte
 * from the input, it REALLY needs another byte in order to fully
 * decode the next Huffman code.)
 *
 * Handling this properly is particularly important on raw deflate
 * (non-zlib) streams, which aren't followed by a byte aligned adler-32.
 * The slow path is only executed at the very end of the input buffer.
 * v1.16: The original macro handled the case at the very end of the
 * passed-in input buffer, but we also need to handle the case where the
 * user passes in 1+zillion bytes following the deflate data and our
 * non-conservative read-ahead path won't kick in here on this code.
 * This is much trickier.
 */
#define TINFL_HUFF_DECODE(state_index, sym, pHuff) \
	do { \
		int temp; \
		unsigned code_len, c; \
		if (num_bits < 15) { \
			if ((pIn_buf_end - pIn_buf_cur) < 2) { \
				 TINFL_HUFF_BITBUF_FILL(state_index, pHuff); \
			} else { \
				bit_buf |= (((uint64_t)pIn_buf_cur[0]) << num_bits) | \
					(((uint64_t)pIn_buf_cur[1]) << (num_bits + 8)); \
				pIn_buf_cur += 2; \
				num_bits += 16; \
			} \
		} \
		temp = (pHuff)->m_look_up[bit_buf & (TINFL_FAST_LOOKUP_SIZE - 1)]; \
		if (temp >= 0) { \
			code_len = temp >> 9; \
			temp &= 511; \
		} else { \
			code_len = TINFL_FAST_LOOKUP_BITS; \
			do { \
				temp = (pHuff)->m_tree[~temp + \
					((bit_buf >> code_len++) & 1)]; \
			} while (temp < 0); \
		} \
		sym = temp; \
		bit_buf >>= code_len; \
		num_bits -= code_len; \
	} while (0)

int tinfl_decompress(tinfl_decompressor *r, const uint8_t *pIn_buf_next,
		     size_t *pIn_buf_size, uint8_t *pOut_buf_start,
		     uint8_t *pOut_buf_next, size_t *pOut_buf_size,
		     const uint32_t decomp_flags)
{
	static const int s_length_base[31] = {
		3,4,5,6,7,8,9,10,11,13,
		15,17,19,23,27,31,35,43,51,59,
		67,83,99,115,131,163,195,227,258,0,0
	};
	static const int s_length_extra[31] = {
		0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0,0,0
	};
	static const int s_dist_base[32] = {
		1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,
		257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577,0,0
	};
	static const int s_dist_extra[32] = {
		0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13
	};
	static const uint8_t s_length_dezigzag[19] = {
		16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15
	};
	static const int s_min_table_sizes[3] = { 257, 1, 4 };
	static const uint32_t crc32_table[256] = {
		0, 1996959894, 3993919788, 2567524794, 124634137, 1886057615,
		3915621685, 2657392035, 249268274, 2044508324, 3772115230,
		2547177864, 162941995, 2125561021, 3887607047, 2428444049,
		498536548, 1789927666, 4089016648, 2227061214, 450548861,
		1843258603, 4107580753, 2211677639, 325883990, 1684777152,
		4251122042, 2321926636, 335633487, 1661365465, 4195302755,
		2366115317, 997073096, 1281953886, 3579855332, 2724688242,
		1006888145, 1258607687, 3524101629, 2768942443, 901097722,
		1119000684, 3686517206, 2898065728, 853044451, 1172266101,
		3705015759, 2882616665, 651767980, 1373503546, 3369554304,
		3218104598, 565507253, 1454621731, 3485111705, 3099436303,
		671266974, 1594198024, 3322730930, 2970347812, 795835527,
		1483230225, 3244367275, 3060149565, 1994146192, 31158534,
		2563907772, 4023717930, 1907459465, 112637215, 2680153253,
		3904427059, 2013776290, 251722036, 2517215374, 3775830040,
		2137656763, 141376813, 2439277719, 3865271297, 1802195444,
		476864866, 2238001368, 4066508878, 1812370925, 453092731,
		2181625025, 4111451223, 1706088902, 314042704, 2344532202,
		4240017532, 1658658271, 366619977, 2362670323, 4224994405,
		1303535960, 984961486, 2747007092, 3569037538, 1256170817,
		1037604311, 2765210733, 3554079995, 1131014506, 879679996,
		2909243462, 3663771856, 1141124467, 855842277, 2852801631,
		3708648649, 1342533948, 654459306, 3188396048, 3373015174,
		1466479909, 544179635, 3110523913, 3462522015, 1591671054,
		702138776, 2966460450, 3352799412, 1504918807, 783551873,
		3082640443, 3233442989, 3988292384, 2596254646, 62317068,
		1957810842, 3939845945, 2647816111, 81470997, 1943803523,
		3814918930, 2489596804, 225274430, 2053790376, 3826175755,
		2466906013, 167816743, 2097651377, 4027552580, 2265490386,
		503444072, 1762050814, 4150417245, 2154129355, 426522225,
		1852507879, 4275313526, 2312317920, 282753626, 1742555852,
		4189708143, 2394877945, 397917763, 1622183637, 3604390888,
		2714866558, 953729732, 1340076626, 3518719985, 2797360999,
		1068828381, 1219638859, 3624741850, 2936675148, 906185462,
		1090812512, 3747672003, 2825379669, 829329135, 1181335161,
		3412177804, 3160834842, 628085408, 1382605366, 3423369109,
		3138078467, 570562233, 1426400815, 3317316542, 2998733608,
		733239954, 1555261956, 3268935591, 3050360625, 752459403,
		1541320221, 2607071920, 3965973030, 1969922972, 40735498,
		2617837225, 3943577151, 1913087877, 83908371, 2512341634,
		3803740692, 2075208622, 213261112, 2463272603, 3855990285,
		2094854071, 198958881, 2262029012, 4057260610, 1759359992,
		534414190, 2176718541, 4139329115, 1873836001, 414664567,
		2282248934, 4279200368, 1711684554, 285281116, 2405801727,
		4167216745, 1634467795, 376229701, 2685067896, 3608007406,
		1308918612, 956543938, 2808555105, 3495958263, 1231636301,
		1047427035, 2932959818, 3654703836, 1088359270, 936918000,
		2847714899, 3736837829, 1202900863, 817233897, 3183342108,
		3401237130, 1404277552, 615818150, 3134207493, 3453421203,
		1423857449, 601450431, 3009837614, 3294710456, 1567103746,
		711928724, 3020668471, 3272380065, 1510334235, 755167117
	};

	int status = TINFL_STATUS_FAILED;
	uint32_t num_bits, dist, counter, num_extra;
	uint64_t bit_buf;
	const uint8_t *pIn_buf_cur = pIn_buf_next;
	const uint8_t *const pIn_buf_end = pIn_buf_next + *pIn_buf_size;
	uint8_t *pOut_buf_cur = pOut_buf_next;
	uint8_t *const pOut_buf_end = pOut_buf_next ?
		pOut_buf_next + *pOut_buf_size :
		NULL;
	size_t out_buf_size_mask =
		(decomp_flags & TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF) ?
			(size_t)-1 :
			((pOut_buf_next - pOut_buf_start) + *pOut_buf_size) - 1;
	size_t dist_from_out_buf_start;

	/*
	 * Ensure the output buffer's size is a power of 2, unless the
	 * output buffer is large enough to hold the entire output file
	 * (in which case it doesn't matter).
	 */
	if (((out_buf_size_mask + 1) & out_buf_size_mask) ||
	    (pOut_buf_next < pOut_buf_start)) {
		*pIn_buf_size = *pOut_buf_size = 0;
		return TINFL_STATUS_BAD_PARAM;
	}

	/* Pick one. You can't have both. */
	if ((decomp_flags & TINFL_FLAG_PARSE_GZIP_HEADER) &&
	    (decomp_flags & TINFL_FLAG_PARSE_ZLIB_HEADER))
		return TINFL_STATUS_BAD_PARAM;

	num_bits = r->m_num_bits;
	bit_buf = r->m_bit_buf;
	dist = r->m_dist;
	counter = r->m_counter;
	num_extra = r->m_num_extra;
	dist_from_out_buf_start = r->m_dist_from_out_buf_start;

	TINFL_CR_BEGIN

	bit_buf = num_bits = dist = counter = num_extra = 0;
	r->m_zhdr0 = r->m_zhdr1 = 0;
	if (decomp_flags & TINFL_FLAG_PARSE_ZLIB_HEADER) {
		r->m_checksum = r->m_checksum_current = 1;
		TINFL_GET_BYTE(1, r->m_zhdr0);
		TINFL_GET_BYTE(2, r->m_zhdr1);
		counter = ((r->m_zhdr0 * 256 + r->m_zhdr1) % 31 != 0) ||
			  (r->m_zhdr1 & 32) || ((r->m_zhdr0 & 15) != 8);
		if (!(decomp_flags & TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF))
			counter |= ((1U << (8U + (r->m_zhdr0 >> 4))) > 32768U) ||
				   ((out_buf_size_mask + 1) < (size_t)(1U << (8U + (r->m_zhdr0 >> 4))));
		if (counter)
			TINFL_CR_RETURN_FOREVER(36, TINFL_STATUS_FAILED);
	} else if (decomp_flags & TINFL_FLAG_PARSE_GZIP_HEADER) {
		unsigned s, varlen = 0;
		r->m_checksum = 0;
		r->m_checksum_current = 0xFFFFFFFFU;
		r->m_g_isize = 0;
		for (counter = 0; counter < 10; counter++)
			TINFL_GET_BYTE(50, r->m_gz_header[counter]);
		if (r->m_gz_header[0] != 0x1F || r->m_gz_header[1] != 0x8B ||
		    r->m_gz_header[2] != 8) {
			TINFL_CR_RETURN_FOREVER(54, TINFL_STATUS_FAILED);
		}
		if (r->m_gz_header[3] & TINFL_GZIP_FEXTRA) {
			unsigned s;
			num_extra = 0;
			TINFL_GET_BYTE(55, s);
			num_extra |= s;
			TINFL_GET_BYTE(56, s);
			num_extra |= s << 8;
			for (counter = 0; counter < num_extra; counter++)
				TINFL_GET_BYTE(57, s);
		}
		varlen = ((r->m_gz_header[3] & TINFL_GZIP_FNAME) != 0) +
			 ((r->m_gz_header[3] & TINFL_GZIP_FCOMMENT) != 0);
		for (counter = 0; counter < varlen; counter++) {
			do {
				TINFL_GET_BYTE(58, s);
			} while (s);
		}
		if (r->m_gz_header[3] & TINFL_GZIP_FHCRC) {
			for (counter = 0; counter < 2; counter++)
				TINFL_GET_BYTE(59, s);
		}
	}

	do {
		TINFL_GET_BITS(3, r->m_final, 3);
		r->m_type = r->m_final >> 1;
		if (r->m_type == 0) {
			TINFL_SKIP_BITS(5, num_bits & 7);
			for (counter = 0; counter < 4; counter++) {
				if (num_bits)
					TINFL_GET_BITS(6, r->m_raw_header[counter], 8);
				else
					TINFL_GET_BYTE(7, r->m_raw_header[counter]);
			}
			counter = (r->m_raw_header[0] | (r->m_raw_header[1] << 8));
			if (counter != (0xFFFFU ^ (r->m_raw_header[2] | (r->m_raw_header[3] << 8))))
				TINFL_CR_RETURN_FOREVER(39, TINFL_STATUS_FAILED);
			while ((counter) && (num_bits)) {
				TINFL_GET_BITS(51, dist, 8);
				while (pOut_buf_cur >= pOut_buf_end)
					TINFL_CR_RETURN(52, TINFL_STATUS_HAS_MORE_OUTPUT);
				*pOut_buf_cur++ = (uint8_t)dist;
				counter--;
			}
			while (counter) {
				size_t n;
				while (pOut_buf_cur >= pOut_buf_end)
					TINFL_CR_RETURN(9, TINFL_STATUS_HAS_MORE_OUTPUT);
				while (pIn_buf_cur >= pIn_buf_end) {
					TINFL_CR_RETURN(38,
						(decomp_flags & TINFL_FLAG_HAS_MORE_INPUT) ?
						TINFL_STATUS_NEEDS_MORE_INPUT :
						TINFL_STATUS_FAILED_CANNOT_MAKE_PROGRESS);
				}
				n = MZ_MIN((size_t)(pOut_buf_end - pOut_buf_cur),
					   (size_t)(pIn_buf_end - pIn_buf_cur));
				n = MZ_MIN(n, counter);
				TINFL_MEMCPY(pOut_buf_cur, pIn_buf_cur, n);
				pIn_buf_cur += n;
				pOut_buf_cur += n;
				counter -= (unsigned)n;
			}
		} else if (r->m_type == 3) {
			TINFL_CR_RETURN_FOREVER(10, TINFL_STATUS_FAILED);
		} else {
			if (r->m_type == 1) {
				uint8_t *p = r->m_tables[0].m_code_size;
				unsigned i;
				r->m_table_sizes[0] = 288;
				r->m_table_sizes[1] = 32;
				TINFL_MEMSET(r->m_tables[1].m_code_size, 5, 32);
				for (i = 0; i <= 143; ++i)
					*p++ = 8;
				for (; i <= 255; ++i)
					*p++ = 9;
				for (; i <= 279; ++i)
					*p++ = 7;
				for (; i <= 287; ++i)
					*p++ = 8;
			} else {
				for (counter = 0; counter < 3; counter++) {
					TINFL_GET_BITS(11, r->m_table_sizes[counter], "\05\05\04"[counter]);
					r->m_table_sizes[counter] +=
						s_min_table_sizes[counter];
				}
				MZ_CLEAR_OBJ(r->m_tables[2].m_code_size);
				for (counter = 0; counter < r->m_table_sizes[2]; counter++) {
					unsigned s;
					TINFL_GET_BITS(14, s, 3);
					r->m_tables[2].m_code_size[s_length_dezigzag[counter]] = (uint8_t)s;
				}
				r->m_table_sizes[2] = 19;
			}
			for (; (int)r->m_type >= 0; r->m_type--) {
				int tree_next, tree_cur;
				tinfl_huff_table *pTable;
				unsigned i, j, used_syms, total, sym_index;
				unsigned next_code[17], total_syms[16];
				pTable = &r->m_tables[r->m_type];
				MZ_CLEAR_OBJ(total_syms);
				MZ_CLEAR_OBJ(pTable->m_look_up);
				MZ_CLEAR_OBJ(pTable->m_tree);
				for (i = 0; i < r->m_table_sizes[r->m_type]; ++i)
					total_syms[pTable->m_code_size[i]]++;
				used_syms = 0, total = 0;
				next_code[0] = next_code[1] = 0;
				for (i = 1; i <= 15; ++i) {
					used_syms += total_syms[i];
					next_code[i + 1] = (total = ((total + total_syms[i]) << 1));
				}
				if ((65536 != total) && (used_syms > 1)) {
					TINFL_CR_RETURN_FOREVER(35, TINFL_STATUS_FAILED);
				}
				for (tree_next = -1, sym_index = 0; sym_index < r->m_table_sizes[r->m_type]; ++sym_index) {
					unsigned rev_code = 0, l, cur_code;
					unsigned code_size = pTable->m_code_size[sym_index];
					if (!code_size)
						continue;
					cur_code = next_code[code_size]++;
					for (l = code_size; l > 0; l--, cur_code >>= 1)
						rev_code = (rev_code << 1) | (cur_code & 1);
					if (code_size <= TINFL_FAST_LOOKUP_BITS) {
						int16_t k = (int16_t)((code_size << 9) | sym_index);
						while (rev_code < TINFL_FAST_LOOKUP_SIZE) {
							pTable->m_look_up[rev_code] = k;
							rev_code += (1 << code_size);
						}
						continue;
					}
					if (0 == (tree_cur = pTable->m_look_up[rev_code & (TINFL_FAST_LOOKUP_SIZE - 1)])) {
						pTable->m_look_up[rev_code & (TINFL_FAST_LOOKUP_SIZE - 1)] = (int16_t)tree_next;
						tree_cur = tree_next;
						tree_next -= 2;
					}
					rev_code >>= (TINFL_FAST_LOOKUP_BITS - 1);
					for (j = code_size; j > (TINFL_FAST_LOOKUP_BITS + 1); j--) {
						tree_cur -= ((rev_code >>= 1) & 1);
						if (!pTable->m_tree[-tree_cur - 1]) {
							pTable->m_tree[-tree_cur - 1] = (int16_t)tree_next;
							tree_cur = tree_next;
							tree_next -= 2;
						} else {
							tree_cur = pTable->m_tree[-tree_cur - 1];
						}
					}
					tree_cur -= ((rev_code >>= 1) & 1);
					pTable->m_tree[-tree_cur - 1] = (int16_t)sym_index;
				}
				if (r->m_type == 2) {
					for (counter = 0; counter < (r->m_table_sizes[0] + r->m_table_sizes[1]); ) {
						unsigned s;
						TINFL_HUFF_DECODE(16, dist, &r->m_tables[2]);
						if (dist < 16) {
							r->m_len_codes[counter++] = (uint8_t)dist;
							continue;
						}
						if ((dist == 16) && !counter)
							TINFL_CR_RETURN_FOREVER(17, TINFL_STATUS_FAILED);
						num_extra = "\02\03\07"[dist - 16];
						TINFL_GET_BITS(18, s, num_extra);
						s += "\03\03\013"[dist - 16];
						TINFL_MEMSET(r->m_len_codes + counter,
							     (dist == 16) ?  r->m_len_codes[counter - 1] : 0,
							     s);
						counter += s;
					}
					if ((r->m_table_sizes[0] + r->m_table_sizes[1]) != counter)
						TINFL_CR_RETURN_FOREVER(21, TINFL_STATUS_FAILED);
					TINFL_MEMCPY(r->m_tables[0].m_code_size, r->m_len_codes, r->m_table_sizes[0]);
					TINFL_MEMCPY(r->m_tables[1].m_code_size, r->m_len_codes + r->m_table_sizes[0], r->m_table_sizes[1]);
				}
			}
			for (;;) {
				uint8_t *pSrc;
				for (;;) {
					if (((pIn_buf_end - pIn_buf_cur) < 4) ||
					    ((pOut_buf_end - pOut_buf_cur) < 2)) {
						TINFL_HUFF_DECODE(23, counter, &r->m_tables[0]);
						if (counter >= 256)
							break;
						while (pOut_buf_cur >= pOut_buf_end)
							TINFL_CR_RETURN(24, TINFL_STATUS_HAS_MORE_OUTPUT);
						*pOut_buf_cur++ = (uint8_t)counter;
					} else {
						int sym2;
						unsigned code_len;
						if (num_bits < 30) {
							bit_buf |= (((uint64_t)MZ_READ_LE32(pIn_buf_cur)) << num_bits);
							pIn_buf_cur += 4;
							num_bits += 32;
						}
						if ((sym2 = r->m_tables[0].m_look_up[bit_buf & (TINFL_FAST_LOOKUP_SIZE - 1)]) >= 0) {
							code_len = sym2 >> 9;
						} else {
							code_len = TINFL_FAST_LOOKUP_BITS;
							do {
								sym2 = r->m_tables[0].m_tree[~sym2 + ((bit_buf >> code_len++) & 1)];
							} while (sym2 < 0);
						}
						counter = sym2;
						bit_buf >>= code_len;
						num_bits -= code_len;
						if (counter & 256)
							break;

						if ((sym2 = r->m_tables[0].m_look_up[bit_buf & (TINFL_FAST_LOOKUP_SIZE - 1)]) >= 0) {
							code_len = sym2 >> 9;
						} else {
							code_len = TINFL_FAST_LOOKUP_BITS;
							do {
								sym2 = r->m_tables[0].m_tree[~sym2 + ((bit_buf >> code_len++) & 1)];
							} while (sym2 < 0);
						}
						bit_buf >>= code_len;
						num_bits -= code_len;

						pOut_buf_cur[0] = (uint8_t)counter;
						if (sym2 & 256) {
							pOut_buf_cur++;
							counter = sym2;
							break;
						}
						pOut_buf_cur[1] = (uint8_t)sym2;
						pOut_buf_cur += 2;
					}
				}
				if ((counter &= 511) == 256)
					break;

				num_extra = s_length_extra[counter - 257];
				counter = s_length_base[counter - 257];
				if (num_extra) {
					unsigned extra_bits;
					TINFL_GET_BITS(25, extra_bits, num_extra);
					counter += extra_bits;
				}

				TINFL_HUFF_DECODE(26, dist, &r->m_tables[1]);
				num_extra = s_dist_extra[dist];
				dist = s_dist_base[dist];
				if (num_extra) {
					unsigned extra_bits;
					TINFL_GET_BITS(27, extra_bits, num_extra);
					dist += extra_bits;
				}

				dist_from_out_buf_start = pOut_buf_cur - pOut_buf_start;
				if ((dist > dist_from_out_buf_start) &&
				    (decomp_flags & TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF)) {
					TINFL_CR_RETURN_FOREVER(37, TINFL_STATUS_FAILED);
				}

				pSrc = pOut_buf_start + ((dist_from_out_buf_start - dist) & out_buf_size_mask);

				if ((MZ_MAX(pOut_buf_cur, pSrc) + counter) > pOut_buf_end) {
					while (counter--) {
						while (pOut_buf_cur >= pOut_buf_end)
							TINFL_CR_RETURN(53, TINFL_STATUS_HAS_MORE_OUTPUT);
						*pOut_buf_cur++ = pOut_buf_start[(dist_from_out_buf_start++ - dist) & out_buf_size_mask];
					}
					continue;
				}
				for (; counter > 0; counter--)
					*pOut_buf_cur++ = *pSrc++;
			}
		}
	} while (!(r->m_final & 1));

	/*
	 * Ensure byte alignment and put back any bytes from the bitbuf
	 * if we've looked ahead too far on gzip, or other Deflate streams
	 * followed by arbitrary data.
	 *
	 * I'm being super conservative here. A number of
	 * simplifications can be made to the byte alignment part, and the
	 * Adler32 check shouldn't ever need to worry about reading from
	 * the bitbuf now.
	 */
	TINFL_SKIP_BITS(32, num_bits & 7);
	while ((pIn_buf_cur > pIn_buf_next) && (num_bits >= 8)) {
		--pIn_buf_cur;
		num_bits -= 8;
	}
	bit_buf &= (uint64_t)((1ULL << num_bits) - 1ULL);
	/*
	 * if this assert fires then we've read beyond the end of
	 * non-deflate/zlib streams with following data
	 * (such as gzip streams). */
	/* MZ_ASSERT(!num_bits); */

	if (decomp_flags & TINFL_FLAG_PARSE_ZLIB_HEADER) {
		for (counter = 0; counter < 4; counter++) {
			unsigned s;
			if (num_bits)
				TINFL_GET_BITS(41, s, 8);
			else
				TINFL_GET_BYTE(42, s);
			r->m_checksum = (r->m_checksum << 8) | s;
		}
	} else if (decomp_flags & TINFL_FLAG_PARSE_GZIP_HEADER) {
		for (counter = 0; counter < 32; counter += 8) {
			unsigned s;
			if (num_bits)
				TINFL_GET_BITS(44, s, 8);
			else
				TINFL_GET_BYTE(45, s);
			r->m_checksum |= s << counter;
		}
		for (counter = 0; counter < 32; counter += 8) {
			unsigned s;
			if (num_bits)
				TINFL_GET_BITS(43, s, 8);
			else
				TINFL_GET_BYTE(40, s);
			r->m_g_isize -= s << counter;
		}
	}
	TINFL_CR_RETURN_FOREVER(34, TINFL_STATUS_DONE);

	TINFL_CR_FINISH

common_exit:
	/*
	 * As long as we aren't telling the caller that we NEED more
	 * input to make forward progress:
	 * Put back any bytes from the bitbuf in case we've looked ahead
	 * too far on gzip, or other Deflate streams followed by arbitrary
	 * data.
	 * We need to be very careful here to NOT push back any bytes
	 * we definitely know we need to make forward progress, though,
	 * or we'll lock the caller up into an inf loop.
	 */
	if ((status != TINFL_STATUS_NEEDS_MORE_INPUT) &&
	    (status != TINFL_STATUS_FAILED_CANNOT_MAKE_PROGRESS)) {
		while ((pIn_buf_cur > pIn_buf_next) && (num_bits >= 8)) {
			--pIn_buf_cur;
			num_bits -= 8;
		}
	}
	r->m_num_bits = num_bits;
	r->m_bit_buf = bit_buf & (uint64_t)((1ULL << num_bits) - 1ULL);
	r->m_dist = dist;
	r->m_counter = counter;
	r->m_num_extra = num_extra;
	r->m_dist_from_out_buf_start = dist_from_out_buf_start;
	*pIn_buf_size = pIn_buf_cur - pIn_buf_next;
	*pOut_buf_size = pOut_buf_cur - pOut_buf_next;
	if ((decomp_flags & TINFL_FLAG_PARSE_GZIP_HEADER) && (status >= 0)) {
		const uint8_t *ptr = pOut_buf_next;
		size_t buf_len = *pOut_buf_size;
		uint32_t i;
		uint32_t s = r->m_checksum_current;
		for (i = 0; i < buf_len; i++)
			s = crc32_table[(s ^ *ptr++) & 0xFF] ^ (s >> 8);
		r->m_checksum_current = s;
		r->m_g_isize += *pOut_buf_size;
		if (status == TINFL_STATUS_DONE &&
		   ((r->m_g_isize != 0) ||
		   ((r->m_checksum_current ^ 0xFFFFFFFFU) != r->m_checksum)))
			status = TINFL_STATUS_ISIZE_OR_CRC32_MISMATCH;
	} else if ((decomp_flags & TINFL_FLAG_PARSE_ZLIB_HEADER) && (status >= 0)) {
		const uint8_t *ptr = pOut_buf_next;
		size_t buf_len = *pOut_buf_size;
		uint32_t i;
		uint32_t s1 = r->m_checksum_current & 0xffff;
		uint32_t s2 = r->m_checksum_current >> 16;
		size_t block_len = buf_len % 5552;
		while (buf_len) {
			for (i = 0; i + 7 < block_len; i += 8, ptr += 8) {
				s1 += ptr[0], s2 += s1;
				s1 += ptr[1], s2 += s1;
				s1 += ptr[2], s2 += s1;
				s1 += ptr[3], s2 += s1;
				s1 += ptr[4], s2 += s1;
				s1 += ptr[5], s2 += s1;
				s1 += ptr[6], s2 += s1;
				s1 += ptr[7], s2 += s1;
			}
			for (; i < block_len; ++i)
				s1 += *ptr++, s2 += s1;
			s1 %= 65521U, s2 %= 65521U;
			buf_len -= block_len;
			block_len = 5552;
		}
		r->m_checksum_current = (s2 << 16) + s1;
		if ((status == TINFL_STATUS_DONE) &&
		    (r->m_checksum_current != r->m_checksum))
			status = TINFL_STATUS_ADLER32_MISMATCH;
	}
	return status;
}

#endif /* TINFL_IMPLEMENTATION */

/*
  This is free and unencumbered software released into the public domain.

  Anyone is free to copy, modify, publish, use, compile, sell, or
  distribute this software, either in source code form or as a compiled
  binary, for any purpose, commercial or non-commercial, and by any
  means.

  In jurisdictions that recognize copyright laws, the author or authors
  of this software dedicate any and all copyright interest in the
  software to the public domain. We make this dedication for the benefit
  of the public at large and to the detriment of our heirs and
  successors. We intend this dedication to be an overt act of
  relinquishment in perpetuity of all present and future rights to this
  software under copyright law.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
  IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
  OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
  ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
  OTHER DEALINGS IN THE SOFTWARE.

  For more information, please refer to <http://unlicense.org/>
*/
