# frozen_string_literal: true

# nkf.so, the C part of the nkf gem 0.3.0: Network Kanji Filter 2.1.5
# (ext/nkf/nkf.c over nkf-utf8/nkf.c), in Ruby. The gem's own nkf.rb
# requires this file, and its kconv.rb is built on NKF.
#
# nkf reads one byte at a time through a chain of input filters (MIME
# decoding, broken-JIS repair, hex and character-reference escapes, NFC
# for UTF8-MAC), guesses the input encoding with one state machine per
# candidate, decodes each character to nkf's internal form, and sends it
# through a chain of output filters (katakana folding, -Z, hiragana,
# ROT13, line folding, newline conversion, MIME encoding) to the encoder
# that the options select. The internal form is the one nkf.c uses: a pair
# (c2, c1) where c2 is 0 for ASCII, a JIS X 0208 row, a JIS X 0212 row
# with 0x8F00 set, or a marker for JIS X 0201 katakana or ISO-8859-1, and
# c1 is the byte or cell. A Unicode code point outside the JIS tables
# goes as c1 with 0x01000000 set.
#
# The converter keeps nkf.c's function names, so each method can be read
# against the C. A chain link that C keeps as a function pointer is a
# method name here, which the converter sends to.
require_relative "nkf/tables"

module NKF
  # The state of one conversion: struct nkf_state_t.
  class Converter
    NKF_VERSION = "2.1.5"
    NKF_RELEASE_DATE = "2018-12-15"

    EOF = -1
    FALSE = 0
    TRUE = 1
    NKF_UNSPECIFIED = -1

    BS = 0x08
    TAB = 0x09
    LF = 0x0a
    CR = 0x0d
    ESC = 0x1b
    SP = 0x20
    DEL = 0x7f
    SI = 0x0f
    SO = 0x0e
    SS2 = 0x8e
    SS3 = 0x8f
    CRLF = 0x0D0A

    FIXED_MIME = 7
    STRICT_MIME = 8

    ENDIAN_BIG = 1
    ENDIAN_LITTLE = 2
    ENDIAN_2143 = 3
    ENDIAN_3412 = 4

    # enum nkf_encodings: the index of each encoding nkf names, and the
    # character sets an escape sequence selects.
    ASCII = 0
    ISO_8859_1 = 1
    ISO_2022_JP = 2
    CP50220 = 3
    CP50221 = 4
    CP50222 = 5
    ISO_2022_JP_1 = 6
    ISO_2022_JP_3 = 7
    ISO_2022_JP_2004 = 8
    SHIFT_JIS = 9
    WINDOWS_31J = 10
    CP10001 = 11
    EUC_JP = 12
    EUCJP_NKF = 13
    CP51932 = 14
    EUCJP_MS = 15
    EUCJP_ASCII = 16
    SHIFT_JISX0213 = 17
    SHIFT_JIS_2004 = 18
    EUC_JISX0213 = 19
    EUC_JIS_2004 = 20
    UTF_8 = 21
    UTF_8N = 22
    UTF_8_BOM = 23
    UTF8_MAC = 24
    UTF_16 = 25
    UTF_16BE = 26
    UTF_16BE_BOM = 27
    UTF_16LE = 28
    UTF_16LE_BOM = 29
    UTF_32 = 30
    UTF_32BE = 31
    UTF_32BE_BOM = 32
    UTF_32LE = 33
    UTF_32LE_BOM = 34
    BINARY = 35
    JIS_X_0201_1976_K = 0x1013
    JIS_X_0208 = 0x1168
    JIS_X_0212 = 0x1159
    JIS_X_0213_2 = 0x1229
    JIS_X_0213_1 = 0x1233

    UCS_MAP_ASCII = 0
    UCS_MAP_MS = 1
    UCS_MAP_CP932 = 2
    UCS_MAP_CP10001 = 3

    PREFIX_EUCG3 = 0x8F00
    CLASS_MASK = 0xFF000000
    CLASS_UNICODE = 0x01000000
    VALUE_MASK = 0x00FFFFFF
    UNICODE_BMP_MAX = 0x0000FFFF
    UNICODE_MAX = 0x0010FFFF

    GETA1 = 0x22
    GETA2 = 0x2e
    DEFAULT_J = "B".ord
    DEFAULT_R = "B".ord
    FOLD_MARGIN = 10
    DEFAULT_FOLD = 60
    BUFSIZ = 1024
    HOLD_SIZE = 1024
    MIME_BUF_SIZE = 1024
    MIME_BUF_MASK = MIME_BUF_SIZE - 1
    MIMEOUT_BUF_LENGTH = 74
    MAXRECOVER = 20

    NKF_ICONV_INVALID_CODE_RANGE = -13
    NKF_ICONV_WAIT_COMBINING_CHAR = -14
    NKF_ICONV_NOT_COMBINED = -15
    NKF_ICONV_NEED_TWO_MORE_BYTES = -2

    # What an encoding reads and writes with: nkf_native_encoding.
    Base = Struct.new(:name, :iconv, :oconv)
    BASE_ASCII = Base.new("ASCII", :e_iconv, :e_oconv).freeze
    BASE_ISO_2022_JP = Base.new("ISO-2022-JP", :e_iconv, :j_oconv).freeze
    BASE_SHIFT_JIS = Base.new("Shift_JIS", :s_iconv, :s_oconv).freeze
    BASE_EUC_JP = Base.new("EUC-JP", :e_iconv, :e_oconv).freeze
    BASE_UTF_8 = Base.new("UTF-8", :w_iconv, :w_oconv).freeze
    BASE_UTF_16 = Base.new("UTF-16", :w_iconv16, :w_oconv16).freeze
    BASE_UTF_32 = Base.new("UTF-32", :w_iconv32, :w_oconv32).freeze

    # An encoding nkf names: nkf_encoding. ENCODINGS is indexed by id.
    Enc = Struct.new(:id, :name, :base) do
      def ascii_compatible? = base == BASE_ASCII || base == BASE_ISO_2022_JP
      def unicode? = base == BASE_UTF_8 || base == BASE_UTF_16 || base == BASE_UTF_32
      def cp5022x? = id == CP50220 || id == CP50221 || id == CP50222
    end

    ENCODINGS = [
      [ASCII, "US-ASCII", BASE_ASCII], [ISO_8859_1, "ISO-8859-1", BASE_ASCII],
      [ISO_2022_JP, "ISO-2022-JP", BASE_ISO_2022_JP], [CP50220, "CP50220", BASE_ISO_2022_JP],
      [CP50221, "CP50221", BASE_ISO_2022_JP], [CP50222, "CP50222", BASE_ISO_2022_JP],
      [ISO_2022_JP_1, "ISO-2022-JP-1", BASE_ISO_2022_JP], [ISO_2022_JP_3, "ISO-2022-JP-3", BASE_ISO_2022_JP],
      [ISO_2022_JP_2004, "ISO-2022-JP-2004", BASE_ISO_2022_JP], [SHIFT_JIS, "Shift_JIS", BASE_SHIFT_JIS],
      [WINDOWS_31J, "Windows-31J", BASE_SHIFT_JIS], [CP10001, "CP10001", BASE_SHIFT_JIS],
      [EUC_JP, "EUC-JP", BASE_EUC_JP], [EUCJP_NKF, "eucJP-nkf", BASE_EUC_JP],
      [CP51932, "CP51932", BASE_EUC_JP], [EUCJP_MS, "eucJP-MS", BASE_EUC_JP],
      [EUCJP_ASCII, "eucJP-ASCII", BASE_EUC_JP], [SHIFT_JISX0213, "Shift_JISX0213", BASE_SHIFT_JIS],
      [SHIFT_JIS_2004, "Shift_JIS-2004", BASE_SHIFT_JIS], [EUC_JISX0213, "EUC-JISX0213", BASE_EUC_JP],
      [EUC_JIS_2004, "EUC-JIS-2004", BASE_EUC_JP], [UTF_8, "UTF-8", BASE_UTF_8],
      [UTF_8N, "UTF-8N", BASE_UTF_8], [UTF_8_BOM, "UTF-8-BOM", BASE_UTF_8],
      [UTF8_MAC, "UTF8-MAC", BASE_UTF_8], [UTF_16, "UTF-16", BASE_UTF_16],
      [UTF_16BE, "UTF-16BE", BASE_UTF_16], [UTF_16BE_BOM, "UTF-16BE-BOM", BASE_UTF_16],
      [UTF_16LE, "UTF-16LE", BASE_UTF_16], [UTF_16LE_BOM, "UTF-16LE-BOM", BASE_UTF_16],
      [UTF_32, "UTF-32", BASE_UTF_32], [UTF_32BE, "UTF-32BE", BASE_UTF_32],
      [UTF_32BE_BOM, "UTF-32BE-BOM", BASE_UTF_32], [UTF_32LE, "UTF-32LE", BASE_UTF_32],
      [UTF_32LE_BOM, "UTF-32LE-BOM", BASE_UTF_32], [BINARY, "BINARY", BASE_ASCII]
    ].map { |row| Enc.new(*row).freeze }.freeze

    # encoding_name_to_id_table, keyed by the upcased name.
    ENCODING_IDS = {
      "US-ASCII" => ASCII, "ASCII" => ASCII, "646" => ASCII, "ROMAN8" => ASCII,
      "ISO-2022-JP" => ISO_2022_JP, "ISO2022JP-CP932" => CP50220, "CP50220" => CP50220,
      "CP50221" => CP50221, "CSISO2022JP" => CP50221, "CP50222" => CP50222,
      "ISO-2022-JP-1" => ISO_2022_JP_1, "ISO-2022-JP-3" => ISO_2022_JP_3,
      "ISO-2022-JP-2004" => ISO_2022_JP_2004, "SHIFT_JIS" => SHIFT_JIS, "SJIS" => SHIFT_JIS,
      "MS_KANJI" => SHIFT_JIS, "PCK" => SHIFT_JIS, "WINDOWS-31J" => WINDOWS_31J,
      "CSWINDOWS31J" => WINDOWS_31J, "CP932" => WINDOWS_31J, "MS932" => WINDOWS_31J,
      "CP10001" => CP10001, "EUCJP" => EUC_JP, "EUC-JP" => EUC_JP, "EUCJP-NKF" => EUCJP_NKF,
      "CP51932" => CP51932, "EUC-JP-MS" => EUCJP_MS, "EUCJP-MS" => EUCJP_MS, "EUCJPMS" => EUCJP_MS,
      "EUC-JP-ASCII" => EUCJP_ASCII, "EUCJP-ASCII" => EUCJP_ASCII,
      "SHIFT_JISX0213" => SHIFT_JISX0213, "SHIFT_JIS-2004" => SHIFT_JIS_2004,
      "EUC-JISX0213" => EUC_JISX0213, "EUC-JIS-2004" => EUC_JIS_2004,
      "UTF-8" => UTF_8, "UTF-8N" => UTF_8N, "UTF-8-BOM" => UTF_8_BOM, "UTF8-MAC" => UTF8_MAC,
      "UTF-8-MAC" => UTF8_MAC, "UTF-16" => UTF_16, "UTF-16BE" => UTF_16BE,
      "UTF-16BE-BOM" => UTF_16BE_BOM, "UTF-16LE" => UTF_16LE, "UTF-16LE-BOM" => UTF_16LE_BOM,
      "UTF-32" => UTF_32, "UTF-32BE" => UTF_32BE, "UTF-32BE-BOM" => UTF_32BE_BOM,
      "UTF-32LE" => UTF_32LE, "UTF-32LE-BOM" => UTF_32LE_BOM, "BINARY" => BINARY
    }.freeze

    # The long options that Ruby's nkf accepts, in nkf.c's order, each with
    # the short options it represents ("" for one handled by name).
    LONG_OPTIONS = [
      ["ic=", ""], ["oc=", ""], ["base64", "jMB"], ["euc", "e"], ["euc-input", "E"],
      ["fj", "jm"], ["help", ""], ["jis", "j"], ["jis-input", "J"], ["mac", "sLm"],
      ["mime", "jM"], ["mime-input", "m"], ["msdos", "sLw"], ["sjis", "s"],
      ["sjis-input", "S"], ["unix", "eLu"], ["version", "v"], ["windows", "sLw"],
      ["hiragana", "h1"], ["katakana", "h2"], ["katakana-hiragana", "h3"],
      ["guess=", ""], ["guess", "g2"], ["cp932", ""], ["no-cp932", ""], ["x0212", ""],
      ["utf8", "w"], ["utf16", "w16"], ["ms-ucs-map", ""], ["fb-skip", ""], ["fb-html", ""],
      ["fb-xml", ""], ["fb-perl", ""], ["fb-java", ""], ["fb-subchar", ""], ["fb-subchar=", ""],
      ["utf8-input", "W"], ["utf16-input", "W16"], ["no-cp932ext", ""], ["no-best-fit-chars", ""],
      ["utf8mac-input", ""], ["cap-input", ""], ["url-input", ""], ["numchar-input", ""],
      ["no-output", ""], ["debug", ""], ["cp932inv", ""], ["prefix=", ""]
    ].map { |name, alias_name| [name.bytes.freeze, name, alias_name.bytes.freeze] }.freeze

    # One candidate of the input guesser: struct input_code.
    InputCode = Struct.new(:name, :stat, :score, :index, :buf, :status_func, :iconv_func)

    # A conversion of `src` under the options `opt`: rb_nkf_convert.
    def self.convert(opt, src)
      opt = string_value(opt)
      raise ArgumentError, "string contains null byte" if opt.include?("\0")

      converter = new
      converter.nkf_split_options(opt.bytes)
      converter.convert(string_value(src))
    end

    # The encoding nkf guesses `src` is in: rb_nkf_guess.
    def self.guess(src)
      new.guess(string_value(src))
    end

    # StringValue: a String, or what an implicit conversion makes one.
    def self.string_value(value)
      return value if value.is_a?(String)

      String.try_convert(value) or
        raise TypeError, no_implicit_conversion(value, "String")
    end

    # rb_nkf_enc_get: the Ruby encoding that an nkf encoding name
    # represents, else the one that its base encoding name represents.
    def self.ruby_encoding(name)
      Encoding.find(name)
    rescue ArgumentError
      id = ENCODING_IDS[name.upcase]
      id ? Encoding.find(ENCODINGS[id].base.name) : Encoding::BINARY
    end

    def initialize
      @input_code_list = [
        InputCode.new("EUC-JP", 0, 0, 0, [0, 0, 0], :e_status, :e_iconv),
        InputCode.new("Shift_JIS", 0, 0, 0, [0, 0, 0], :s_status, :s_iconv),
        InputCode.new("UTF-8", 0, 0, 0, [0, 0, 0], :w_status, :w_iconv),
        InputCode.new("UTF-16", 0, 0, 0, [0, 0, 0], nil, :w_iconv16),
        InputCode.new("UTF-32", 0, 0, 0, [0, 0, 0], nil, :w_iconv32)
      ]
      @std_gc_buf = []
      @broken_buf = []
      @nfc_buf = []
      @hold_buf = []
      @mime_input_buf = Array.new(MIME_BUF_SIZE, 0)
      @mimeout_buf = Array.new(MIMEOUT_BUF_LENGTH + 2, 0)
      @iconv = nil
      @oconv = nil
      reinit
    end

    # NKF.nkf once the options are read.
    def convert(src)
      raise ArgumentError, "no output encoding given" unless @output_encoding

      case @output_encoding.id
      when UTF_8_BOM then @output_encoding = ENCODINGS[UTF_8]
      when UTF_16BE_BOM then @output_encoding = ENCODINGS[UTF_16BE]
      when UTF_16LE_BOM then @output_encoding = ENCODINGS[UTF_16LE]
      when UTF_32BE_BOM then @output_encoding = ENCODINGS[UTF_32BE]
      when UTF_32LE_BOM then @output_encoding = ENCODINGS[UTF_32LE]
      end
      @output_bom_f = false
      @input = src.bytes
      @input_pos = 0
      @output = String.new(capacity: @input.size * 3 + 10, encoding: Encoding::BINARY)
      kanji_convert
      encoding = @mimeout_f == FALSE ? Converter.ruby_encoding(@output_encoding.name) : Encoding::US_ASCII
      @output.force_encoding(encoding)
    end

    # NKF.guess.
    def guess(src)
      @input = src.bytes
      @input_pos = 0
      @output = String.new(encoding: Encoding::BINARY)
      @guess_f = TRUE
      kanji_convert
      Converter.ruby_encoding(get_guessed_code)
    end

    private

    # reinit: every option and every piece of state at its default.
    def reinit
      @std_gc_buf.clear
      @broken_buf.clear
      @nfc_buf.clear
      @input_code_list.each { |p| status_reinit(p) }
      @unbuf_f = false
      @estab_f = FALSE
      @nop_f = FALSE
      @rot_f = false
      @hira_f = 0
      @alpha_f = 0
      @mime_f = STRICT_MIME
      @mime_decode_f = false
      @mimebuf_f = FALSE
      @broken_f = 0
      @iso8859_f = false
      @mimeout_f = FALSE
      @x0201_f = NKF_UNSPECIFIED
      @iso2022jp_f = false
      @ms_ucs_map_f = UCS_MAP_ASCII
      @no_cp932ext_f = false
      @no_best_fit_chars_f = false
      @encode_fallback = nil
      @unicode_subchar = "?".ord
      @input_endian = ENDIAN_BIG
      @input_bom_f = false
      @output_bom_f = false
      @output_endian = ENDIAN_BIG
      @nfc_f = false
      @cap_f = false
      @url_f = false
      @numchar_f = false
      @noout_f = false
      @debug_f = false
      @guess_f = 0
      @cp51932_f = true
      @cp932inv_f = TRUE
      @x0212_f = false
      @x0213_f = false
      @prefix_table = Array.new(256, 0)
      @hold_count = 0
      @mimeout_count = 0
      @mimeout_mode = 0
      @base64_count = 0
      @f_line = 0
      @f_prev = 0
      @fold_preserve_f = false
      @fold_f = false
      @fold_len = 0
      @kanji_intro = DEFAULT_J
      @ascii_intro = DEFAULT_R
      @fold_margin = FOLD_MARGIN
      @o_zconv = @o_fconv = @o_eol_conv = @o_rot_conv = @o_hira_conv = nil
      @o_base64conv = @o_iso2022jp_check_conv = nil
      @o_putc = :std_putc
      @i_getc = :std_getc
      @i_ungetc = :std_ungetc
      @i_bgetc = :std_getc
      @i_bungetc = :std_ungetc
      @o_mputc = :std_putc
      @i_mgetc = :std_getc
      @i_mungetc = :std_ungetc
      @i_mgetc_buf = :std_getc
      @i_mungetc_buf = :std_ungetc
      @i_cgetc = @i_cungetc = @i_ugetc = @i_uungetc = nil
      @i_ngetc = @i_nungetc = @i_nfc_getc = @i_nfc_ungetc = nil
      @output_mode = ASCII
      @input_mode = ASCII
      @mime_decode_mode = FALSE
      @eolmode_f = 0
      @input_eol = 0
      @prev_cr = 0
      @option_mode = 0
      @z_prev2 = 0
      @z_prev1 = 0
      @iconv_for_check = nil
      @input_codename = nil
      @input_encoding = nil
      @output_encoding = nil
      @broken_state = 0
      @base64_state = 0
      @mime_top = 0
      @mime_last = 0
      @mime_input = 0
      @mime_iconv_back = nil
    end

    # The chain links, sent to by name.
    def i_getc = __send__(@i_getc)
    def i_ungetc(c) = __send__(@i_ungetc, c)
    def o_putc(c) = __send__(@o_putc, c)
    def oconv(c2, c1) = __send__(@oconv, c2, c1)
    def iconv(c2, c1, c0) = __send__(@iconv, c2, c1, c0)

    def debug(str)
      $stderr.write("#{str || "NULL"}\n") if @debug_f
    end

    # Character classes, as nkf.c's macros test them.
    def alnum?(c) = (0x61 <= c && c <= 0x7a) || (0x41 <= c && c <= 0x5a) || (0x30 <= c && c <= 0x39)
    def digit?(c) = 0x30 <= c && c <= 0x39
    def xdigit?(c) = digit?(c) || (0x61 <= c && c <= 0x66) || (0x41 <= c && c <= 0x46)
    def octal?(c) = 0x30 <= c && c <= 0x37
    def blank?(c) = c == SP || c == TAB
    def space?(c) = blank?(c) || c == CR || c == LF
    def graph?(c) = 0x21 <= c && c <= 0x7e
    def print?(c) = SP <= c && c <= 0x7e
    def toupper(c) = 0x61 <= c && c <= 0x7a ? c - 0x20 : c
    def hex2bin(c) = digit?(c) ? c - 0x30 : (0x41 <= c && c <= 0x46) ? c - 0x37 : (0x61 <= c && c <= 0x66) ? c - 0x57 : 0
    def bin2hex(c) = "0123456789ABCDEF".getbyte(c & 15)
    def eucg3?(c2) = ((c2 & 0xFFFF) >> 8) == SS3
    def ibmext_in_sjis?(c2) = 0xFA <= c2 && c2 <= 0xFC
    def unicode_new(c) = c | CLASS_UNICODE
    def unicode_p?(c) = (c & CLASS_MASK) == CLASS_UNICODE
    def unicode_bmp_p?(c) = (c & VALUE_MASK) <= UNICODE_BMP_MAX
    def unicode_value_p?(c) = (c & VALUE_MASK) <= UNICODE_MAX
    def utf16_to_utf32(lead, trail) = (lead << 10) + trail - 0x35FDC00

    def noescape_mime?(c)
      c == CR || c == LF || (c > SP && c < DEL && c != 0x3f && c != 0x3d && c != 0x5f &&
                             c != 0x28 && c != 0x29 && c != 0x2e && c != 0x22)
    end

    # A cell of a table, 0 where C would read past its end.
    def cell(row, index) = row && index >= 0 ? row[index] || 0 : 0

    # A cell of a two-dimensional table of 189 columns. C reads a column
    # past a row's end from the next row, and one before its start from
    # the row before, so the index runs over the whole table.
    def grid(name, row, column)
      rows = Tables[name]
      flat = row * 189 + column
      flat >= 0 && flat < rows.size * 189 ? rows[flat / 189][flat % 189] : 0
    end

    def enc_find(name)
      name = name.byteslice(2..) if name.start_with?("X-")
      id = ENCODING_IDS[name.upcase]
      id && ENCODINGS[id]
    end

    # --- Options ------------------------------------------------------

    public

    # nkf_split_options: the option string cut at spaces, with shell-like
    # quotes and backslashes, each piece read by `options`.
    def nkf_split_options(arg)
      option = []
      single_quoted = double_quoted = escaped = false
      arg.each do |byte|
        return if option.size == 255

        if single_quoted
          byte == 0x27 ? single_quoted = false : option << byte
        elsif escaped
          escaped = false
          option << byte
        elsif byte == 0x5c
          escaped = true
        elsif double_quoted
          byte == 0x22 ? double_quoted = false : option << byte
        elsif byte == 0x27
          single_quoted = true
        elsif byte == 0x22
          double_quoted = true
        elsif byte == SP
          options(option)
          option = []
        else
          option << byte
        end
      end
      options(option) unless option.empty?
    end

    private

    # options: one piece of the option string. A piece nkf does not know
    # ends the piece, as the C returns -1.
    def options(text)
      return if @option_mode == 1

      pos = 0
      at = ->(i) { text[i] || 0 }
      while at.(pos) != 0
        c = text[pos]
        pos += 1
        break if c == 0x2d
      end
      back = nil
      loop do
        if at.(pos) == 0
          break unless back

          text, pos = back
          at = ->(i) { text[i] || 0 }
          back = nil
          next
        end
        c = text[pos]
        pos += 1
        case c
        when 0x2d # --long-option
          if at.(pos) == 0 || at.(pos) == SP
            @option_mode = 1
            return
          end
          found = nil
          value = nil
          LONG_OPTIONS.each do |name_bytes, name, alias_bytes|
            j = 0
            j += 1 while j < name_bytes.size && name_bytes[j] != 0x3d && name_bytes[j] == at.(pos + j)
            if (name_bytes[j] || 0) == at.(pos + j) || at.(pos + j) == SP
              found = [name, alias_bytes]
              value = text[(pos + j + 1)..] || []
              break
            end
          end
          return unless found

          pos += 1 while at.(pos) != 0 && at.(pos) != SP
          name, alias_bytes = found
          unless alias_bytes.empty?
            back = [text, pos]
            text = alias_bytes
            at = ->(i) { text[i] || 0 }
            pos = 0
            next
          end
          return unless long_option(name, value)
        when 0x62 then @unbuf_f = false # b
        when 0x75 then @unbuf_f = true # u
        when 0x74 # t
          if at.(pos) == 0x31
            pos += 1
            @nop_f = TRUE
          elsif at.(pos) == 0x32
            pos += 1
            @nop_f = 2
          else
            @nop_f = TRUE
          end
        when 0x6a, 0x6e then @output_encoding = ENCODINGS[ISO_2022_JP] # j n
        when 0x65 then @output_encoding = ENCODINGS[EUCJP_NKF] # e
        when 0x73 then @output_encoding = ENCODINGS[SHIFT_JIS] # s
        when 0x6c # l
          @iso8859_f = true
          @input_encoding = ENCODINGS[ISO_8859_1]
        when 0x69 # i
          if at.(pos) == 0x40 || at.(pos) == 0x42
            @kanji_intro = text[pos]
            pos += 1
          end
        when 0x6f # o
          if at.(pos) == 0x4a || at.(pos) == 0x42 || at.(pos) == 0x48
            @ascii_intro = text[pos]
            pos += 1
          end
        when 0x68 # h
          if digit?(at.(pos))
            @hira_f |= text[pos] - 0x30
            pos += 1
          else
            @hira_f |= 1
          end
        when 0x72 then @rot_f = true # r
        when 0x77 then pos = utf_output_option(text, pos) # w
        when 0x57 then pos = utf_input_option(text, pos) # W
        when 0x4a then @input_encoding = ENCODINGS[ISO_2022_JP] # J
        when 0x45 then @input_encoding = ENCODINGS[EUCJP_NKF] # E
        when 0x53 then @input_encoding = ENCODINGS[SHIFT_JIS] # S
        when 0x5a # Z
          while 0x30 <= at.(pos) && at.(pos) <= 0x34
            @alpha_f |= 1 << (text[pos] - 0x30)
            pos += 1
          end
          @alpha_f |= 1
        when 0x78 then @x0201_f = FALSE # x
        when 0x58 then @x0201_f = TRUE # X
        when 0x46, 0x66 # F f
          @fold_preserve_f = true if c == 0x46
          @fold_f = true
          @fold_len = 0
          while digit?(at.(pos))
            @fold_len = @fold_len * 10 + text[pos] - 0x30
            pos += 1
          end
          @fold_len = DEFAULT_FOLD unless 0 < @fold_len && @fold_len < BUFSIZ
          if at.(pos) == 0x2d
            @fold_margin = 0
            pos += 1
            while digit?(at.(pos))
              @fold_margin = @fold_margin * 10 + text[pos] - 0x30
              pos += 1
            end
          end
        when 0x6d # m
          case at.(pos)
          when 0x42, 0x51
            @mime_decode_mode = text[pos]
            pos += 1
            @mimebuf_f = FIXED_MIME
          when 0x4e
            @mime_f = TRUE
            pos += 1
          when 0x53
            @mime_f = STRICT_MIME
            pos += 1
          when 0x30
            @mime_decode_f = false
            @mime_f = FALSE
            pos += 1
          else
            @mime_f = STRICT_MIME
          end
        when 0x4d # M
          case at.(pos)
          when 0x42, 0x51
            @mimeout_mode = text[pos]
            @mimeout_f = FIXED_MIME
            pos += 1
          else
            @mimeout_f = TRUE
          end
        when 0x42 # B
          if digit?(at.(pos))
            @broken_f |= 1 << (text[pos] - 0x30)
            pos += 1
          else
            @broken_f |= TRUE
          end
        when 0x63 then @eolmode_f = CRLF # c
        when 0x64 then @eolmode_f = LF # d
        when 0x49 then @iso2022jp_f = true # I
        when 0x4c # L
          case at.(pos)
          when 0x75 then @eolmode_f = LF
          when 0x6d then @eolmode_f = CR
          when 0x77 then @eolmode_f = CRLF
          when 0x30 then @eolmode_f = 0
          end
          pos += 1 if [0x75, 0x6d, 0x77, 0x30].include?(at.(pos))
        when SP
          while at.(pos) != 0
            c = text[pos]
            pos += 1
            break if c == 0x2d
          end
        else
          return
        end
      end
    end

    # A long option handled by name. False for one Ruby's nkf refuses.
    def long_option(name, value)
      case name
      when "ic="
        enc = enc_find(value.pack("C*"))
        @input_encoding = enc if enc
      when "oc="
        enc = enc_find(value.pack("C*"))
        @output_encoding = enc if enc
      when "guess="
        @guess_f = value[0] == 0x30 || value[0] == 0x31 ? 1 : 2
      when "cap-input" then @cap_f = true
      when "url-input" then @url_f = true
      when "numchar-input" then @numchar_f = true
      when "no-output" then @noout_f = true
      when "debug" then @debug_f = true
      when "cp932"
        @cp51932_f = true
        @cp932inv_f = -TRUE
        @ms_ucs_map_f = UCS_MAP_CP932
      when "no-cp932"
        @cp51932_f = false
        @cp932inv_f = FALSE
        @ms_ucs_map_f = UCS_MAP_ASCII
      when "cp932inv" then @cp932inv_f = -TRUE
      when "x0212" then @x0212_f = true
      when "no-cp932ext" then @no_cp932ext_f = true
      when "no-best-fit-chars" then @no_best_fit_chars_f = true
      when "fb-skip" then @encode_fallback = nil
      when "fb-html" then @encode_fallback = :encode_fallback_html
      when "fb-xml" then @encode_fallback = :encode_fallback_xml
      when "fb-java" then @encode_fallback = :encode_fallback_java
      when "fb-perl" then @encode_fallback = :encode_fallback_perl
      when "fb-subchar" then @encode_fallback = :encode_fallback_subchar
      when "fb-subchar=" then subchar_option(value)
      when "ms-ucs-map" then @ms_ucs_map_f = UCS_MAP_MS
      when "utf8mac-input" then @nfc_f = true
      when "prefix="
        if graph?(value[0] || 0)
          i = 1
          while graph?(value[i] || 0)
            @prefix_table[value[i]] = value[0]
            i += 1
          end
        end
      else
        return false
      end
      true
    end

    # --fb-subchar=N, in decimal, 0x hex or 0 octal.
    def subchar_option(value)
      at = ->(i) { value[i] || 0 }
      @encode_fallback = :encode_fallback_subchar
      @unicode_subchar = 0
      if at.(0) != 0x30
        i = 0
        while i < 7 && digit?(at.(i))
          @unicode_subchar = @unicode_subchar * 10 + hex2bin(at.(i))
          i += 1
        end
      elsif at.(1) == 0x78 || at.(1) == 0x58
        i = 2
        while i < 8 && xdigit?(at.(i))
          @unicode_subchar = (@unicode_subchar << 4) | hex2bin(at.(i))
          i += 1
        end
      else
        i = 1
        while i < 8 && octal?(at.(i))
          @unicode_subchar = @unicode_subchar * 8 + hex2bin(at.(i))
          i += 1
        end
      end
      _, c2, c1 = w16e_conv(@unicode_subchar)
      @unicode_subchar = (c2 << 8) | c1
    end

    # -w[8[0]|16|32][B|L][0]
    def utf_output_option(text, pos)
      at = ->(i) { text[i] || 0 }
      if at.(pos) == 0x38
        pos += 1
        if at.(pos) == 0x30
          pos += 1
          @output_encoding = ENCODINGS[UTF_8N]
        else
          @output_bom_f = true
          @output_encoding = ENCODINGS[UTF_8_BOM]
        end
        return pos
      end
      if at.(pos) == 0x31 && at.(pos + 1) == 0x36
        pos += 2
        enc_idx = UTF_16
      elsif at.(pos) == 0x33 && at.(pos + 1) == 0x32
        pos += 2
        enc_idx = UTF_32
      else
        @output_encoding = ENCODINGS[UTF_8]
        return pos
      end
      if at.(pos) == 0x4c
        pos += 1
        @output_endian = ENDIAN_LITTLE
        @output_bom_f = true
      elsif at.(pos) == 0x42
        pos += 1
        @output_bom_f = true
      end
      little = @output_endian == ENDIAN_LITTLE
      if at.(pos) == 0x30
        @output_bom_f = false
        pos += 1
        enc_idx = enc_idx == UTF_16 ? (little ? UTF_16LE : UTF_16BE) : (little ? UTF_32LE : UTF_32BE)
      else
        enc_idx = enc_idx == UTF_16 ? (little ? UTF_16LE_BOM : UTF_16BE_BOM) : (little ? UTF_32LE_BOM : UTF_32BE_BOM)
      end
      @output_encoding = ENCODINGS[enc_idx]
      pos
    end

    # -W[8|16|32][B|L]
    def utf_input_option(text, pos)
      at = ->(i) { text[i] || 0 }
      if at.(pos) == 0x38
        @input_encoding = ENCODINGS[UTF_8]
        return pos + 1
      end
      if at.(pos) == 0x31 && at.(pos + 1) == 0x36
        pos += 2
        @input_endian = ENDIAN_BIG
        enc_idx = UTF_16
      elsif at.(pos) == 0x33 && at.(pos + 1) == 0x32
        pos += 2
        @input_endian = ENDIAN_BIG
        enc_idx = UTF_32
      else
        @input_encoding = ENCODINGS[UTF_8]
        return pos
      end
      if at.(pos) == 0x4c
        pos += 1
        @input_endian = ENDIAN_LITTLE
      elsif at.(pos) == 0x42
        pos += 1
        @input_endian = ENDIAN_BIG
      end
      little = @input_endian == ENDIAN_LITTLE
      @input_encoding = ENCODINGS[enc_idx == UTF_16 ? (little ? UTF_16LE : UTF_16BE) : (little ? UTF_32LE : UTF_32BE)]
      pos
    end

    def set_input_encoding(enc)
      case enc.id
      when ISO_8859_1
        @iso8859_f = true
      when CP50221, CP50222, CP50220
        @x0201_f = FALSE if enc.id != CP50220 && @x0201_f == NKF_UNSPECIFIED
        @cp51932_f = true
        @ms_ucs_map_f = UCS_MAP_CP932
      when ISO_2022_JP_1
        @x0212_f = true
      when ISO_2022_JP_3, ISO_2022_JP_2004
        @x0212_f = true
        @x0213_f = true
      when WINDOWS_31J
        @x0201_f = FALSE if @x0201_f == NKF_UNSPECIFIED
        @cp51932_f = true
        @ms_ucs_map_f = UCS_MAP_CP932
      when CP10001
        @cp51932_f = true
        @ms_ucs_map_f = UCS_MAP_CP10001
      when CP51932
        @x0201_f = FALSE if @x0201_f == NKF_UNSPECIFIED
        @cp51932_f = true
        @ms_ucs_map_f = UCS_MAP_CP932
      when EUCJP_MS
        @x0201_f = FALSE if @x0201_f == NKF_UNSPECIFIED
        @cp51932_f = false
        @ms_ucs_map_f = UCS_MAP_MS
      when EUCJP_ASCII
        @x0201_f = FALSE if @x0201_f == NKF_UNSPECIFIED
        @cp51932_f = false
        @ms_ucs_map_f = UCS_MAP_ASCII
      when SHIFT_JISX0213, SHIFT_JIS_2004
        @x0213_f = true
        @cp51932_f = false
        @cp932inv_f = FALSE if @cp932inv_f == TRUE
      when EUC_JISX0213, EUC_JIS_2004
        @x0213_f = true
        @cp51932_f = false
      when UTF8_MAC
        @nfc_f = true
      when UTF_16, UTF_16BE, UTF_16BE_BOM, UTF_32, UTF_32BE, UTF_32BE_BOM
        @input_endian = ENDIAN_BIG
      when UTF_16LE, UTF_16LE_BOM, UTF_32LE, UTF_32LE_BOM
        @input_endian = ENDIAN_LITTLE
      end
    end

    def set_output_encoding(enc)
      case enc.id
      when CP50220
        @cp932inv_f = FALSE if @cp932inv_f == TRUE
        @ms_ucs_map_f = UCS_MAP_CP932
      when CP50221
        @x0201_f = FALSE if @x0201_f == NKF_UNSPECIFIED
        @cp932inv_f = FALSE if @cp932inv_f == TRUE
        @ms_ucs_map_f = UCS_MAP_CP932
      when ISO_2022_JP
        @cp932inv_f = FALSE if @cp932inv_f == TRUE
      when ISO_2022_JP_1
        @x0212_f = true
        @cp932inv_f = FALSE if @cp932inv_f == TRUE
      when ISO_2022_JP_3, ISO_2022_JP_2004
        @x0212_f = true
        @x0213_f = true
        @cp932inv_f = FALSE if @cp932inv_f == TRUE
      when WINDOWS_31J
        @x0201_f = FALSE if @x0201_f == NKF_UNSPECIFIED
        @ms_ucs_map_f = UCS_MAP_CP932
      when CP10001
        @ms_ucs_map_f = UCS_MAP_CP10001
      when EUC_JP
        @x0212_f = true
        @cp932inv_f = FALSE if @cp932inv_f == TRUE
        @ms_ucs_map_f = UCS_MAP_ASCII
      when EUCJP_NKF
        @x0212_f = false
        @cp932inv_f = FALSE if @cp932inv_f == TRUE
        @ms_ucs_map_f = UCS_MAP_ASCII
      when CP51932
        @x0201_f = FALSE if @x0201_f == NKF_UNSPECIFIED
        @cp932inv_f = FALSE if @cp932inv_f == TRUE
        @ms_ucs_map_f = UCS_MAP_CP932
      when EUCJP_MS
        @x0201_f = FALSE if @x0201_f == NKF_UNSPECIFIED
        @x0212_f = true
        @ms_ucs_map_f = UCS_MAP_MS
      when EUCJP_ASCII
        @x0201_f = FALSE if @x0201_f == NKF_UNSPECIFIED
        @x0212_f = true
        @ms_ucs_map_f = UCS_MAP_ASCII
      when SHIFT_JISX0213, SHIFT_JIS_2004
        @x0213_f = true
        @cp932inv_f = FALSE if @cp932inv_f == TRUE
      when EUC_JISX0213, EUC_JIS_2004
        @x0212_f = true
        @x0213_f = true
        @cp932inv_f = FALSE if @cp932inv_f == TRUE
      when UTF_8_BOM, UTF_16, UTF_16BE_BOM, UTF_32, UTF_32BE_BOM
        @output_bom_f = true
      when UTF_16LE, UTF_32LE
        @output_endian = ENDIAN_LITTLE
        @output_bom_f = false
      when UTF_16LE_BOM, UTF_32LE_BOM
        @output_endian = ENDIAN_LITTLE
        @output_bom_f = true
      end
    end

    def find_inputcode_byfunc(iconv_func)
      iconv_func && @input_code_list.find { |p| p.iconv_func == iconv_func }
    end

    # set_iconv: `f` is FALSE, TRUE, or -TRUE to force the input decoder
    # even when the options fixed the input encoding.
    def set_iconv(f, iconv_func)
      @estab_f = f if f != FALSE || !@input_encoding
      @iconv = iconv_func if iconv_func && (f == -TRUE || !@input_encoding)
      return unless @estab_f != FALSE && @iconv_for_check != @iconv

      p = find_inputcode_byfunc(@iconv)
      if p
        set_input_codename(p.name)
        debug(p.name)
      end
      @iconv_for_check = @iconv
    end

    def set_input_codename(codename)
      if @input_codename.nil?
        @input_codename = codename
      elsif codename != @input_codename
        @input_codename = ""
      end
    end

    def get_guessed_code
      if @input_codename && @input_codename.empty?
        @input_codename = "BINARY"
      else
        p = find_inputcode_byfunc(@iconv)
        if @input_codename.nil?
          @input_codename = "ASCII"
        elsif @input_codename == "Shift_JIS"
          @input_codename = "CP932" if p.score & (SCORE_DEPEND | SCORE_CP932) != 0
        elsif @input_codename == "EUC-JP"
          if p.score & SCORE_X0213 != 0
            @input_codename = "EUC-JIS-2004"
          elsif p.score & SCORE_X0212 != 0
            @input_codename = "EUCJP-MS"
          elsif p.score & (SCORE_DEPEND | SCORE_CP932) != 0
            @input_codename = "CP51932"
          end
        elsif @input_codename == "ISO-2022-JP"
          if p.score & SCORE_KANA != 0
            @input_codename = "CP50221"
          elsif p.score & (SCORE_DEPEND | SCORE_CP932) != 0
            @input_codename = "CP50220"
          end
        end
      end
      @input_codename
    end

    # --- Code conversion primitives -----------------------------------
    #
    # A primitive that writes through pointers in C returns [ret, c2, c1]
    # here, with nil for a value it leaves unwritten.

    SJ0162 = 0x00e1
    SJ6394 = 0x0161
    SHIFT_JISX0213_S1A3_TABLE = [[1, 8], [3, 4], [5, 12], [13, 14], [15, 0]].freeze
    X0213_2_TABLE = [0, 1, 0, 1, 1, 1, 0, 0, 1, 0, 0, 0, 1, 1, 1, 1].freeze

    def x0212_shift(c)
      ret = c
      c &= 0x7f
      if eucg3?(ret)
        ret = c + (0x109 - 0x75) if 0x75 <= c && c <= 0x7f
      elsif 0x75 <= c && c <= 0x7f
        ret = c + (0x113 - 0x75)
      end
      ret
    end

    def x0212_unshift(c)
      if 0x7f <= c && c <= 0x88
        c + (0x75 - 0x7f)
      elsif 0x89 <= c && c <= 0x92
        PREFIX_EUCG3 | 0x80 | (c + (0x75 - 0x89))
      else
        c
      end
    end

    def x0213_2_in_x0212?(c1)
      ku = c1 - 0x20
      return X0213_2_TABLE[ku] == 1 if ku <= 15 && ku >= 0

      78 <= ku && ku <= 94
    end

    def sjis_trail(c2, c1) = c1 + (c2.odd? ? (c1 < 0x60 ? 0x1f : 0x20) : 0x7e)

    # EUC (JIS row and cell) to Shift_JIS.
    def e2s_conv(c2, c1)
      if eucg3?(c2)
        ndx = c2 & 0x7f
        if @x0213_f && x0213_2_in_x0212?(ndx)
          return [0, ((ndx - 1) >> 1) + 0xec - ndx / 8 * 3, sjis_trail(ndx, c1)] if 0x21 <= ndx && ndx <= 0x2F
          return [0, ((ndx - 1) >> 1) + 0xbe, sjis_trail(ndx, c1)] if 0x6E <= ndx && ndx <= 0x7E

          return [1, nil, nil]
        elsif graph?(ndx)
          val = cell(Tables[:x0212_shiftjis][ndx - 0x21], (c1 & 0x7f) - 0x21)
          return [0, val >> 8, val & 0xff] if val != 0

          c2 = x0212_shift(c2)
        end
      end
      return [1, nil, nil] if 0x7F < c2

      [0, ((c2 - 1) >> 1) + (c2 <= 0x5e ? 0x71 : 0xb1), sjis_trail(c2, c1)]
    end

    # Shift_JIS to EUC (JIS row and cell).
    def s2e_conv(c2, c1)
      return [1, nil, nil] if 0xFC < c1

      if @cp932inv_f == FALSE && !@x0213_f && ibmext_in_sjis?(c2)
        val = grid(:shiftjis_cp932, c2 - 0xFA, c1 - 0x40)
        if val != 0
          c2 = val >> 8
          c1 = val & 0xff
        end
      end
      if @cp932inv_f != FALSE && 0xED <= c2 && c2 <= 0xEE
        val = grid(:cp932inv, c2 - 0xED, c1 - 0x40)
        if val != 0
          c2 = val >> 8
          c1 = val & 0xff
        end
      end
      if !@x0213_f && ibmext_in_sjis?(c2)
        val = grid(:shiftjis_x0212, c2 - 0xfa, c1 - 0x40)
        if val != 0
          return [0, PREFIX_EUCG3 | ((val >> 8) & 0x7f), val & 0xff] if val > 0x7FFF

          return [0, val >> 8, val & 0xff]
        end
      end
      if c2 >= 0x80
        if @x0213_f && c2 >= 0xF0
          if c2 <= 0xF3 || (c2 == 0xF4 && c1 < 0x9F)
            c2 = PREFIX_EUCG3 | 0x20 | SHIFT_JISX0213_S1A3_TABLE[c2 - 0xF0][0x9E < c1 ? 1 : 0]
          else
            c2 = PREFIX_EUCG3 | (c2 * 2 - 0x17B)
            c2 += 1 if 0x9E < c1
          end
        else
          c2 = c2 + c2 - (c2 <= 0x9F ? SJ0162 : SJ6394)
          c2 += 1 if 0x9E < c1
        end
        c1 = c1 < 0x9F ? c1 - (c1 > DEL ? SP : 0x1F) : c1 - 0x7E
      end
      [0, x0212_unshift(c2), c1]
    end

    def nkf_unicode_to_utf8(val)
      val &= VALUE_MASK
      if val < 0x80
        [val, 0, 0, 0]
      elsif val < 0x800
        [0xc0 | (val >> 6), 0x80 | (val & 0x3f), 0, 0]
      elsif unicode_bmp_p?(val)
        [0xe0 | (val >> 12), 0x80 | ((val >> 6) & 0x3f), 0x80 | (val & 0x3f), 0]
      elsif unicode_value_p?(val)
        [0xf0 | (val >> 18), 0x80 | ((val >> 12) & 0x3f), 0x80 | ((val >> 6) & 0x3f), 0x80 | (val & 0x3f)]
      else
        [0, 0, 0, 0]
      end
    end

    # nkf_utf8_to_unicode, with the C's own tests (it checks the second
    # byte, not the first, for a four-byte sequence).
    def nkf_utf8_to_unicode(c1, c2, c3, c4)
      if c1 <= 0x7F
        c1
      elsif c1 <= 0xC1
        -1
      elsif c1 <= 0xDF
        ((c1 & 0x1F) << 6) | (c2 & 0x3F)
      elsif c1 <= 0xEF
        ((c1 & 0x0F) << 12) | ((c2 & 0x3F) << 6) | (c3 & 0x3F)
      elsif c2 <= 0xF4
        ((c1 & 0x0F) << 18) | ((c2 & 0x3F) << 12) | ((c3 & 0x3F) << 6) | (c4 & 0x3F)
      else
        -1
      end
    end

    def unicode_to_jis_common2(c1, c0, pp, psize)
      return [1, nil, nil] unless pp

      c1 -= 0x80
      return [1, nil, nil] if c1 < 0 || psize <= c1

      p = pp[c1]
      return [1, nil, nil] unless p

      c0 -= 0x80
      return [1, nil, nil] if c0 < 0 || 64 <= c0

      val = p[c0] || 0
      return [1, nil, nil] if val == 0
      return [1, nil, nil] if @no_cp932ext_f && ((val >> 8) == 0x2D || val > 0xF300)

      c2 = val >> 8
      c2 = (c2 & 0x7f) | PREFIX_EUCG3 if val > 0x7FFF
      c2 = JIS_X_0201_1976_K if c2 == SO
      [0, c2, val & 0xFF]
    end

    NO_BEST_FIT_C2 = [
      1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
      1, 1, 0, 0, 1, 0, 0, 0, 0, 1, 1, 1, 2, 1, 1, 2, 0, 0, 1, 1, 0, 1, 0, 1, 2, 1, 1, 1, 1, 1, 1, 1
    ].freeze
    NO_BEST_FIT_C2_MS = [
      1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
      1, 0, 1, 1, 0, 1, 1, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 1, 1, 0, 1, 0, 1, 0, 1, 0, 1, 1, 1, 1, 0
    ].freeze
    NO_BEST_FIT_932_C2 = [
      1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
      1, 1, 1, 1, 0, 1, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 0, 0, 1, 1, 0, 1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0
    ].freeze
    NO_BEST_FIT_932_C3 = [
      1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1,
      1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1
    ].freeze

    # A UTF-8 sequence (lead c2, then c1 and c0) to JIS.
    def unicode_to_jis_common(c2, c1, c0)
      if c2 < 0x80
        ret, p2, p1 = 0, 0, c2
      elsif c2 < 0xe0
        return [1, nil, nil] if @no_best_fit_chars_f && no_best_fit_2bytes?(c2, c1)

        pp = if @ms_ucs_map_f == UCS_MAP_CP932 then :utf8_to_euc_2bytes_932
             elsif @ms_ucs_map_f == UCS_MAP_MS then :utf8_to_euc_2bytes_ms
             elsif @ms_ucs_map_f == UCS_MAP_CP10001 then :utf8_to_euc_2bytes_mac
             elsif @x0213_f then :utf8_to_euc_2bytes_x0213
             else :utf8_to_euc_2bytes
             end
        ret, p2, p1 = unicode_to_jis_common2(c2, c1, Tables[pp], 112)
      elsif c0 < 0xF0
        return [1, nil, nil] if @no_best_fit_chars_f && no_best_fit_3bytes?(c2, c1, c0)

        ppp = if @ms_ucs_map_f == UCS_MAP_CP932 then :utf8_to_euc_3bytes_932
              elsif @ms_ucs_map_f == UCS_MAP_MS then :utf8_to_euc_3bytes_ms
              elsif @ms_ucs_map_f == UCS_MAP_CP10001 then :utf8_to_euc_3bytes_mac
              elsif @x0213_f then :utf8_to_euc_3bytes_x0213
              else :utf8_to_euc_3bytes
              end
        ret, p2, p1 = unicode_to_jis_common2(c1, c0, Tables[ppp][c2 - 0xE0], 64)
      else
        return [-1, nil, nil]
      end
      if ret == 0 && eucg3?(p2)
        if @cp932inv_f != FALSE
          ret = 1 if @encode_fallback
        else
          r, s2, s1 = e2s_conv(p2, p1)
          if r == 0
            r, t2, t1 = s2e_conv(s2, s1)
            p2, p1 = t2, t1 if r == 0
          else
            ret = 1
          end
        end
      end
      [ret, p2, p1]
    end

    def no_best_fit_2bytes?(c2, c1)
      if @ms_ucs_map_f == UCS_MAP_CP932
        (c2 == 0xC2 && NO_BEST_FIT_932_C2[c1 & 0x3F] != 0) || (c2 == 0xC3 && NO_BEST_FIT_932_C3[c1 & 0x3F] != 0)
      elsif @cp932inv_f == FALSE
        (c2 == 0xC2 && NO_BEST_FIT_C2[c1 & 0x3F] != 0) || (c2 == 0xC3 && NO_BEST_FIT_932_C3[c1 & 0x3F] != 0)
      elsif @ms_ucs_map_f == UCS_MAP_MS
        c2 == 0xC2 && NO_BEST_FIT_C2_MS[c1 & 0x3F] != 0
      elsif @ms_ucs_map_f == UCS_MAP_CP10001
        c2 == 0xC2 && [0xA2, 0xA3, 0xA5, 0xA6, 0xAC, 0xAF, 0xB8].include?(c1)
      else
        false
      end
    end

    def no_best_fit_3bytes?(c2, c1, c0)
      if @ms_ucs_map_f == UCS_MAP_CP932
        c2 == 0xE3 && c1 == 0x82 && c0 == 0x94
      elsif @ms_ucs_map_f == UCS_MAP_MS
        case c2
        when 0xE2 then (c1 == 0x80 && [0x94, 0x96, 0xBE].include?(c0)) || (c1 == 0x88 && c0 == 0x92)
        when 0xE3 then c1 == 0x80 || c0 == 0x9C
        else false
        end
      elsif @ms_ucs_map_f == UCS_MAP_CP10001
        c2 == 0xE3 && ((c1 == 0x82 && c0 == 0x94) || (c1 == 0x83 && c0 == 0xBB))
      else
        case c2
        when 0xE2 then (c1 == 0x80 && c0 == 0x95) || (c1 == 0x88 && c0 == 0xA5)
        when 0xEF
          (c1 == 0xBC && c0 == 0x8D) || (c1 == 0xBD && c0 == 0x9E && @cp932inv_f == FALSE) ||
            (c1 == 0xBF && 0xA0 <= c0 && c0 <= 0xA5)
        else false
        end
      end
    end

    # JIS (or a JIS X 0201 katakana) to a Unicode code point, 0 for none.
    def e2w_conv(c2, c1)
      from_x0212 = false
      if c2 == JIS_X_0201_1976_K
        if @ms_ucs_map_f == UCS_MAP_CP10001
          return 0xA0 if c1 == 0x20
          return 0xA9 if c1 == 0x7D
        end
        p = Tables[:euc_to_utf8_1byte]
      elsif eucg3?(c2)
        return 0xA6 if @ms_ucs_map_f == UCS_MAP_ASCII && c2 == 0x8F22 && c1 == 0x43

        c2 = (c2 & 0x7f) - 0x21
        return 0 unless 0 <= c2 && c2 < 94

        p = Tables[@x0213_f ? :x0212_to_utf8_2bytes_x0213 : :x0212_to_utf8_2bytes][c2]
        from_x0212 = @x0213_f
      else
        c2 = (c2 & 0x7f) - 0x21
        return 0 unless 0 <= c2 && c2 < 94

        name = if @x0213_f then :euc_to_utf8_2bytes_x0213
               elsif @ms_ucs_map_f == UCS_MAP_ASCII then :euc_to_utf8_2bytes
               elsif @ms_ucs_map_f == UCS_MAP_CP10001 then :euc_to_utf8_2bytes_mac
               else :euc_to_utf8_2bytes_ms
               end
        p = Tables[name][c2]
      end
      return 0 unless p

      c1 = (c1 & 0x7f) - 0x21
      return 0 unless 0 <= c1 && c1 < 94

      val = p[c1] || 0
      return val unless @x0213_f && 0xD800 <= val && val <= 0xDBFF

      euc = ((c2 + 0x21) << 8) | (c1 + 0x21)
      table = Tables[from_x0212 ? :x0213_2_surrogate_table : :x0213_1_surrogate_table]
      row = table.find { |entry| entry[0] == euc }
      row && row[2] != 0 ? utf16_to_utf32(val, row[2]) : 0
    end

    def e2w_combining(comb, c2, c1)
      return 0 unless Tables[:x0213_combining_chars].include?(comb)

      euc = ((c2 & 0x7f) << 8) | (c1 & 0x7f)
      row = Tables[:x0213_combining_table].find { |entry| entry[0] == euc }
      row ? row[1] : 0
    end

    # UTF-8 to JIS. The callers pass their own c2 and c1 as the pointers,
    # so an unwritten value stays what it was.
    def w2e_conv(c2, c1, c0)
      if c1 == 0
        [0, 0, c2]
      elsif 0xc0 <= c2 && c2 <= 0xef
        ret, p2, p1 = unicode_to_jis_common(c2, c1, c0)
        return [0, 0, unicode_new(nkf_utf8_to_unicode(c2, c1, c0, 0))] if ret > 0

        [ret, p2 || c2, p1 || c1]
      else
        [0, c2, c1]
      end
    end

    # A code point to JIS, or to itself marked as Unicode.
    def w16e_conv(val)
      val &= VALUE_MASK
      if val < 0x80
        [0, 0, val]
      elsif unicode_bmp_p?(val)
        c1, c2, c3, = nkf_unicode_to_utf8(val)
        ret, p2, p1 = unicode_to_jis_common(c1, c2, c3)
        ret > 0 ? [0, 0, unicode_new(val)] : [ret, p2, p1]
      else
        if @x0213_f
          high = (val >> 10) + 0xD7C0
          low = (val & 0x3FF) + 0xDC00
          row = Tables[:x0213_1_surrogate_table].find { |entry| entry[1] == high && entry[2] == low }
          return [0, row[0] >> 8, row[0] & 0xFF] if row

          row = Tables[:x0213_2_surrogate_table].find { |entry| entry[1] == high && entry[2] == low }
          return [0, PREFIX_EUCG3 | (row[0] >> 8), row[0] & 0xFF] if row
        end
        [0, 0, unicode_new(val)]
      end
    end

    def x0213_wait_combining_p(wc) = Tables[:x0213_combining_table].any? { |entry| entry[1] == wc }
    def x0213_combining_p(wc) = Tables[:x0213_combining_chars].include?(wc)

    # --- Input decoders -----------------------------------------------
    #
    # An iconv takes the bytes of one character and sends its internal
    # form to oconv. It returns 0 when it is done, -1 or -2 when it needs
    # one or two more bytes, -3 when it waits for a combining character,
    # and 16 or 32 for the UTF-16 and UTF-32 decoders, which kanji_convert
    # drives on their own.

    # EUC-JP, and ISO-2022-JP once its escapes are read.
    def e_iconv(c2, c1, c0)
      if c2 == JIS_X_0201_1976_K || c2 == SS2
        if @iso2022jp_f && @x0201_f == FALSE
          c2 = GETA1
          c1 = GETA2
        else
          c2 = JIS_X_0201_1976_K
          c1 &= 0x7f
        end
      elsif c2 == 0x8f
        return -1 if c0 == 0

        if !@cp51932_f && !@x0213_f && 0xF5 <= c1 && c1 <= 0xFE && 0xA1 <= c0 && c0 <= 0xFE
          # eucJP-ms user-defined characters, into the Private Use Area.
          c1 = unicode_new((c1 - 0xF5) * 94 + c0 - 0xA1 + 0xE3AC)
          c2 = 0
        else
          c2 = (c2 << 8) | (c1 & 0x7f)
          c1 = c0 & 0x7f
          c2, c1 = cp51932_invert(c2, c1) if @cp51932_f
        end
      elsif c2 == EOF || c2 == 0 || c2 < SP || c2 == ISO_8859_1
        # Nothing to decode.
      elsif !@cp51932_f && @ms_ucs_map_f != UCS_MAP_ASCII && 0xF5 <= c2 && c2 <= 0xFE && 0xA1 <= c1 && c1 <= 0xFE
        c1 = unicode_new((c2 - 0xF5) * 94 + c1 - 0xA1 + 0xE000)
        c2 = 0
      else
        c1 &= 0x7f
        c2 &= 0x7f
        c2, c1 = cp51932_invert(c2, c1) if @cp51932_f && 0x79 <= c2 && c2 <= 0x7c
      end
      oconv(c2, c1)
      0
    end

    # A CP51932 character, through Shift_JIS and back, onto the codes
    # CP932 prefers.
    def cp51932_invert(c2, c1)
      ret, s2, s1 = e2s_conv(c2, c1)
      return [c2, c1] unless ret == 0

      ret, t2, t1 = s2e_conv(s2, s1)
      return [c2, c1] unless ret == 0

      t2 < 0x100 ? [t2 & 0x7f, t1 & 0x7f] : [t2, t1]
    end

    def s_iconv(c2, c1, _c0)
      if c2 == JIS_X_0201_1976_K || (0xA1 <= c2 && c2 <= 0xDF)
        if @iso2022jp_f && @x0201_f == FALSE
          c2 = GETA1
          c1 = GETA2
        else
          c1 &= 0x7f
        end
      elsif c2 == EOF || c2 == 0 || c2 < SP
        # Nothing to decode.
      elsif !@x0213_f && 0xF0 <= c2 && c2 <= 0xF9 && 0x40 <= c1 && c1 <= 0xFC
        # CP932 user-defined characters.
        return 0 if c1 == 0x7F

        c1 = unicode_new((c2 - 0xF0) * 188 + (c1 - 0x40 - (0x7E < c1 ? 1 : 0)) + 0xE000)
        c2 = 0
      else
        ret, p2, p1 = s2e_conv(c2, c1)
        return ret if ret != 0

        c2 = p2
        c1 = p1
      end
      oconv(c2, c1)
      0
    end

    W_ICONV_UTF8_1ST_BYTE = [
      20, 20, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21,
      21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21,
      30, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 32, 33, 33,
      40, 41, 41, 41, 42, 43, 43, 43, 50, 50, 50, 50, 60, 60, 70, 70
    ].freeze

    def w_iconv(c1, c2, c3)
      ret = 0
      c4 = 0
      if c3 > 0xFF
        c4 = c3 & 0xFF
        c3 >>= 8
      end
      if c1 < 0 || 0xff < c1
        # A marker, not a byte.
      elsif c1 == 0
        c3 = 0
      elsif (c1 & 0xC0) == 0x80
        return 0
      else
        kind = c1 >= 0xC0 ? W_ICONV_UTF8_1ST_BYTE[c1 - 0xC0] : nil
        case kind
        when 21
          return 0 if c2 < 0x80 || 0xBF < c2
        when 30
          return -1 if c3 == 0
          return 0 if c2 < 0xA0 || 0xBF < c2 || (c3 & 0xC0) != 0x80
        when 31, 33
          return -1 if c3 == 0
          return 0 if (c2 & 0xC0) != 0x80 || (c3 & 0xC0) != 0x80
        when 32
          return -1 if c3 == 0
          return 0 if c2 < 0x80 || 0x9F < c2 || (c3 & 0xC0) != 0x80
        when 40
          return -2 if c3 == 0
          return 0 if c2 < 0x90 || 0xBF < c2 || (c3 & 0xC0) != 0x80 || (c4 & 0xC0) != 0x80
        when 41
          return -2 if c3 == 0
          return 0 if c2 < 0x80 || 0xBF < c2 || (c3 & 0xC0) != 0x80 || (c4 & 0xC0) != 0x80
        when 42
          return -2 if c3 == 0
          return 0 if c2 < 0x80 || 0x8F < c2 || (c3 & 0xC0) != 0x80 || (c4 & 0xC0) != 0x80
        else
          return 0
        end
      end
      if c1 == 0 || c1 == EOF
        # ASCII or the end passes through.
      elsif (c1 & 0xf8) == 0xf0
        c2 = unicode_new(nkf_utf8_to_unicode(c1, c2, c3, c4))
        c1 = 0
      else
        return -3 if @x0213_f && x0213_wait_combining_p(nkf_utf8_to_unicode(c1, c2, c3, c4))

        ret, c1, c2 = w2e_conv(c1, c2, c3)
      end
      oconv(c1, c2) if ret == 0
      ret
    end

    def w_iconv_nocombine(c1, c2, c3)
      ret, c1, c2 = w2e_conv(c1, c2, c3)
      oconv(c1, c2) if ret == 0
      ret
    end

    def unicode_iconv(wc, nocombine)
      if wc < 0x80
        c2 = 0
        c1 = wc
      elsif (wc >> 11) == 27
        return NKF_ICONV_INVALID_CODE_RANGE
      elsif wc < 0xFFFF
        return NKF_ICONV_WAIT_COMBINING_CHAR if !nocombine && @x0213_f && x0213_wait_combining_p(wc)

        ret, c2, c1 = w16e_conv(wc)
        return ret if ret != 0
      elsif wc < 0x10FFFF
        c2 = 0
        c1 = unicode_new(wc)
      else
        return NKF_ICONV_INVALID_CODE_RANGE
      end
      oconv(c2, c1)
      0
    end

    def unicode_iconv_combine(wc, wc2)
      if wc2 < 0x80
        NKF_ICONV_NOT_COMBINED
      elsif (wc2 >> 11) == 27
        NKF_ICONV_INVALID_CODE_RANGE
      elsif wc2 < 0xFFFF
        return NKF_ICONV_NOT_COMBINED unless x0213_combining_p(wc2)

        row = Tables[:x0213_combining_table].find { |entry| entry[1] == wc && entry[2] == wc2 }
        return NKF_ICONV_NOT_COMBINED unless row

        oconv(row[0] >> 8, row[0] & 0x7f)
        0
      elsif wc2 < 0x10FFFF
        NKF_ICONV_NOT_COMBINED
      else
        NKF_ICONV_INVALID_CODE_RANGE
      end
    end

    def w_iconv_combine(c1, c2, c3, c4, c5, c6)
      wc = nkf_utf8_to_unicode(c1, c2, c3, 0)
      wc2 = nkf_utf8_to_unicode(c4, c5, c6, 0)
      return wc2 if wc2 < 0

      unicode_iconv_combine(wc, wc2)
    end

    def nkf_iconv_utf_16(c1, c2, c3, c4)
      if c1 == EOF
        oconv(EOF, 0)
        return 0
      end
      if @input_endian == ENDIAN_BIG
        if 0xD8 <= c1 && c1 <= 0xDB
          return NKF_ICONV_NEED_TWO_MORE_BYTES unless 0xDC <= c3 && c3 <= 0xDF

          wc = utf16_to_utf32((c1 << 8) | c2, (c3 << 8) | c4)
        else
          wc = (c1 << 8) | c2
        end
      elsif 0xD8 <= c2 && c2 <= 0xDB
        return NKF_ICONV_NEED_TWO_MORE_BYTES unless 0xDC <= c4 && c4 <= 0xDF

        wc = utf16_to_utf32((c2 << 8) | c1, (c4 << 8) | c3)
      else
        wc = (c2 << 8) | c1
      end
      unicode_iconv(wc, false)
    end

    def nkf_iconv_utf_16_combine(c1, c2, c3, c4)
      if @input_endian == ENDIAN_BIG
        return NKF_ICONV_NOT_COMBINED if 0xD8 <= c3 && c3 <= 0xDB

        unicode_iconv_combine((c1 << 8) | c2, (c3 << 8) | c4)
      else
        return NKF_ICONV_NOT_COMBINED if 0xD8 <= c2 && c2 <= 0xDB

        unicode_iconv_combine((c2 << 8) | c1, (c4 << 8) | c3)
      end
    end

    def nkf_iconv_utf_16_nocombine(c1, c2)
      unicode_iconv(@input_endian == ENDIAN_BIG ? (c1 << 8) | c2 : (c2 << 8) | c1, true)
    end

    def w_iconv16(c2, c1, _c0)
      oconv(c2, c1)
      16
    end

    def w_iconv32(c2, c1, _c0)
      oconv(c2, c1)
      32
    end

    def utf32_to_nkf_char(c1, c2, c3, c4)
      case @input_endian
      when ENDIAN_BIG then (c2 << 16) | (c3 << 8) | c4
      when ENDIAN_LITTLE then (c3 << 16) | (c2 << 8) | c1
      when ENDIAN_2143 then (c1 << 16) | (c4 << 8) | c3
      when ENDIAN_3412 then (c4 << 16) | (c1 << 8) | c2
      else NKF_ICONV_INVALID_CODE_RANGE
      end
    end

    def nkf_iconv_utf_32(c1, c2, c3, c4)
      if c1 == EOF
        oconv(EOF, 0)
        return 0
      end
      wc = utf32_to_nkf_char(c1, c2, c3, c4)
      return wc if wc < 0

      unicode_iconv(wc, false)
    end

    def nkf_iconv_utf_32_combine(c1, c2, c3, c4, c5, c6, c7, c8)
      wc = utf32_to_nkf_char(c1, c2, c3, c4)
      return wc if wc < 0

      wc2 = utf32_to_nkf_char(c5, c6, c7, c8)
      return wc2 if wc2 < 0

      unicode_iconv_combine(wc, wc2)
    end

    def nkf_iconv_utf_32_nocombine(c1, c2, c3, c4)
      unicode_iconv(utf32_to_nkf_char(c1, c2, c3, c4), true)
    end

    # --- Output encoders ----------------------------------------------

    def std_putc(c)
      @output << (c & 0xFF) if c != EOF
    end

    def no_putc(_c) = nil

    def encode_fallback_html(c)
      oconv(0, "&".ord)
      oconv(0, "#".ord)
      c &= VALUE_MASK
      [1_000_000, 100_000, 10_000, 1000, 100, 10].each do |place|
        oconv(0, 0x30 + (c / place) % 10) if c >= place
      end
      oconv(0, 0x30 + c % 10) if c >= 0
      oconv(0, ";".ord)
    end

    def nkf_each_char_to_hex(c)
      shift = 20
      c &= VALUE_MASK
      while shift >= 0
        if c >= 1 << shift
          while shift >= 0
            oconv(0, bin2hex(c >> shift))
            shift -= 4
          end
        else
          shift -= 4
        end
      end
    end

    def encode_fallback_xml(c)
      oconv(0, "&".ord)
      oconv(0, "#".ord)
      oconv(0, "x".ord)
      nkf_each_char_to_hex(c)
      oconv(0, ";".ord)
    end

    def encode_fallback_java(c)
      oconv(0, "\\".ord)
      c &= VALUE_MASK
      if unicode_bmp_p?(c)
        java_hex(c)
      else
        java_hex((c >> 10) + 0xD7C0)
        oconv(0, "\\".ord)
        java_hex((c & 0x3FF) + 0xDC00)
      end
    end

    def java_hex(c)
      oconv(0, "u".ord)
      [12, 8, 4, 0].each { |shift| oconv(0, bin2hex(c >> shift)) }
    end

    def encode_fallback_perl(c)
      oconv(0, "\\".ord)
      oconv(0, "x".ord)
      oconv(0, "{".ord)
      nkf_each_char_to_hex(c)
      oconv(0, "}".ord)
    end

    def encode_fallback_subchar(_c)
      c = @unicode_subchar
      oconv((c >> 8) & 0xFF, c & 0xFF)
    end

    def output_ascii_escape_sequence(mode)
      return if @output_mode == ASCII || @output_mode == ISO_8859_1

      o_putc(ESC)
      o_putc("(".ord)
      o_putc(@ascii_intro)
      @output_mode = mode
    end

    def output_escape_sequence(mode)
      return if @output_mode == mode

      sequence = case mode
                 when ISO_8859_1 then [ESC, ".".ord, "A".ord]
                 when JIS_X_0201_1976_K then [ESC, "(".ord, "I".ord]
                 when JIS_X_0208 then [ESC, "$".ord, @kanji_intro]
                 when JIS_X_0212 then [ESC, "$".ord, "(".ord, "D".ord]
                 when JIS_X_0213_1 then [ESC, "$".ord, "(".ord, "Q".ord]
                 when JIS_X_0213_2 then [ESC, "$".ord, "(".ord, "P".ord]
                 else []
                 end
      sequence.each { |byte| o_putc(byte) }
      @output_mode = mode
    end

    # ISO-2022-JP.
    def j_oconv(c2, c1)
      if c2 == 0 && unicode_p?(c1)
        _, c2, c1 = w16e_conv(c1)
        if c2 == 0 && unicode_p?(c1)
          c2 = c1 & VALUE_MASK
          if @ms_ucs_map_f != UCS_MAP_ASCII && 0xE000 <= c2 && c2 <= 0xE757
            # CP5022x user-defined characters.
            c1 &= 0xFFF
            c2 = 0x7F + c1 / 94
            c1 = 0x21 + c1 % 94
          else
            __send__(@encode_fallback, c1) if @encode_fallback
            return
          end
        end
      end
      if c2 == 0
        output_ascii_escape_sequence(ASCII)
        o_putc(c1)
      elsif c2 == EOF
        output_ascii_escape_sequence(ASCII)
        o_putc(EOF)
      elsif c2 == ISO_8859_1
        output_ascii_escape_sequence(ISO_8859_1)
        o_putc(c1 | 0x80)
      elsif c2 == JIS_X_0201_1976_K
        output_escape_sequence(JIS_X_0201_1976_K)
        o_putc(c1)
      elsif eucg3?(c2)
        output_escape_sequence(@x0213_f ? JIS_X_0213_2 : JIS_X_0212)
        o_putc(c2 & 0x7f)
        o_putc(c1)
      else
        limit = @ms_ucs_map_f != UCS_MAP_ASCII ? 0x92 : 0x7e
        return if c2 < 0x20 || limit < c2 || c1 < 0x20 || 0x7e < c1

        output_escape_sequence(@x0213_f ? JIS_X_0213_1 : JIS_X_0208)
        o_putc(c2)
        o_putc(c1)
      end
    end

    # EUC-JP.
    def e_oconv(c2, c1)
      if c2 == 0 && unicode_p?(c1)
        _, c2, c1 = w16e_conv(c1)
        if c2 == 0 && unicode_p?(c1)
          c2 = c1 & VALUE_MASK
          if @x0212_f && 0xE000 <= c2 && c2 <= 0xE757
            # eucJP-ms user-defined characters.
            c1 &= 0xFFF
            c2 = c1 / 94
            c2 += c2 < 10 ? 0x75 : 0x8FEB
            c1 = 0x21 + c1 % 94
            o_putc(0x8f) if eucg3?(c2)
            o_putc((c2 & 0x7f) | 0x80)
            o_putc(c1 | 0x80)
          elsif @encode_fallback
            __send__(@encode_fallback, c1)
          end
          return
        end
      end
      if c2 == EOF
        o_putc(EOF)
      elsif c2 == 0
        @output_mode = ASCII
        o_putc(c1)
      elsif c2 == JIS_X_0201_1976_K
        @output_mode = EUC_JP
        o_putc(SS2)
        o_putc(c1 | 0x80)
      elsif c2 == ISO_8859_1
        @output_mode = ISO_8859_1
        o_putc(c1 | 0x80)
      elsif eucg3?(c2)
        @output_mode = EUC_JP
        if @cp932inv_f == FALSE
          ret, s2, s1 = e2s_conv(c2, c1)
          if ret == 0
            ret, t2, t1 = s2e_conv(s2, s1)
            c2, c1 = t2, t1 if ret == 0
          end
        end
        if c2 == 0
          @output_mode = ASCII
          o_putc(c1)
        elsif eucg3?(c2)
          if @x0212_f
            o_putc(0x8f)
            o_putc((c2 & 0x7f) | 0x80)
            o_putc(c1 | 0x80)
          end
        else
          o_putc((c2 & 0x7f) | 0x80)
          o_putc(c1 | 0x80)
        end
      else
        unless graph?(c1) && graph?(c2)
          set_iconv(FALSE, nil)
          return
        end
        @output_mode = EUC_JP
        o_putc(c2 | 0x80)
        o_putc(c1 | 0x80)
      end
    end

    # Shift_JIS.
    def s_oconv(c2, c1)
      if c2 == 0 && unicode_p?(c1)
        _, c2, c1 = w16e_conv(c1)
        if c2 == 0 && unicode_p?(c1)
          c2 = c1 & VALUE_MASK
          if !@x0213_f && 0xE000 <= c2 && c2 <= 0xE757
            # CP932 user-defined characters.
            c1 &= 0xFFF
            c2 = c1 / 188 + (@cp932inv_f != FALSE ? 0xF0 : 0xEB)
            c1 %= 188
            c1 += 0x40 + (c1 > 0x3e ? 1 : 0)
            o_putc(c2)
            o_putc(c1)
          elsif @encode_fallback
            __send__(@encode_fallback, c1)
          end
          return
        end
      end
      if c2 == EOF
        o_putc(EOF)
      elsif c2 == 0
        @output_mode = ASCII
        o_putc(c1)
      elsif c2 == JIS_X_0201_1976_K
        @output_mode = SHIFT_JIS
        o_putc(c1 | 0x80)
      elsif c2 == ISO_8859_1
        @output_mode = ISO_8859_1
        o_putc(c1 | 0x80)
      elsif eucg3?(c2)
        @output_mode = SHIFT_JIS
        ret, s2, s1 = e2s_conv(c2, c1)
        if ret == 0
          o_putc(s2)
          o_putc(s1)
        end
      else
        unless print?(c1) && print?(c2)
          set_iconv(FALSE, nil)
          return
        end
        @output_mode = SHIFT_JIS
        ret, s2, s1 = e2s_conv(c2, c1)
        c2, c1 = s2, s1 if ret == 0
        if @cp932inv_f != FALSE && 0xED <= c2 && c2 <= 0xEE
          c = grid(:cp932inv, c2 - 0xED, c1 - 0x40)
          if c != 0
            c2 = c >> 8
            c1 = c & 0xff
          end
        end
        o_putc(c2)
        prefix = @prefix_table[c1 & 0xFF]
        o_putc(prefix) if prefix != 0
        o_putc(c1)
      end
    end

    def output_utf8(val)
      c1, c2, c3, c4 = nkf_unicode_to_utf8(val)
      o_putc(c1)
      o_putc(c2) if c2 != 0
      o_putc(c3) if c3 != 0
      o_putc(c4) if c4 != 0
    end

    # UTF-8.
    def w_oconv(c2, c1)
      if @output_bom_f
        @output_bom_f = false
        o_putc(0xEF)
        o_putc(0xBB)
        o_putc(0xBF)
      end
      if c2 == EOF
        o_putc(EOF)
      elsif c2 == 0 && unicode_p?(c1)
        output_utf8(c1 & VALUE_MASK)
      elsif c2 == 0
        o_putc(c1)
      else
        val = e2w_conv(c2, c1)
        return if val == 0

        val2 = e2w_combining(val, c2, c1)
        output_utf8(val2) if val2 != 0
        output_utf8(val)
      end
    end

    def output_utf16_bytes(c1, c2)
      if @output_endian == ENDIAN_LITTLE
        o_putc(c1)
        o_putc(c2)
      else
        o_putc(c2)
        o_putc(c1)
      end
    end

    def output_utf16(val)
      if unicode_bmp_p?(val)
        output_utf16_bytes(val & 0xff, (val >> 8) & 0xff)
      else
        val &= VALUE_MASK
        return unless val <= UNICODE_MAX

        high = (val >> 10) + 0xD7C0
        low = (val & 0x3FF) + 0xDC00
        output_utf16_bytes(high & 0xff, (high >> 8) & 0xff)
        output_utf16_bytes(low & 0xff, (low >> 8) & 0xff)
      end
    end

    # UTF-16.
    def w_oconv16(c2, c1)
      if @output_bom_f
        @output_bom_f = false
        output_utf16_bytes(0xFF, 0xFE)
      end
      if c2 == EOF
        o_putc(EOF)
      elsif c2 == 0 && unicode_p?(c1)
        output_utf16(c1)
      elsif c2 != 0
        val = e2w_conv(c2, c1)
        return if val == 0

        val2 = e2w_combining(val, c2, c1)
        output_utf16(val2) if val2 != 0
        output_utf16(val)
      else
        output_utf16_bytes(c1, c2)
      end
    end

    def output_utf32(c)
      bytes = [0, (c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF]
      bytes.reverse! if @output_endian == ENDIAN_LITTLE
      bytes.each { |byte| o_putc(byte) }
    end

    # UTF-32.
    def w_oconv32(c2, c1)
      if @output_bom_f
        @output_bom_f = false
        (@output_endian == ENDIAN_LITTLE ? [0xFF, 0xFE, 0, 0] : [0, 0, 0xFE, 0xFF]).each { |byte| o_putc(byte) }
      end
      if c2 == EOF
        o_putc(EOF)
        return
      end
      if c2 == ISO_8859_1
        c1 |= 0x80
      elsif c2 == 0 && unicode_p?(c1)
        c1 &= VALUE_MASK
      elsif c2 != 0
        val = e2w_conv(c2, c1)
        return if val == 0

        val2 = e2w_combining(val, c2, c1)
        output_utf32(val2) if val2 != 0
        c1 = val
      end
      output_utf32(c1)
    end

    # --- Input guessing -----------------------------------------------
    #
    # Each candidate encoding runs a state machine over the bytes. A
    # candidate that meets a byte it cannot hold is disabled; the scores
    # mark characters that are rare in the encoding, and the lowest score
    # wins when the bytes run out before one candidate is left.

    SCORE_L2 = 1
    SCORE_KANA = SCORE_L2 << 1
    SCORE_DEPEND = SCORE_KANA << 1
    SCORE_CP932 = SCORE_DEPEND << 1
    SCORE_X0212 = SCORE_CP932 << 1
    SCORE_X0213 = SCORE_X0212 << 1
    SCORE_NO_EXIST = SCORE_X0213 << 1
    SCORE_IMIME = SCORE_NO_EXIST << 1
    SCORE_ERROR = SCORE_IMIME << 1
    SCORE_INIT = SCORE_IMIME

    SCORE_TABLE_A0 = [0, 0, 0, 0, 0, 0, 0, 0, 0, SCORE_DEPEND, SCORE_DEPEND, SCORE_DEPEND,
                      SCORE_DEPEND, SCORE_DEPEND, SCORE_DEPEND, SCORE_X0213].freeze
    SCORE_TABLE_F0 = [SCORE_L2, SCORE_L2, SCORE_L2, SCORE_L2, SCORE_L2, SCORE_DEPEND, SCORE_X0213, SCORE_X0213,
                      SCORE_DEPEND, SCORE_DEPEND, SCORE_CP932, SCORE_CP932, SCORE_CP932, SCORE_X0213,
                      SCORE_X0213, SCORE_ERROR].freeze
    SCORE_TABLE_8FA0 = [0, SCORE_X0213, SCORE_X0212, SCORE_X0213, SCORE_X0213, SCORE_X0213, SCORE_X0212,
                        SCORE_X0212, SCORE_X0213, SCORE_X0212, SCORE_X0212, SCORE_X0212, SCORE_X0213,
                        SCORE_X0213, SCORE_X0213, SCORE_X0213].freeze
    SCORE_TABLE_8FE0 = ([SCORE_X0212] * 14 + [SCORE_X0213] * 2).freeze
    SCORE_TABLE_8FF0 = [SCORE_X0213, SCORE_X0213, SCORE_X0213, SCORE_X0212, SCORE_X0212, SCORE_X0213,
                        SCORE_X0213, SCORE_X0213, SCORE_X0213, SCORE_X0213, SCORE_X0213, SCORE_X0213,
                        SCORE_X0213, SCORE_X0213, SCORE_X0213, SCORE_X0213].freeze

    def set_code_score(ptr, score)
      ptr.score |= score if ptr
    end

    def clr_code_score(ptr, score)
      ptr.score &= ~score if ptr
    end

    def code_score(ptr)
      c2 = ptr.buf[0]
      c1 = ptr.buf[1]
      if c2 < 0
        set_code_score(ptr, SCORE_ERROR)
      elsif c2 == SS2
        set_code_score(ptr, SCORE_KANA)
      elsif c2 == 0x8f
        score = case c1 & 0x70
                when 0x20 then SCORE_TABLE_8FA0[c1 & 0x0f]
                when 0x60 then SCORE_TABLE_8FE0[c1 & 0x0f]
                when 0x70 then SCORE_TABLE_8FF0[c1 & 0x0f]
                else SCORE_X0212
                end
        set_code_score(ptr, score)
      elsif e2w_conv(c2, c1) == 0
        set_code_score(ptr, SCORE_NO_EXIST)
      elsif (c2 & 0x70) == 0x20
        set_code_score(ptr, SCORE_TABLE_A0[c2 & 0x0f])
      elsif (c2 & 0x70) == 0x70
        set_code_score(ptr, SCORE_TABLE_F0[c2 & 0x0f])
      elsif (c2 & 0x70) >= 0x50
        set_code_score(ptr, SCORE_L2)
      end
    end

    def status_disable(ptr)
      ptr.stat = -1
      ptr.buf[0] = -1
      code_score(ptr)
      set_iconv(FALSE, nil) if @iconv == ptr.iconv_func
    end

    def status_push_ch(ptr, c)
      ptr.buf[ptr.index] = c
      ptr.index += 1
    end

    def status_clear(ptr)
      ptr.stat = 0
      ptr.index = 0
    end

    def status_reset(ptr)
      status_clear(ptr)
      ptr.score = SCORE_INIT
    end

    alias status_reinit status_reset

    def status_check(ptr, c)
      status_reset(ptr) if c <= DEL && @estab_f != FALSE
    end

    def sjis_trail_byte?(c) = (0x40 <= c && c <= 0x7e) || (0x80 <= c && c <= 0xfc)

    # The status buffer converted in place, as s2e_conv and w2e_conv write
    # through pointers into it.
    def status_s2e(ptr)
      ret, c2, c1 = s2e_conv(ptr.buf[0], ptr.buf[1])
      ptr.buf[0], ptr.buf[1] = c2, c1 if ret == 0
      ret
    end

    def s_status(ptr, c)
      case ptr.stat
      when -1
        status_check(ptr, c)
      when 0
        if c <= DEL || unicode_p?(c)
          nil
        elsif 0xa1 <= c && c <= 0xdf
          status_push_ch(ptr, SS2)
          status_push_ch(ptr, c)
          code_score(ptr)
          status_clear(ptr)
        elsif (0x81 <= c && c < 0xa0) || (0xe0 <= c && c <= 0xea)
          ptr.stat = 1
          status_push_ch(ptr, c)
        elsif 0xed <= c && c <= 0xee
          ptr.stat = 3
          status_push_ch(ptr, c)
        elsif ibmext_in_sjis?(c)
          ptr.stat = 2
          status_push_ch(ptr, c)
        elsif 0xf0 <= c && c <= 0xfc
          ptr.stat = 1
          status_push_ch(ptr, c)
        else
          status_disable(ptr)
        end
      when 1
        if sjis_trail_byte?(c)
          status_push_ch(ptr, c)
          status_s2e(ptr)
          code_score(ptr)
          status_clear(ptr)
        else
          status_disable(ptr)
        end
      when 2
        if sjis_trail_byte?(c)
          status_push_ch(ptr, c)
          if status_s2e(ptr) == 0
            set_code_score(ptr, SCORE_CP932)
            status_clear(ptr)
            return
          end
        end
        status_disable(ptr)
      when 3
        if sjis_trail_byte?(c)
          status_push_ch(ptr, c)
          status_s2e(ptr)
          set_code_score(ptr, SCORE_CP932)
          status_clear(ptr)
        else
          status_disable(ptr)
        end
      end
    end

    def e_status(ptr, c)
      case ptr.stat
      when -1
        status_check(ptr, c)
      when 0
        if c <= DEL || unicode_p?(c)
          nil
        elsif c == SS2 || (0xa1 <= c && c <= 0xfe)
          ptr.stat = 1
          status_push_ch(ptr, c)
        elsif c == 0x8f
          ptr.stat = 2
          status_push_ch(ptr, c)
        else
          status_disable(ptr)
        end
      when 1
        if 0xa1 <= c && c <= 0xfe
          status_push_ch(ptr, c)
          code_score(ptr)
          status_clear(ptr)
        else
          status_disable(ptr)
        end
      when 2
        if 0xa1 <= c && c <= 0xfe
          ptr.stat = 1
          status_push_ch(ptr, c)
        else
          status_disable(ptr)
        end
      end
    end

    def w_status(ptr, c)
      case ptr.stat
      when -1
        status_check(ptr, c)
      when 0
        if c <= DEL || unicode_p?(c)
          nil
        elsif 0xc0 <= c && c <= 0xdf
          ptr.stat = 1
          status_push_ch(ptr, c)
        elsif 0xe0 <= c && c <= 0xef
          ptr.stat = 2
          status_push_ch(ptr, c)
        elsif 0xf0 <= c && c <= 0xf4
          ptr.stat = 3
          status_push_ch(ptr, c)
        else
          status_disable(ptr)
        end
      when 1, 2
        if 0x80 <= c && c <= 0xbf
          status_push_ch(ptr, c)
          if ptr.index > ptr.stat
            buf = ptr.buf
            bom = buf[0] == 0xef && buf[1] == 0xbb && buf[2] == 0xbf
            _, buf[0], buf[1] = w2e_conv(buf[0], buf[1], buf[2])
            code_score(ptr) unless bom
            status_clear(ptr)
          end
        else
          status_disable(ptr)
        end
      when 3
        if 0x80 <= c && c <= 0xbf
          if ptr.index < ptr.stat
            status_push_ch(ptr, c)
          else
            status_clear(ptr)
          end
        else
          status_disable(ptr)
        end
      end
    end

    def code_status(c)
      action_flag = true
      result = nil
      @input_code_list.each do |p|
        next unless p.status_func

        __send__(p.status_func, p, c)
        if p.stat > 0
          action_flag = false
        elsif p.stat == 0
          if result
            action_flag = false
          else
            result = p
          end
        end
      end
      return unless action_flag

      if result && @estab_f == FALSE
        set_iconv(TRUE, result.iconv_func)
      elsif c <= DEL
        @input_code_list.each { |p| status_reset(p) }
      end
    end

    def push_hold_buf(c2)
      return EOF if @hold_count >= HOLD_SIZE * 2

      @hold_buf[@hold_count] = c2
      @hold_count += 1
      @hold_count >= HOLD_SIZE * 2 ? EOF : @hold_count
    end

    # h_conv: bytes kept while the guess is still open, then converted
    # with the decoder that the guess selects.
    def h_conv(c1, c2)
      @hold_count = 0
      push_hold_buf(c1)
      push_hold_buf(c2)
      while (c2 = i_getc) != EOF
        if c2 == ESC
          i_ungetc(c2)
          break
        end
        code_status(c2)
        break if push_hold_buf(c2) == EOF || @estab_f != FALSE
      end

      if @estab_f == FALSE
        code_status(c2) if c2 == EOF
        result = @input_code_list.first
        @input_code_list.each { |p| result = p if p.status_func && p.score < result.score }
        set_iconv(TRUE, result.iconv_func)
      end

      ret = c2
      hold_index = 0
      hold = lambda do
        value = @hold_buf[hold_index]
        hold_index += 1
        value
      end
      while hold_index < @hold_count
        c1 = hold.call
        if unicode_p?(c1)
          oconv(0, c1)
          next
        elsif c1 <= DEL
          iconv(0, c1, 0)
          next
        elsif @iconv == :s_iconv && 0xa1 <= c1 && c1 <= 0xdf
          iconv(JIS_X_0201_1976_K, c1, 0)
          next
        end
        fromhold_count = 1
        if hold_index < @hold_count
          c2 = hold.call
          fromhold_count += 1
        else
          c2 = i_getc
          break if c2 == EOF

          code_status(c2)
        end
        c3 = 0
        case iconv(c1, c2, 0)
        when -2
          # A four-byte UTF-8 character.
          if hold_index < @hold_count
            c3 = hold.call
          elsif (c3 = i_getc) == EOF
            ret = EOF
            break
          end
          code_status(c3)
          if hold_index < @hold_count
            c4 = hold.call
          elsif (c4 = i_getc) == EOF
            ret = EOF
            break
          end
          code_status(c4)
          iconv(c1, c2, (c3 << 8) | c4)
        when -3
          # A UTF-8 character that may combine with the next one.
          if hold_index < @hold_count
            c3 = hold.call
            fromhold_count += 1
          elsif (c3 = i_getc) == EOF
            w_iconv_nocombine(c1, c2, 0)
            break
          end
          if hold_index < @hold_count
            c4 = hold.call
            fromhold_count += 1
          elsif (c4 = i_getc) == EOF
            w_iconv_nocombine(c1, c2, 0)
            if fromhold_count <= 2
              i_ungetc(c3)
            else
              hold_index -= 1
            end
            next
          end
          if w_iconv_combine(c1, c2, 0, c3, c4, 0) != 0
            w_iconv_nocombine(c1, c2, 0)
            if fromhold_count <= 2
              i_ungetc(c4)
              i_ungetc(c3)
            elsif fromhold_count == 3
              i_ungetc(c4)
              hold_index -= 1
            else
              hold_index -= 2
            end
          end
        when -1
          # A three-byte EUC-JP or UTF-8 character.
          if hold_index < @hold_count
            c3 = hold.call
            fromhold_count += 1
          elsif (c3 = i_getc) == EOF
            ret = EOF
            break
          else
            code_status(c3)
          end
          if iconv(c1, c2, c3) == -3
            hold_index = h_conv_combine6(c1, c2, c3, fromhold_count, hold_index)
          end
        end
      end
      ret
    end

    # The six-byte case of h_conv: a three-byte UTF-8 character that can
    # combine with the three bytes after it. Returns the hold index.
    def h_conv_combine6(c1, c2, c3, fromhold_count, hold_index)
      take = lambda do
        if hold_index < @hold_count
          value = @hold_buf[hold_index]
          hold_index += 1
          fromhold_count += 1
          value
        else
          i_getc
        end
      end
      if (c4 = take.call) == EOF
        w_iconv_nocombine(c1, c2, c3)
        return hold_index
      end
      if (c5 = take.call) == EOF
        w_iconv_nocombine(c1, c2, c3)
        if fromhold_count == 4
          hold_index -= 1
        else
          i_ungetc(c4)
        end
        return hold_index
      end
      if (c6 = take.call) == EOF
        w_iconv_nocombine(c1, c2, c3)
        if fromhold_count == 5
          hold_index -= 2
        elsif fromhold_count == 4
          hold_index -= 1
          i_ungetc(c5)
        else
          i_ungetc(c5)
          i_ungetc(c4)
        end
        return hold_index
      end
      if w_iconv_combine(c1, c2, c3, c4, c5, c6) != 0
        w_iconv_nocombine(c1, c2, c3)
        case fromhold_count
        when 6 then hold_index -= 3
        when 5
          hold_index -= 2
          i_ungetc(c6)
        when 4
          hold_index -= 1
          i_ungetc(c6)
          i_ungetc(c5)
        else
          i_ungetc(c6)
          i_ungetc(c5)
          i_ungetc(c4)
        end
      end
      hold_index
    end

    # check_bom: a byte order mark read and dropped, and the decoder it
    # names chosen when the options named none.
    def check_bom
      @input_bom_f = false
      c2 = i_getc
      case c2
      when 0x00
        if (c2 = i_getc) == 0x00
          if (c2 = i_getc) == 0xFE
            if (c2 = i_getc) == 0xFF
              set_iconv(TRUE, :w_iconv32) unless @input_encoding
              if @iconv == :w_iconv32
                @input_bom_f = true
                @input_endian = ENDIAN_BIG
                return
              end
              i_ungetc(0xFF)
            else
              i_ungetc(c2)
            end
            i_ungetc(0xFE)
          elsif c2 == 0xFF
            if (c2 = i_getc) == 0xFE
              set_iconv(TRUE, :w_iconv32) unless @input_encoding
              if @iconv == :w_iconv32
                @input_endian = ENDIAN_2143
                return
              end
              i_ungetc(0xFF)
            else
              i_ungetc(c2)
            end
            i_ungetc(0xFF)
          else
            i_ungetc(c2)
          end
          i_ungetc(0x00)
        else
          i_ungetc(c2)
        end
        i_ungetc(0x00)
      when 0xEF
        if (c2 = i_getc) == 0xBB
          if (c2 = i_getc) == 0xBF
            set_iconv(TRUE, :w_iconv) unless @input_encoding
            if @iconv == :w_iconv
              @input_bom_f = true
              return
            end
            i_ungetc(0xBF)
          else
            i_ungetc(c2)
          end
          i_ungetc(0xBB)
        else
          i_ungetc(c2)
        end
        i_ungetc(0xEF)
      when 0xFE
        if (c2 = i_getc) == 0xFF
          if (c2 = i_getc) == 0x00
            if (c2 = i_getc) == 0x00
              set_iconv(TRUE, :w_iconv32) unless @input_encoding
              if @iconv == :w_iconv32
                @input_endian = ENDIAN_3412
                return
              end
              i_ungetc(0x00)
            else
              i_ungetc(c2)
            end
            i_ungetc(0x00)
          else
            i_ungetc(c2)
          end
          set_iconv(TRUE, :w_iconv16) unless @input_encoding
          if @iconv == :w_iconv16
            @input_endian = ENDIAN_BIG
            @input_bom_f = true
            return
          end
          i_ungetc(0xFF)
        else
          i_ungetc(c2)
        end
        i_ungetc(0xFE)
      when 0xFF
        if (c2 = i_getc) == 0xFE
          if (c2 = i_getc) == 0x00
            if (c2 = i_getc) == 0x00
              set_iconv(TRUE, :w_iconv32) unless @input_encoding
              if @iconv == :w_iconv32
                @input_endian = ENDIAN_LITTLE
                @input_bom_f = true
                return
              end
              i_ungetc(0x00)
            else
              i_ungetc(c2)
            end
            i_ungetc(0x00)
          else
            i_ungetc(c2)
          end
          set_iconv(TRUE, :w_iconv16) unless @input_encoding
          if @iconv == :w_iconv16
            @input_endian = ENDIAN_LITTLE
            @input_bom_f = true
            return
          end
          i_ungetc(0xFE)
        else
          i_ungetc(c2)
        end
        i_ungetc(0xFF)
      else
        i_ungetc(c2)
      end
    end

    # --- Input filters ------------------------------------------------

    def std_getc
      return @std_gc_buf.pop unless @std_gc_buf.empty?
      return EOF if @input_pos >= @input.size

      byte = @input[@input_pos]
      @input_pos += 1
      byte
    end

    def std_ungetc(c)
      @std_gc_buf.push(c)
      c
    end

    # -B: JIS whose escape characters were lost.
    def broken_getc
      return @broken_buf.pop unless @broken_buf.empty?

      c = __send__(@i_bgetc)
      if c == "$".ord && @broken_state != ESC && (@input_mode == ASCII || @input_mode == JIS_X_0201_1976_K)
        c1 = __send__(@i_bgetc)
        @broken_state = 0
        if c1 == "@".ord || c1 == "B".ord
          @broken_buf.push(c1, c)
          return ESC
        end
        __send__(@i_bungetc, c1)
        c
      elsif c == "(".ord && @broken_state != ESC && (@input_mode == JIS_X_0208 || @input_mode == JIS_X_0201_1976_K)
        c1 = __send__(@i_bgetc)
        @broken_state = 0
        if c1 == "J".ord || c1 == "B".ord
          @broken_buf.push(c1, c)
          return ESC
        end
        __send__(@i_bungetc, c1)
        c
      else
        @broken_state = c
        c
      end
    end

    def broken_ungetc(c)
      @broken_buf.push(c) if @broken_buf.size < 2
      c
    end

    # --cap-input and --url-input: a byte written as ":xx" or "%xx".
    def hex_getc(ch, getc, ungetc)
      c1 = __send__(getc)
      return c1 if c1 != ch

      c2 = __send__(getc)
      unless xdigit?(c2)
        __send__(ungetc, c2)
        return c1
      end
      c3 = __send__(getc)
      unless xdigit?(c3)
        __send__(ungetc, c2)
        __send__(ungetc, c3)
        return c1
      end
      (hex2bin(c2) << 4) | hex2bin(c3)
    end

    def cap_getc = hex_getc(":".ord, @i_cgetc, @i_cungetc)
    def cap_ungetc(c) = __send__(@i_cungetc, c)
    def url_getc = hex_getc("%".ord, @i_ugetc, @i_uungetc)
    def url_ungetc(c) = __send__(@i_uungetc, c)

    # --numchar-input: "&#1234;" and "&#x4E00;".
    def numchar_getc
      buf = [__send__(@i_ngetc)]
      c = -1
      if buf[0] == "&".ord
        buf << __send__(@i_ngetc)
        if buf[1] == "#".ord
          c = 0
          buf << __send__(@i_ngetc)
          if buf[2] == "x".ord || buf[2] == "X".ord
            7.times do
              buf << __send__(@i_ngetc)
              unless xdigit?(buf.last)
                c = -1 if buf.last != ";".ord
                break
              end
              c = (c << 4) | hex2bin(buf.last)
            end
          else
            8.times do |j|
              buf << __send__(@i_ngetc) if j != 0
              unless digit?(buf.last)
                c = -1 if buf.last != ";".ord
                break
              end
              c = c * 10 + hex2bin(buf.last)
            end
          end
        end
      end
      return unicode_new(c) if c != -1

      (buf.size - 1).downto(1) { |i| __send__(@i_nungetc, buf[i]) }
      buf[0]
    end

    def numchar_ungetc(c) = __send__(@i_nungetc, c)

    # UTF8-MAC: decomposed sequences read back as composed ones.
    def nfc_getc
      table = Tables[:normalization_table]
      buf = @nfc_buf
      lower = 0
      upper = table.size - 1
      c = __send__(@i_nfc_getc)
      return c if c == EOF || c > 0xFF || (c & 0xc0) == 0x80

      buf.push(c)
      loop do
        while lower <= upper
          mid = (lower + upper) / 2
          nfd = table[mid][3, 9]
          len = 0
          while len < 9 && nfd[len] != 0
            if len >= buf.size
              c = __send__(@i_nfc_getc)
              if c == EOF
                len = 0
                lower = 1
                upper = 0
                break
              end
              buf.push(c)
            end
            if nfd[len] != buf[len]
              if nfd[len] < buf[len]
                lower = mid + 1
              else
                upper = mid - 1
              end
              len = 0
              break
            end
            len += 1
          end
          next unless len > 0

          buf.clear
          table[mid][0, 3].each do |byte|
            break if byte == 0

            buf.push(byte)
          end
          break
        end
        break unless lower <= upper
      end
      __send__(@i_nfc_ungetc, buf.pop) while buf.size > 1
      buf.pop
    end

    def nfc_ungetc(c) = __send__(@i_nfc_ungetc, c)

    # --- Output filters -----------------------------------------------

    # Newline conversion (-Lu -Lw -Lm -c -d), and the newline kind the
    # guesser reports.
    def eol_conv(c2, c1)
      if @guess_f != 0 && @input_eol != EOF
        this_eol = @prev_cr != 0 ? CRLF : LF
        if c2 == 0 && c1 == LF
          if @input_eol == 0
            @input_eol = this_eol
          elsif @input_eol != this_eol
            @input_eol = EOF
          end
        elsif c2 == 0 && c1 == CR && @input_eol == LF
          @input_eol = EOF
        elsif @prev_cr == 0
          nil
        elsif @input_eol == 0
          @input_eol = CR
        elsif @input_eol != CR
          @input_eol = EOF
        end
      end
      if @prev_cr != 0 || (c2 == 0 && c1 == LF)
        @prev_cr = 0
        __send__(@o_eol_conv, 0, CR) if @eolmode_f != LF
        __send__(@o_eol_conv, 0, LF) if @eolmode_f != CR
      end
      if c2 == 0 && c1 == CR
        @prev_cr = CR
      elsif c2 != 0 || c1 != LF
        __send__(@o_eol_conv, c2, c1)
      end
    end

    def newline_bytes
      case @eolmode_f == 0 ? LF : @eolmode_f
      when CRLF then [CR, LF]
      when CR then [CR]
      when LF then [LF]
      else []
      end
    end

    def put_newline(func) = newline_bytes.each { |byte| __send__(func, byte) }
    def oconv_newline(func) = newline_bytes.each { |byte| __send__(func, 0, byte) }

    # -f and -F: line folding with nkf's simple kinsoku rules.
    def fold_conv(c2, c1)
      if c1 == CR && !@fold_preserve_f
        fold_state = 0
      elsif c1 == LF && @f_prev == CR && @fold_preserve_f
        @f_prev = LF
        fold_state = 0
      elsif c1 == BS
        @f_line -= 1 if @f_line > 0
        fold_state = 1
      elsif c2 == EOF && @f_line != 0
        fold_state = LF
      elsif (c1 == LF && !@fold_preserve_f) || ((c1 == CR || (c1 == LF && @f_prev != CR)) && @fold_preserve_f)
        if @fold_preserve_f
          @f_prev = c1
          @f_line = 0
          fold_state = CR
        elsif @f_prev == c1 || @f_prev == LF
          fold_state = @f_line != 0 ? LF : 1
          @f_line = 0
        elsif (@f_prev & 0x80) != 0
          @f_prev = c1
          fold_state = 0
        elsif @f_prev == SP
          fold_state = 0
        else
          @f_prev = c1
          @f_line += 1
          if @f_line <= @fold_len
            fold_state = SP
          else
            @f_line = 0
            fold_state = CR
          end
        end
      elsif c1 == 0x0c
        @f_prev = LF
        @f_line = 0
        fold_state = LF
      elsif (c2 == 0 && blank?(c1)) || (c2 == 0x21 && c1 == 0x21)
        if @f_prev == SP
          fold_state = 0
        else
          @f_prev = SP
          @f_line += 1
          if @f_line <= @fold_len
            fold_state = SP
          else
            @f_line = 0
            fold_state = CR
          end
        end
      else
        fold_state = fold_char(c2, c1)
      end
      case fold_state
      when LF
        oconv_newline(@o_fconv)
        __send__(@o_fconv, c2, c1)
      when 0
        nil
      when CR
        oconv_newline(@o_fconv)
      when TAB, SP
        __send__(@o_fconv, 0, SP)
      else
        __send__(@o_fconv, c2, c1)
      end
    end

    KINSOKU_ASCII = ")]}.,!?/:;".bytes.freeze
    KINSOKU_X0201 = [0xde & 0x7f, 0xdf & 0x7f, 0xa4 & 0x7f, 0xa3 & 0x7f, 0xa1 & 0x7f, 0xb0 & 0x7f].freeze
    KINSOKU_X0208 = "\"#WK$%'()*+,".bytes.freeze

    # fold_conv for a character that takes room on the line.
    def fold_char(c2, c1)
      char_size = c2 != 0 ? 2 : 1
      prev0 = @f_prev
      @f_prev = c1
      @f_prev |= 0x80 if c2 != 0
      @f_line += c2 == JIS_X_0201_1976_K ? 1 : char_size
      return 1 if @f_line <= @fold_len

      if @f_line > @fold_len + @fold_margin
        @f_line = char_size
        LF
      elsif c2 == JIS_X_0201_1976_K
        return 1 if KINSOKU_X0201.include?(c1)

        @f_line = 1
        LF
      elsif c2 == 0
        if KINSOKU_ASCII.include?(c1)
          1
        elsif !alnum?(prev0) || prev0 == SP || prev0 == LF || (prev0 & 0x80) != 0
          @f_line = char_size
          LF
        else
          1
        end
      elsif c2 == 0x21 && KINSOKU_X0208.include?(c1)
        1
      else
        @f_line = char_size
        LF
      end
    end

    # X0201 kana to X0208, by the byte after 0xA0 (two bytes per entry).
    CV = [
      0x21, 0x21, 0x21, 0x23, 0x21, 0x56, 0x21, 0x57, 0x21, 0x22, 0x21, 0x26, 0x25, 0x72, 0x25, 0x21,
      0x25, 0x23, 0x25, 0x25, 0x25, 0x27, 0x25, 0x29, 0x25, 0x63, 0x25, 0x65, 0x25, 0x67, 0x25, 0x43,
      0x21, 0x3c, 0x25, 0x22, 0x25, 0x24, 0x25, 0x26, 0x25, 0x28, 0x25, 0x2a, 0x25, 0x2b, 0x25, 0x2d,
      0x25, 0x2f, 0x25, 0x31, 0x25, 0x33, 0x25, 0x35, 0x25, 0x37, 0x25, 0x39, 0x25, 0x3b, 0x25, 0x3d,
      0x25, 0x3f, 0x25, 0x41, 0x25, 0x44, 0x25, 0x46, 0x25, 0x48, 0x25, 0x4a, 0x25, 0x4b, 0x25, 0x4c,
      0x25, 0x4d, 0x25, 0x4e, 0x25, 0x4f, 0x25, 0x52, 0x25, 0x55, 0x25, 0x58, 0x25, 0x5b, 0x25, 0x5e,
      0x25, 0x5f, 0x25, 0x60, 0x25, 0x61, 0x25, 0x62, 0x25, 0x64, 0x25, 0x66, 0x25, 0x68, 0x25, 0x69,
      0x25, 0x6a, 0x25, 0x6b, 0x25, 0x6c, 0x25, 0x6d, 0x25, 0x6f, 0x25, 0x73, 0x21, 0x2b, 0x21, 0x2c,
      0x00, 0x00
    ].freeze

    # The voiced (dakuten) forms.
    DV = Array.new(130, 0).tap do |dv|
      { 0x13 => 0x2574, 0x16 => 0x252c, 0x17 => 0x252e, 0x18 => 0x2530, 0x19 => 0x2532, 0x1a => 0x2534,
        0x1b => 0x2536, 0x1c => 0x2538, 0x1d => 0x253a, 0x1e => 0x253c, 0x1f => 0x253e, 0x20 => 0x2540,
        0x21 => 0x2542, 0x22 => 0x2545, 0x23 => 0x2547, 0x24 => 0x2549, 0x2a => 0x2550, 0x2b => 0x2553,
        0x2c => 0x2556, 0x2d => 0x2559, 0x2e => 0x255c }.each do |index, code|
        dv[index * 2] = code >> 8
        dv[index * 2 + 1] = code & 0xff
      end
    end.freeze

    # The semi-voiced (handakuten) forms.
    EV = Array.new(130, 0).tap do |ev|
      { 0x2a => 0x2551, 0x2b => 0x2554, 0x2c => 0x2557, 0x2d => 0x255a, 0x2e => 0x255d }.each do |index, code|
        ev[index * 2] = code >> 8
        ev[index * 2 + 1] = code & 0xff
      end
    end.freeze

    # The semi-voiced forms JIS X 0213 adds.
    EV_X0213 = Array.new(130, 0).tap do |ev|
      { 0x16 => 0x2577, 0x17 => 0x2578, 0x18 => 0x2579, 0x19 => 0x257a, 0x1a => 0x257b, 0x1e => 0x257c,
        0x22 => 0x257d, 0x24 => 0x257e }.each do |index, code|
        ev[index * 2] = code >> 8
        ev[index * 2 + 1] = code & 0xff
      end
    end.freeze

    # X0208 symbols to ASCII, from row 1 cell 0x20.
    FV = [
      0x00, 0x00, 0x00, 0x00, 0x2c, 0x2e, 0x00, 0x3a, 0x3b, 0x3f, 0x21, 0x00, 0x00, 0x27, 0x60, 0x00,
      0x5e, 0x00, 0x5f, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x2d, 0x00, 0x2f,
      0x5c, 0x00, 0x00, 0x7c, 0x00, 0x00, 0x60, 0x27, 0x22, 0x22, 0x28, 0x29, 0x00, 0x00, 0x5b, 0x5d,
      0x7b, 0x7d, 0x3c, 0x3e, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x2b, 0x2d, 0x00, 0x00,
      0x00, 0x3d, 0x00, 0x3c, 0x3e, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x24, 0x00, 0x00, 0x25, 0x23, 0x26, 0x2a, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ].freeze

    # X0208 katakana (row 5, from cell 0x20) to X0201: the kana, and a
    # voiced or semi-voiced mark after it.
    FULLWIDTH_TO_HALFWIDTH = [
      0x0000, 0x2700, 0x3100, 0x2800, 0x3200, 0x2900, 0x3300, 0x2A00,
      0x3400, 0x2B00, 0x3500, 0x3600, 0x365E, 0x3700, 0x375E, 0x3800,
      0x385E, 0x3900, 0x395E, 0x3A00, 0x3A5E, 0x3B00, 0x3B5E, 0x3C00,
      0x3C5E, 0x3D00, 0x3D5E, 0x3E00, 0x3E5E, 0x3F00, 0x3F5E, 0x4000,
      0x405E, 0x4100, 0x415E, 0x2F00, 0x4200, 0x425E, 0x4300, 0x435E,
      0x4400, 0x445E, 0x4500, 0x4600, 0x4700, 0x4800, 0x4900, 0x4A00,
      0x4A5E, 0x4A5F, 0x4B00, 0x4B5E, 0x4B5F, 0x4C00, 0x4C5E, 0x4C5F,
      0x4D00, 0x4D5E, 0x4D5F, 0x4E00, 0x4E5E, 0x4E5F, 0x4F00, 0x5000,
      0x5100, 0x5200, 0x5300, 0x2C00, 0x5400, 0x2D00, 0x5500, 0x2E00,
      0x5600, 0x5700, 0x5800, 0x5900, 0x5A00, 0x5B00, 0x0000, 0x5C00,
      0x0000, 0x0000, 0x2600, 0x5D00, 0x335E, 0x0000, 0x0000, 0x365F,
      0x375F, 0x385F, 0x395F, 0x3A5F, 0x3E5F, 0x425F, 0x445F, 0x0000
    ].freeze

    # X0208 symbols -Z4 writes as X0201.
    HALFWIDTH_SYMBOLS = { 0x23 => 0xA1, 0x56 => 0xA2, 0x57 => 0xA3, 0x22 => 0xA4, 0x26 => 0xA5,
                          0x3C => 0xB0, 0x2B => 0xDE, 0x2C => 0xDF }.freeze

    HTML_ENTITIES = { ">".ord => "&gt;", "<".ord => "&lt;", "\"".ord => "&quot;", "&".ord => "&amp;" }.freeze

    # A byte of a kana table entry, 0 where C would read past the table.
    def kana(table, c, offset) = cell(table, (c - SP) * 2 + offset)

    # z_conv: X0201 katakana to X0208 (joining voiced marks), and the -Z
    # conversions.
    def z_conv(c2, c1)
      if c2 == JIS_X_0201_1976_K && (c1 == 0x20 || c1 == 0x7D || c1 == 0x7E)
        __send__(@o_zconv, c2, c1)
        return
      end

      if @x0201_f != FALSE
        if @z_prev2 == JIS_X_0201_1976_K
          if c2 == JIS_X_0201_1976_K
            if c1 == (0xde & 0x7f)
              @z_prev2 = 0
              __send__(@o_zconv, kana(DV, @z_prev1, 0), kana(DV, @z_prev1, 1))
              return
            elsif c1 == (0xdf & 0x7f) && kana(EV, @z_prev1, 0) != 0
              @z_prev2 = 0
              __send__(@o_zconv, kana(EV, @z_prev1, 0), kana(EV, @z_prev1, 1))
              return
            elsif @x0213_f && c1 == (0xdf & 0x7f) && kana(EV_X0213, @z_prev1, 0) != 0
              @z_prev2 = 0
              __send__(@o_zconv, kana(EV_X0213, @z_prev1, 0), kana(EV_X0213, @z_prev1, 1))
              return
            end
          end
          @z_prev2 = 0
          __send__(@o_zconv, kana(CV, @z_prev1, 0), kana(CV, @z_prev1, 1))
        end
        if c2 == JIS_X_0201_1976_K
          if kana(DV, c1, 0) != 0 || kana(EV, c1, 0) != 0 || (@x0213_f && kana(EV_X0213, c1, 0) != 0)
            @z_prev1 = c1
            @z_prev2 = c2
          else
            __send__(@o_zconv, kana(CV, c1, 0), kana(CV, c1, 1))
          end
          return
        end
      end

      if c2 == EOF
        __send__(@o_zconv, c2, c1)
        return
      end

      if (@alpha_f & 1) != 0 && c2 == 0x23
        c2 = 0
      elsif c2 == 0x21
        if c1 == 0x21
          if (@alpha_f & 2) != 0
            c2 = 0
            c1 = SP
          elsif (@alpha_f & 4) != 0
            __send__(@o_zconv, 0, SP)
            __send__(@o_zconv, 0, SP)
            return
          end
        elsif (@alpha_f & 1) != 0 && 0x20 < c1 && c1 < 0x7f && FV[c1 - 0x20] != 0
          c2 = 0
          c1 = FV[c1 - 0x20]
        end
      end

      if (@alpha_f & 8) != 0 && c2 == 0 && (entity = HTML_ENTITIES[c1])
        entity.each_byte { |byte| __send__(@o_zconv, 0, byte) }
        return
      end

      if (@alpha_f & 16) != 0
        if c2 == 0x21
          if (c = HALFWIDTH_SYMBOLS[c1])
            __send__(@o_zconv, JIS_X_0201_1976_K, c)
            return
          end
        elsif c2 == 0x25
          half = cell(FULLWIDTH_TO_HALFWIDTH, c1 - 0x20)
          if half != 0
            __send__(@o_zconv, JIS_X_0201_1976_K, half >> 8)
            __send__(@o_zconv, JIS_X_0201_1976_K, half & 0xFF) if (half & 0xFF) != 0
            return
          end
        elsif c2 == 0 && unicode_p?(c1) && [0x3099, 0x309A].include?(c1 & VALUE_MASK)
          __send__(@o_zconv, JIS_X_0201_1976_K, 0x5E + (c1 & VALUE_MASK) - 0x3099)
          return
        end
      end
      __send__(@o_zconv, c2, c1)
    end

    def rot13(c)
      if c < "A".ord then c
      elsif c <= "M".ord then c + 13
      elsif c <= "Z".ord then c - 13
      elsif c < "a".ord then c
      elsif c <= "m".ord then c + 13
      elsif c <= "z".ord then c - 13
      else c
      end
    end

    def rot47(c)
      if c < "!".ord then c
      elsif c <= "O".ord then c + 47
      elsif c <= "~".ord then c - 47
      else c
      end
    end

    # -r: ROT13 on ASCII, ROT47 on JIS.
    def rot_conv(c2, c1)
      if c2 == 0 || c2 == JIS_X_0201_1976_K || c2 == ISO_8859_1
        c1 = rot13(c1)
      elsif c2 != 0
        c1 = rot47(c1)
        c2 = rot47(c2)
      end
      __send__(@o_rot_conv, c2, c1)
    end

    # -h1 katakana to hiragana, -h2 hiragana to katakana.
    def hira_conv(c2, c1)
      if (@hira_f & 1) != 0
        if c2 == 0x25
          if 0x20 < c1 && c1 < 0x74
            __send__(@o_hira_conv, 0x24, c1)
            return
          elsif c1 == 0x74 && @output_encoding.unicode?
            __send__(@o_hira_conv, 0, unicode_new(0x3094))
            return
          end
        elsif c2 == 0x21 && (c1 == 0x33 || c1 == 0x34)
          __send__(@o_hira_conv, c2, c1 + 2)
          return
        end
      end
      if (@hira_f & 2) != 0
        if c2 == 0 && c1 == unicode_new(0x3094)
          c2 = 0x25
          c1 = 0x74
        elsif c2 == 0x24 && 0x20 < c1 && c1 < 0x74
          c2 = 0x25
        elsif c2 == 0x21 && (c1 == 0x35 || c1 == 0x36)
          c1 -= 2
        end
      end
      __send__(@o_hira_conv, c2, c1)
    end

    ISO2022JP_RANGES = [
      [0x222f, 0x2239], [0x2242, 0x2249], [0x2251, 0x225b], [0x226b, 0x2271], [0x227a, 0x227d],
      [0x2321, 0x232f], [0x233a, 0x2340], [0x235b, 0x2360], [0x237b, 0x237e], [0x2474, 0x247e],
      [0x2577, 0x257e], [0x2639, 0x2640], [0x2659, 0x267e], [0x2742, 0x2750], [0x2772, 0x277e],
      [0x2841, 0x287e], [0x4f54, 0x4f7e], [0x7425, 0x747e]
    ].freeze

    # -I: characters outside ISO-2022-JP become a geta mark.
    def iso2022jp_check_conv(c2, c1)
      if c2 >= 0x00 && c2 <= 0x20 && c1 >= 0x7f && c1 <= 0xff
        c2 = GETA1
        c1 = GETA2
      end
      if (c2 >= 0x29 && c2 <= 0x2f) || (c2 >= 0x75 && c2 <= 0x7e)
        c2 = GETA1
        c1 = GETA2
      end
      ISO2022JP_RANGES.each do |start, finish|
        c = (c2 << 8) + c1
        if c >= start && c <= finish
          c2 = GETA1
          c1 = GETA2
        end
      end
      __send__(@o_iso2022jp_check_conv, c2, c1)
    end

    # --- MIME decoding ------------------------------------------------
    #
    # Decoded bytes wait in a ring buffer between @mime_top and
    # @mime_last; @mime_input reads the undecoded bytes the integrity
    # check stored there.

    MIME_PATTERNS = ["=?EUC-JP?B?", "=?SHIFT_JIS?B?", "=?ISO-8859-1?Q?", "=?ISO-8859-1?B?", "=?ISO-2022-JP?B?",
                     "=?ISO-2022-JP?B?", "=?ISO-2022-JP?Q?", "=?UTF-8?B?", "=?UTF-8?Q?", "=?US-ASCII?Q?"]
                    .map { |pattern| pattern.bytes.freeze }.freeze
    MIME_PRIORITY_FUNC = [:e_iconv, :s_iconv, nil, nil, nil, nil, nil, :w_iconv, :w_iconv, nil].freeze
    MIME_ENCODE = [EUC_JP, SHIFT_JIS, ISO_8859_1, ISO_8859_1, JIS_X_0208, JIS_X_0201_1976_K,
                   JIS_X_0201_1976_K, UTF_8, UTF_8, ASCII, 0].freeze
    MIME_ENCODE_METHOD = ["B", "B", "Q", "B", "B", "B", "Q", "B", "Q", "Q"].map(&:ord).push(0).freeze
    MIME_B = "B".ord
    MIME_Q = "Q".ord
    BASIS_64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".bytes.freeze

    def mime_buf_get(index) = @mime_input_buf[index & MIME_BUF_MASK]

    def mime_buf_set(index, c)
      @mime_input_buf[index & MIME_BUF_MASK] = c & 0xFF
    end

    def mime_ungetc(c)
      @mime_top -= 1
      mime_buf_set(@mime_top, c)
      c
    end

    def mime_ungetc_buf(c)
      if @mimebuf_f != FALSE
        __send__(@i_mungetc_buf, c)
      else
        @mime_input -= 1
        mime_buf_set(@mime_input, c)
      end
      c
    end

    def mime_getc_buf
      return __send__(@i_mgetc_buf) if @mimebuf_f != FALSE

      c = mime_buf_get(@mime_input)
      @mime_input += 1
      c
    end

    def switch_mime_getc
      return if @i_getc == :mime_getc

      @i_mgetc = @i_getc
      @i_getc = :mime_getc
      @i_mungetc = @i_ungetc
      @i_ungetc = :mime_ungetc
      return unless @mime_f == STRICT_MIME

      @i_mgetc_buf = @i_mgetc
      @i_mgetc = :mime_getc_buf
      @i_mungetc_buf = @i_mungetc
      @i_mungetc = :mime_ungetc_buf
    end

    def unswitch_mime_getc
      if @mime_f == STRICT_MIME
        @i_mgetc = @i_mgetc_buf
        @i_mungetc = @i_mungetc_buf
      end
      @i_getc = @i_mgetc
      @i_ungetc = @i_mungetc
      set_iconv(FALSE, @mime_iconv_back) if @mime_iconv_back
      @mime_iconv_back = nil
    end

    # In buffered mode, the encoded word read ahead up to its "?=", so a
    # broken word passes through undecoded.
    def mime_integrity(pattern)
      @mime_input = @mime_top
      @mime_last = @mime_top
      pattern.each do |byte|
        mime_buf_set(@mime_input, byte)
        @mime_input += 1
      end
      d = 0
      q = @mime_input
      while (c = i_getc) != EOF
        break if ((@mime_input - @mime_top) & MIME_BUF_MASK) == 0

        if c == "=".ord && d == "?".ord
          mime_buf_set(@mime_input, c)
          @mime_input = q
          switch_mime_getc
          return 1
        end
        break unless c == "+".ord || c == "/".ord || c == "=".ord || c == "?".ord || alnum?(c)

        mime_buf_set(@mime_input, c)
        @mime_input += 1
        d = c
      end
      mime_buf_set(@mime_input, c)
      @mime_input += 1
      @mime_last = @mime_input
      @mime_decode_mode = 1
      switch_mime_getc
      1
    end

    # "=?" read: the charset and encoding matched against nkf's patterns.
    def mime_begin_strict
      c1 = 0
      @mime_decode_mode = FALSE
      j = 0
      p = MIME_PATTERNS[j]
      r = ["=".ord, "?".ord]
      i = 2
      while (p[i] || 0) > SP
        r[i] = c1 = i_getc
        if c1 == EOF || toupper(c1) != p[i]
          q = p
          p = nil
          while (j += 1) < MIME_PATTERNS.size
            candidate = MIME_PATTERNS[j]
            k = 2
            k += 1 while k < i && candidate[k] == q[k]
            if k == i && toupper(c1) == (candidate[k] || 0)
              p = candidate
              break
            end
          end
          unless p
            i_ungetc(c1)
            i.times { |index| oconv(0, r[index]) }
            return c1
          end
        end
        i += 1
      end
      @mime_decode_mode = p[i - 2]
      @mime_iconv_back = @iconv
      set_iconv(FALSE, MIME_PRIORITY_FUNC[j])
      clr_code_score(find_inputcode_byfunc(MIME_PRIORITY_FUNC[j]), SCORE_IMIME)

      if @mime_decode_mode == MIME_B
        @mimebuf_f = @unbuf_f ? TRUE : FALSE
        return mime_integrity(MIME_PATTERNS[j]) unless @unbuf_f
      end
      switch_mime_getc
      @mimebuf_f = TRUE
      c1
    end

    # -mN: only "=?" is checked, and a false start is read again from the
    # buffer.
    def mime_begin
      c1 = 0
      k = @mime_last
      mime_buf_set(@mime_last, "=".ord)
      @mime_last += 1
      mime_buf_set(@mime_last, "?".ord)
      @mime_last += 1
      i = 2
      while i < MAXRECOVER
        c1 = i_getc
        mime_buf_set(@mime_last, c1)
        @mime_last += 1
        if c1 == LF || c1 == SP || c1 == CR || c1 == "-".ord || c1 == "_".ord || alnum?(c1)
          i += 1
          next
        end
        if c1 == "=".ord
          i_ungetc(c1)
          @mime_last -= 1
          break
        end
        break if c1 != "?".ord

        c1 = i_getc
        mime_buf_set(@mime_last, c1)
        @mime_last += 1
        i += 1
        break if i >= MAXRECOVER || c1 == EOF

        if c1 == "b".ord || c1 == "B".ord
          @mime_decode_mode = MIME_B
        elsif c1 == "q".ord || c1 == "Q".ord
          @mime_decode_mode = MIME_Q
        else
          break
        end
        c1 = i_getc
        mime_buf_set(@mime_last, c1)
        @mime_last += 1
        i += 1
        break if i >= MAXRECOVER || c1 == EOF

        @mime_decode_mode = FALSE if c1 != "?".ord
        break
      end
      switch_mime_getc
      if @mime_decode_mode == FALSE
        @mime_decode_mode = 1
        return c1
      end
      @mime_last = k
      c1
    end

    def base64decode(c)
      if c > "@".ord
        if c < "[".ord
          c - "A".ord
        elsif c == "_".ord
          "?".ord
        else
          c - "G".ord
        end
      elsif c > "/".ord
        c - "0".ord + "4".ord
      elsif c == "+".ord || c == "-".ord
        ">".ord
      else
        "?".ord
      end
    end

    # The white space after an encoded word's "?=": dropped before the
    # next "=?", kept otherwise, with folded lines joined. `q_encoding`
    # picks the CR rule the Q decoder uses; the B decoder's differs.
    def mime_after_word(q_encoding)
      lwsp = []
      while (c1 = i_getc) != EOF
        case c1
        when LF
          if (c1 = i_getc) != EOF && blank?(c1)
            i_ungetc(SP)
            next
          end
          i_ungetc(c1)
          c1 = LF
        when CR
          if q_encoding
            if (c1 = i_getc) != EOF && c1 == LF
              if (c1 = i_getc) != EOF && blank?(c1)
                i_ungetc(SP)
                next
              end
              i_ungetc(c1)
              i_ungetc(LF)
            else
              i_ungetc(c1)
            end
          elsif (c1 = i_getc) != EOF
            if c1 == SP
              i_ungetc(SP)
              next
            elsif (c1 = i_getc) != EOF && blank?(c1)
              i_ungetc(SP)
              next
            end
            i_ungetc(c1)
            i_ungetc(LF)
          else
            i_ungetc(c1)
          end
          c1 = CR
        when SP, TAB
          lwsp << c1
          next
        end
        break
      end
      if !lwsp.empty? && (c1 != "=".ord || (lwsp.last != SP && lwsp.last != TAB))
        i_ungetc(c1)
        (lwsp.size - 1).downto(1) { |index| i_ungetc(lwsp[index]) }
        c1 = lwsp[0]
      end
      c1
    end

    def mime_getc
      if @mime_top != @mime_last
        c = mime_buf_get(@mime_top)
        @mime_top += 1
        return c
      end
      if @mime_decode_mode == 1 || @mime_decode_mode == FALSE
        @mime_decode_mode = FALSE
        unswitch_mime_getc
        return i_getc
      end

      exit_mode = @mimebuf_f == FIXED_MIME ? @mime_decode_mode : FALSE
      return mime_getc_q(exit_mode) if @mime_decode_mode == MIME_Q

      if @mime_decode_mode != MIME_B
        @mime_decode_mode = FALSE
        return __send__(@i_mgetc)
      end
      mime_getc_b(exit_mode)
    end

    def mime_getc_q(exit_mode)
      return EOF if (c1 = __send__(@i_mgetc)) == EOF

      loop do
        return SP if c1 == "_".ord && @mimebuf_f != FIXED_MIME

        if c1 <= SP || DEL <= c1
          @mime_decode_mode = exit_mode
          return c1
        end
        return c1 if c1 != "=".ord && (c1 != "?".ord || @mimebuf_f == FIXED_MIME)

        @mime_decode_mode = exit_mode
        return EOF if (c2 = __send__(@i_mgetc)) == EOF

        if c1 == "?".ord && c2 == "=".ord && @mimebuf_f != FIXED_MIME
          @input_mode = exit_mode
          return mime_after_word(true)
        end
        if c1 == "=".ord && c2 < SP
          # A soft line break.
          while (c1 = __send__(@i_mgetc)) <= SP
            return EOF if c1 == EOF
          end
          @mime_decode_mode = MIME_Q
          next
        end
        if c1 == "?".ord
          @mime_decode_mode = MIME_Q
          __send__(@i_mungetc, c2)
          return c1
        end
        return EOF if (c3 = __send__(@i_mgetc)) == EOF
        return c2 if c2 <= SP

        @mime_decode_mode = MIME_Q
        return (hex2bin(c2) << 4) + hex2bin(c3)
      end
    end

    # One base64 character, skipping white space unless the decoding is
    # strict. Returns [c, nil] or [nil, value to return].
    def mime_b_char
      loop do
        c = __send__(@i_mgetc)
        return [c, nil] if c > SP
        return [nil, EOF] if c == EOF
        next if @mime_f != STRICT_MIME

        @input_mode = ASCII if @mimebuf_f != FIXED_MIME
        return [nil, c]
      end
    end

    def mime_getc_b(exit_mode)
      mode = @mime_decode_mode
      @mime_decode_mode = exit_mode

      while (c1 = __send__(@i_mgetc)) <= SP
        return EOF if c1 == EOF
      end
      c2, early = mime_b_char
      return early unless c2

      if c1 == "?".ord && c2 == "=".ord
        @input_mode = ASCII
        return mime_after_word(false)
      end
      c3, early = mime_b_char
      return early unless c3

      c4, early = mime_b_char
      return early unless c4

      @mime_decode_mode = mode
      t1 = 0x3f & base64decode(c1)
      t2 = 0x3f & base64decode(c2)
      t3 = 0x3f & base64decode(c3)
      t4 = 0x3f & base64decode(c4)
      return c1 if c2 == "=".ord

      mime_buf_set(@mime_last, ((t1 << 2) & 0x0fc) | ((t2 >> 4) & 0x03))
      @mime_last += 1
      if c3 != "=".ord
        mime_buf_set(@mime_last, ((t2 << 4) & 0x0f0) | ((t3 >> 2) & 0x0f))
        @mime_last += 1
        if c4 != "=".ord
          mime_buf_set(@mime_last, ((t3 << 6) & 0x0c0) | (t4 & 0x3f))
          @mime_last += 1
        end
      end
      c = mime_buf_get(@mime_top)
      @mime_top += 1
      c
    end

    # --- MIME encoding (-M) -------------------------------------------

    def open_mime(mode)
      i = MIME_ENCODE.index(mode)
      i = MIME_PATTERNS.size if i.nil? || i >= MIME_PATTERNS.size
      p = MIME_PATTERNS[i] || MIME_PATTERNS[0]
      @mimeout_mode = MIME_ENCODE_METHOD[i]
      i = 0
      if @base64_count > 45
        if @mimeout_count > 0 && blank?(@mimeout_buf[i])
          __send__(@o_mputc, @mimeout_buf[i])
          i += 1
        end
        put_newline(@o_mputc)
        __send__(@o_mputc, SP)
        @base64_count = 1
        i += 1 if @mimeout_count > 0 && space?(@mimeout_buf[i])
      end
      while i < @mimeout_count
        break unless space?(@mimeout_buf[i])

        __send__(@o_mputc, @mimeout_buf[i])
        @base64_count += 1
        i += 1
      end
      p.each do |byte|
        __send__(@o_mputc, byte)
        @base64_count += 1
      end
      j = @mimeout_count
      @mimeout_count = 0
      while i < j
        mime_putc(@mimeout_buf[i])
        i += 1
      end
    end

    def mime_prechar(c2, c1)
      if @mimeout_mode > 0
        if c2 == EOF
          if @base64_count + @mimeout_count / 3 * 4 > 73
            __send__(@o_base64conv, EOF, 0)
            oconv_newline(@o_base64conv)
            __send__(@o_base64conv, 0, SP)
            @base64_count = 1
          end
        elsif (c2 != 0 || c1 > DEL) && @base64_count + @mimeout_count / 3 * 4 > 66
          __send__(@o_base64conv, EOF, 0)
          oconv_newline(@o_base64conv)
          __send__(@o_base64conv, 0, SP)
          @base64_count = 1
          @mimeout_mode = -1
        end
      elsif c2 != 0
        if c2 != EOF && @base64_count + @mimeout_count / 3 * 4 > 60
          @mimeout_mode = @output_mode == ASCII || @output_mode == ISO_8859_1 ? MIME_Q : MIME_B
          open_mime(@output_mode)
          __send__(@o_base64conv, EOF, 0)
          oconv_newline(@o_base64conv)
          __send__(@o_base64conv, 0, SP)
          @base64_count = 1
          @mimeout_mode = -1
        end
      end
    end

    def close_mime
      __send__(@o_mputc, "?".ord)
      __send__(@o_mputc, "=".ord)
      @base64_count += 2
      @mimeout_mode = 0
    end

    def eof_mime
      case @mimeout_mode
      when 2
        __send__(@o_mputc, cell(BASIS_64, (@base64_state & 0x3) << 4))
        __send__(@o_mputc, "=".ord)
        __send__(@o_mputc, "=".ord)
        @base64_count += 3
      when 1
        __send__(@o_mputc, cell(BASIS_64, (@base64_state & 0xF) << 2))
        __send__(@o_mputc, "=".ord)
        @base64_count += 2
      end
      return unless @mimeout_mode > 0

      if @mimeout_f != FIXED_MIME
        close_mime
      elsif @mimeout_mode != MIME_Q
        @mimeout_mode = MIME_B
      end
    end

    def mimeout_addchar(c)
      case @mimeout_mode
      when MIME_Q
        if c == CR || c == LF
          __send__(@o_mputc, c)
          @base64_count = 0
        elsif !alnum?(c)
          __send__(@o_mputc, "=".ord)
          __send__(@o_mputc, bin2hex((c >> 4) & 0xf))
          __send__(@o_mputc, bin2hex(c & 0xf))
          @base64_count += 3
        else
          __send__(@o_mputc, c)
          @base64_count += 1
        end
      when MIME_B
        @base64_state = c
        __send__(@o_mputc, cell(BASIS_64, c >> 2))
        @mimeout_mode = 2
        @base64_count += 1
      when 2
        __send__(@o_mputc, cell(BASIS_64, ((@base64_state & 0x3) << 4) | ((c & 0xF0) >> 4)))
        @base64_state = c
        @mimeout_mode = 1
        @base64_count += 1
      when 1
        __send__(@o_mputc, cell(BASIS_64, ((@base64_state & 0xF) << 2) | ((c & 0xC0) >> 6)))
        __send__(@o_mputc, cell(BASIS_64, c & 0x3F))
        @mimeout_mode = MIME_B
        @base64_count += 2
      else
        __send__(@o_mputc, c)
        @base64_count += 1
      end
    end

    def mimeout_push(c)
      @mimeout_buf[@mimeout_count] = c
      @mimeout_count += 1
    end

    def mime_putc(c)
      if @mimeout_f == FIXED_MIME
        if @mimeout_mode == MIME_Q
          if @base64_count > 71
            if c != CR && c != LF
              __send__(@o_mputc, "=".ord)
              put_newline(@o_mputc)
            end
            @base64_count = 0
          end
        else
          if @base64_count > 71
            eof_mime
            put_newline(@o_mputc)
            @base64_count = 0
          end
          eof_mime if c == EOF
        end
        mimeout_addchar(c) if c != EOF
        return
      end

      return mime_putc_eof if c == EOF

      lastchar = @mimeout_count > 0 ? @mimeout_buf[@mimeout_count - 1] : -1

      if @mimeout_mode == MIME_Q && c <= DEL && (@output_mode == ASCII || @output_mode == ISO_8859_1)
        if c == CR || c == LF
          close_mime
          __send__(@o_mputc, c)
          @base64_count = 0
          return
        elsif c <= SP
          close_mime
          if @base64_count > 70
            put_newline(@o_mputc)
            @base64_count = 0
          end
          unless blank?(c)
            __send__(@o_mputc, SP)
            @base64_count += 1
          end
        else
          if @base64_count > 70
            close_mime
            put_newline(@o_mputc)
            __send__(@o_mputc, SP)
            @base64_count = 1
            open_mime(@output_mode)
          end
          unless noescape_mime?(c)
            mimeout_addchar(c)
            return
          end
        end
        if c != ESC
          __send__(@o_mputc, c)
          @base64_count += 1
          return
        end
      end

      plain = c <= DEL && (@output_mode == ASCII || @output_mode == ISO_8859_1 || @output_mode == UTF_8)
      if @mimeout_mode <= 0
        return if plain && mime_putc_plain(c)

        unless plain
          if lastchar == CR || lastchar == LF
            @mimeout_count.times { |i| __send__(@o_mputc, @mimeout_buf[i]) }
            @base64_count = 0
            @mimeout_count = 0
          end
          if lastchar == SP
            (@mimeout_count - 1).times do |i|
              __send__(@o_mputc, @mimeout_buf[i])
              @base64_count += 1
            end
            @mimeout_buf[0] = SP
            @mimeout_count = 1
          end
          open_mime(@output_mode)
        end
      elsif plain
        return if mime_putc_encoded(c, lastchar)
      end
      if @mimeout_count > 0
        j = @mimeout_count
        @mimeout_count = 0
        i = 0
        while i < j
          break if @mimeout_buf[i] == CR || @mimeout_buf[i] == LF

          mimeout_addchar(@mimeout_buf[i])
          i += 1
        end
        if i < j
          eof_mime
          @base64_count = 0
          while i < j
            __send__(@o_mputc, @mimeout_buf[i])
            i += 1
          end
          open_mime(@output_mode)
        end
      end
      mimeout_addchar(c)
    end

    def mime_putc_eof
      open_mime(@output_mode) if @mimeout_mode == -1 && @mimeout_count > 1
      j = @mimeout_count
      @mimeout_count = 0
      i = 0
      if @mimeout_mode > 0
        if j > 0 && !blank?(@mimeout_buf[j - 1])
          while i < j
            break if space?(@mimeout_buf[i]) && @base64_count < 71

            mimeout_addchar(@mimeout_buf[i])
            i += 1
          end
          eof_mime
          while i < j
            mimeout_addchar(@mimeout_buf[i])
            i += 1
          end
        else
          while i < j
            mimeout_addchar(@mimeout_buf[i])
            i += 1
          end
          eof_mime
        end
      else
        while i < j
          mimeout_addchar(@mimeout_buf[i])
          i += 1
        end
      end
    end

    BOUNDARY = "boundary=\"".bytes.freeze

    # mime_putc for a plain character outside an encoded word. True when
    # the character is dealt with.
    def mime_putc_plain(c)
      if space?(c)
        flag = @mimeout_mode == -1
        if c == CR || c == LF
          if flag
            open_mime(@output_mode)
            @output_mode = 0
          else
            @base64_count = 0
          end
        end
        @mimeout_count.times do |i|
          __send__(@o_mputc, @mimeout_buf[i])
          if @mimeout_buf[i] == CR || @mimeout_buf[i] == LF
            @base64_count = 0
          else
            @base64_count += 1
          end
        end
        if flag
          eof_mime
          @base64_count = 0
          @mimeout_mode = 0
        end
        @mimeout_buf[0] = c
        @mimeout_count = 1
      else
        if @base64_count > 1 && @base64_count + @mimeout_count > 76 &&
           @mimeout_buf[0] != CR && @mimeout_buf[0] != LF
          len = BOUNDARY.size
          i = 0
          while i < @mimeout_count - len
            if @mimeout_buf[i, len] == BOUNDARY
              i += len - 2
              break
            end
            i += 1
          end
          if i == 0 || i == @mimeout_count - len
            put_newline(@o_mputc)
            @base64_count = 0
            unless space?(@mimeout_buf[0])
              __send__(@o_mputc, SP)
              @base64_count += 1
            end
          else
            (0..i).each { |index| __send__(@o_mputc, @mimeout_buf[index]) }
            put_newline(@o_mputc)
            @base64_count = 1
            ((i + 1)..@mimeout_count).each { |index| @mimeout_buf[index - i] = @mimeout_buf[index] || 0 }
            @mimeout_count -= i
          end
        end
        mimeout_push(c)
        open_mime(@output_mode) if @mimeout_count > MIMEOUT_BUF_LENGTH
      end
      true
    end

    # mime_putc for a plain character inside an encoded word. True when
    # the character is dealt with.
    def mime_putc_encoded(c, lastchar)
      if lastchar == CR || lastchar == LF
        if blank?(c)
          @mimeout_count.times { |i| mimeout_addchar(@mimeout_buf[i]) }
        else
          eof_mime
          @mimeout_count.times { |i| __send__(@o_mputc, @mimeout_buf[i]) }
          @base64_count = 0
        end
        @mimeout_count = 0
        mimeout_push(c)
        return true
      end
      if space?(c)
        i = 0
        while i < @mimeout_count
          if SP < @mimeout_buf[i] && @mimeout_buf[i] < DEL
            eof_mime
            i = 0
            while i < @mimeout_count
              __send__(@o_mputc, @mimeout_buf[i])
              @base64_count += 1
              i += 1
            end
            @mimeout_count = 0
          end
          i += 1
        end
        mimeout_push(c)
        if @mimeout_count > MIMEOUT_BUF_LENGTH
          eof_mime
          @mimeout_count.times do |index|
            __send__(@o_mputc, @mimeout_buf[index])
            @base64_count += 1
          end
          @mimeout_count = 0
        end
        return true
      end
      if @mimeout_count > 0 && SP < c && c != "=".ord
        mimeout_push(c)
        if @mimeout_count > MIMEOUT_BUF_LENGTH
          j = @mimeout_count
          @mimeout_count = 0
          j.times { |i| mimeout_addchar(@mimeout_buf[i]) }
        end
        return true
      end
      false
    end

    def base64_conv(c2, c1)
      mime_prechar(c2, c1)
      __send__(@o_base64conv, c2, c1)
    end

    # --- The conversion -----------------------------------------------

    # module_connection: the filter chains that the options select.
    def module_connection
      set_input_encoding(@input_encoding) if @input_encoding
      @output_encoding ||= ENCODINGS[UTF_8]
      set_output_encoding(@output_encoding)
      @oconv = @output_encoding.base.oconv
      @o_putc = :std_putc
      @output_mode = UTF_8 if @output_encoding.unicode?
      @x0201_f = TRUE if @x0201_f == NKF_UNSPECIFIED

      @o_putc = :no_putc if @noout_f || @guess_f != 0
      if @mimeout_f != FALSE
        @o_mputc = @o_putc
        @o_putc = :mime_putc
        if @mimeout_f == TRUE
          @o_base64conv = @oconv
          @oconv = :base64_conv
        end
      end
      if @eolmode_f != 0 || @guess_f != 0
        @o_eol_conv = @oconv
        @oconv = :eol_conv
      end
      if @rot_f
        @o_rot_conv = @oconv
        @oconv = :rot_conv
      end
      if @iso2022jp_f
        @o_iso2022jp_check_conv = @oconv
        @oconv = :iso2022jp_check_conv
      end
      if @hira_f != 0
        @o_hira_conv = @oconv
        @oconv = :hira_conv
      end
      if @fold_f
        @o_fconv = @oconv
        @oconv = :fold_conv
        @f_line = 0
      end
      if @alpha_f != 0 || @x0201_f != FALSE
        @o_zconv = @oconv
        @oconv = :z_conv
      end

      @i_getc = :std_getc
      @i_ungetc = :std_ungetc
      if @cap_f
        @i_cgetc, @i_getc = @i_getc, :cap_getc
        @i_cungetc, @i_ungetc = @i_ungetc, :cap_ungetc
      end
      if @url_f
        @i_ugetc, @i_getc = @i_getc, :url_getc
        @i_uungetc, @i_ungetc = @i_ungetc, :url_ungetc
      end
      if @numchar_f
        @i_ngetc, @i_getc = @i_getc, :numchar_getc
        @i_nungetc, @i_ungetc = @i_ungetc, :numchar_ungetc
      end
      if @nfc_f
        @i_nfc_getc, @i_getc = @i_getc, :nfc_getc
        @i_nfc_ungetc, @i_ungetc = @i_ungetc, :nfc_ungetc
      end
      if @mime_f != FALSE && @mimebuf_f == FIXED_MIME
        @i_mgetc, @i_getc = @i_getc, :mime_getc
        @i_mungetc, @i_ungetc = @i_ungetc, :mime_ungetc
      end
      if (@broken_f & 1) != 0
        @i_bgetc, @i_getc = @i_getc, :broken_getc
        @i_bungetc, @i_ungetc = @i_ungetc, :broken_ungetc
      end
      if @input_encoding
        set_iconv(-TRUE, @input_encoding.base.iconv)
      else
        set_iconv(FALSE, :e_iconv)
      end
      @input_code_list.each { |p| status_reinit(p) }
    end

    def set_input_mode(mode)
      @input_mode = mode
      @shift_mode = 0
      set_input_codename("ISO-2022-JP")
      debug("ISO-2022-JP")
    end

    # kanji_convert: the main loop.
    def kanji_convert
      c2 = 0
      @shift_mode = 0
      @g2 = 0
      @is_8bit = @input_encoding && !@input_encoding.ascii_compatible?
      @input_mode = ASCII
      @output_mode = ASCII
      module_connection
      check_bom

      if @iconv == :w_iconv32
        convert_utf32
      elsif @iconv == :w_iconv16
        convert_utf16
      else
        while (c1 = i_getc) != EOF
          code_status(c1) unless @input_encoding
          if c2 != 0
            # The second byte.
            limit = @input_encoding&.cp5022x? ? 0x92 : DEL
            if c2 > limit
              if @estab_f == FALSE && @mime_decode_mode == FALSE
                break if h_conv(c2, c1) == EOF

                c2 = 0
                next
              elsif c1 < 0x40
                c2 = 0
                next
              end
            end
          elsif unicode_p?(c1)
            oconv(0, c1)
            next
          else
            action, c2, c1 = first_byte(c1)
            case action
            when :next then next
            when :last then break
            end
          end
          send_char(c2, c1)
          c2 = 0
        end
      end

      iconv(EOF, 0, 0)
      return unless @input_codename.nil? && @is_8bit

      result = @input_code_list.first
      @input_code_list.each { |p| result = p if p.score < result.score }
      set_input_codename(result.name)
      debug(result.name)
    end

    # A first byte: [:send, c2, c1] to convert what it makes, [:next, c2,
    # c1] to read on with c2 kept, or [:last] to stop.
    def first_byte(c1)
      if @input_mode == JIS_X_0208 && DEL <= c1 && c1 < 0x92
        [:next, c1, c1]
      elsif @input_codename&.start_with?("I") && 0xA1 <= c1 && c1 <= 0xDF
        [:send, JIS_X_0201_1976_K, c1 & 0x7f]
      elsif c1 > DEL
        if @estab_f == FALSE && !@iso8859_f
          [:next, c1, c1]
        elsif @iso8859_f
          [:send, ISO_8859_1, c1 & 0x7f]
        elsif (@iconv == :s_iconv && 0xA0 <= c1 && c1 <= 0xDF) ||
              (@ms_ucs_map_f == UCS_MAP_CP10001 && (c1 == 0xFD || c1 == 0xFE))
          [:send, JIS_X_0201_1976_K, c1 & 0x7f]
        else
          [:next, c1, c1]
        end
      elsif SP < c1 && c1 < DEL
        if @shift_mode != 0
          if @iso8859_f
            [:send, ISO_8859_1, c1]
          elsif SP <= c1 && c1 <= 0x5F
            [:send, JIS_X_0201_1976_K, c1]
          else
            [:next, 0, c1]
          end
        elsif [JIS_X_0208, JIS_X_0212, JIS_X_0213_1, JIS_X_0213_2].include?(@input_mode)
          [:next, c1, c1]
        elsif c1 == "=".ord && @mime_f != FALSE && @mime_decode_mode == FALSE
          mime_start
        else
          [:send, 0, c1]
        end
      elsif c1 == SI && (!@is_8bit || @mime_decode_mode != FALSE)
        @shift_mode = 0
        [:next, 0, c1]
      elsif c1 == SO && (!@is_8bit || @mime_decode_mode != FALSE)
        @shift_mode = 1
        [:next, 0, c1]
      elsif c1 == ESC && (!@is_8bit || @mime_decode_mode != FALSE)
        escape_sequence
      elsif c1 == ESC && @iconv == :s_iconv
        jphone_escape
      elsif (c1 == LF || c1 == CR) && (@broken_f & 4) != 0
        @input_mode = ASCII
        set_iconv(FALSE, nil)
        [:send, 0, c1]
      else
        [:send, 0, c1]
      end
    end

    # "=" in ASCII: perhaps the start of a MIME encoded word.
    def mime_start
      c1 = i_getc
      if c1 == EOF
        oconv(0, "=".ord)
        [:last]
      elsif c1 == "?".ord
        result = @mime_f == STRICT_MIME ? mime_begin_strict : mime_begin
        result == EOF ? [:last] : [:next, 0, result]
      else
        oconv(0, "=".ord)
        i_ungetc(c1)
        [:next, 0, c1]
      end
    end

    # An ISO-2022 escape sequence.
    def escape_sequence
      c1 = i_getc
      if c1 == EOF
        oconv(0, ESC)
        return [:last]
      end
      case c1
      when "&".ord # IRR
        i_getc == EOF ? [:last] : [:next, 0, 0]
      when "$".ord # GZDMx
        c1 = i_getc
        if c1 == EOF
          [:last]
        elsif c1 == "@".ord || c1 == "B".ord
          set_input_mode(JIS_X_0208)
          [:next, 0, c1]
        elsif c1 == "(".ord # GZDM4
          c1 = i_getc
          case c1
          when EOF then return [:last]
          when "@".ord, "B".ord then set_input_mode(JIS_X_0208)
          when "D".ord then set_input_mode(JIS_X_0212)
          when "O".ord, "Q".ord then set_input_mode(JIS_X_0213_1)
          when "P".ord then set_input_mode(JIS_X_0213_2)
          else
            [ESC, "$".ord, "(".ord, c1].each { |byte| oconv(0, byte) }
          end
          [:next, 0, c1]
        elsif (@broken_f & 0x2) != 0
          @input_mode = JIS_X_0208
          @shift_mode = 0
          [:next, 0, c1]
        else
          [ESC, "$".ord, c1].each { |byte| oconv(0, byte) }
          [:next, 0, c1]
        end
      when "(".ord # GZD4
        c1 = i_getc
        if c1 == EOF
          [:last]
        elsif c1 == "I".ord
          set_input_mode(JIS_X_0201_1976_K)
          @shift_mode = 1
          [:next, 0, c1]
        elsif c1 == "B".ord || c1 == "J".ord || c1 == "H".ord || (@broken_f & 0x2) != 0
          set_input_mode(ASCII)
          [:next, 0, c1]
        else
          oconv(0, ESC)
          oconv(0, "(".ord)
          [:send, 0, c1]
        end
      when ".".ord # G2D6
        c1 = i_getc
        if c1 == EOF
          [:last]
        elsif c1 == "A".ord
          @g2 = ISO_8859_1
          [:next, 0, c1]
        else
          oconv(0, ESC)
          oconv(0, ".".ord)
          [:send, 0, c1]
        end
      when "N".ord # SS2
        c1 = i_getc
        return [:send, ISO_8859_1, c1] if @g2 == ISO_8859_1

        i_ungetc(c1)
        oconv(0, ESC)
        [:send, 0, c1]
      else
        i_ungetc(c1)
        oconv(0, ESC)
        [:next, 0, c1]
      end
    end

    # ESC in Shift_JIS: the J-PHONE emoji escapes.
    JPHONE_EMOJI_FIRST_TABLE = [0xE1E0, 0xDFE0, 0xE2E0, 0xE3E0, 0xE4E0, 0xDFE0, 0xE0E0].freeze

    def jphone_escape
      c1 = i_getc
      if c1 == EOF
        oconv(0, ESC)
        return [:last]
      elsif c1 != "$".ord
        i_ungetc(c1)
        oconv(0, ESC)
        return [:next, 0, c1]
      end
      c1 = i_getc
      return [:last] if c1 == EOF

      unless ("E".ord <= c1 && c1 <= "G".ord) || ("O".ord <= c1 && c1 <= "Q".ord)
        oconv(0, ESC)
        oconv(0, "$".ord)
        return [:send, 0, c1]
      end
      c3 = unicode_new(JPHONE_EMOJI_FIRST_TABLE[c1 % 7])
      c1 = i_getc
      return [:last] if c1 == EOF

      while SP <= c1 && c1 <= "z".ord
        oconv(0, c1 + c3)
        break if (c1 = i_getc) == EOF
      end
      [:next, 0, c1]
    end

    # The character a first and second byte make, by the input mode.
    def send_char(c2, c1)
      case @input_mode
      when ASCII
        case iconv(c2, c1, 0)
        when -2
          # A four-byte UTF-8 character.
          if (c3 = i_getc) != EOF
            code_status(c3)
            c3 <<= 8
            if (c4 = i_getc) != EOF
              code_status(c4)
              iconv(c2, c1, c3 | c4)
            end
          end
        when -3
          # A UTF-8 character that may combine with the next one.
          if (c3 = i_getc) != EOF
            if (c4 = i_getc) != EOF
              if w_iconv_combine(c2, c1, 0, c3, c4, 0) != 0
                i_ungetc(c4)
                i_ungetc(c3)
                w_iconv_nocombine(c2, c1, 0)
              end
            else
              i_ungetc(c3)
              w_iconv_nocombine(c2, c1, 0)
            end
          else
            w_iconv_nocombine(c2, c1, 0)
          end
        when -1
          # A three-byte EUC-JP or UTF-8 character.
          if (c3 = i_getc) != EOF
            code_status(c3)
            send_combining6(c2, c1, c3) if iconv(c2, c1, c3) == -3
          end
        end
      when JIS_X_0208, JIS_X_0213_1
        if @ms_ucs_map_f != UCS_MAP_ASCII && 0x7F <= c2 && c2 <= 0x92 && 0x21 <= c1 && c1 <= 0x7E
          # CP932 user-defined characters.
          c1 = unicode_new((c2 - 0x7F) * 94 + c1 - 0x21 + 0xE000)
          c2 = 0
        end
        oconv(c2, c1)
      when JIS_X_0212, JIS_X_0213_2
        oconv(PREFIX_EUCG3 | c2, c1)
      else
        oconv(@input_mode, c1)
      end
    end

    def send_combining6(c2, c1, c3)
      if (c4 = i_getc) == EOF
        w_iconv_nocombine(c2, c1, c3)
      elsif (c5 = i_getc) == EOF
        i_ungetc(c4)
        w_iconv_nocombine(c2, c1, c3)
      elsif (c6 = i_getc) == EOF
        i_ungetc(c5)
        i_ungetc(c4)
        w_iconv_nocombine(c2, c1, c3)
      elsif w_iconv_combine(c2, c1, c3, c4, c5, c6) != 0
        i_ungetc(c6)
        i_ungetc(c5)
        i_ungetc(c4)
        w_iconv_nocombine(c2, c1, c3)
      end
    end

    def convert_utf32
      while (c1 = i_getc) != EOF && (c2 = i_getc) != EOF && (c3 = i_getc) != EOF && (c4 = i_getc) != EOF
        next unless nkf_iconv_utf_32(c1, c2, c3, c4) == NKF_ICONV_WAIT_COMBINING_CHAR

        if (c5 = i_getc) != EOF && (c6 = i_getc) != EOF && (c7 = i_getc) != EOF && (c8 = i_getc) != EOF
          if nkf_iconv_utf_32_combine(c1, c2, c3, c4, c5, c6, c7, c8) != 0
            i_ungetc(c8)
            i_ungetc(c7)
            i_ungetc(c6)
            i_ungetc(c5)
            nkf_iconv_utf_32_nocombine(c1, c2, c3, c4)
          end
        else
          nkf_iconv_utf_32_nocombine(c1, c2, c3, c4)
        end
      end
    end

    def convert_utf16
      while (c1 = i_getc) != EOF && (c2 = i_getc) != EOF
        ret = nkf_iconv_utf_16(c1, c2, 0, 0)
        if ret == NKF_ICONV_NEED_TWO_MORE_BYTES && (c3 = i_getc) != EOF && (c4 = i_getc) != EOF
          nkf_iconv_utf_16(c1, c2, c3, c4)
        elsif ret == NKF_ICONV_WAIT_COMBINING_CHAR
          if (c3 = i_getc) != EOF && (c4 = i_getc) != EOF
            if nkf_iconv_utf_16_combine(c1, c2, c3, c4) != 0
              i_ungetc(c4)
              i_ungetc(c3)
              nkf_iconv_utf_16_nocombine(c1, c2)
            end
          else
            nkf_iconv_utf_16_nocombine(c1, c2)
          end
        end
      end
    end
  end
  private_constant :Converter

  AUTO = nil
  NOCONV = nil
  UNKNOWN = nil
  BINARY = Converter.ruby_encoding("BINARY")
  ASCII = Converter.ruby_encoding("US-ASCII")
  JIS = Converter.ruby_encoding("ISO-2022-JP")
  EUC = Converter.ruby_encoding("EUC-JP")
  SJIS = Converter.ruby_encoding("Shift_JIS")
  UTF8 = Encoding::UTF_8
  UTF16 = Converter.ruby_encoding("UTF-16BE")
  UTF32 = Converter.ruby_encoding("UTF-32BE")

  # Full version string of nkf
  VERSION = String.new("#{Converter::NKF_VERSION} (#{Converter::NKF_RELEASE_DATE})")
  # Version of nkf
  NKF_VERSION = String.new(Converter::NKF_VERSION)
  # Release date of nkf
  NKF_RELEASE_DATE = String.new(Converter::NKF_RELEASE_DATE)
  # Version of nkf library
  GEM_VERSION = String.new("0.3.0")

  module_function

  #  call-seq:
  #     NKF.nkf(opt, str)   => string
  #
  #  Convert _str_ and return converted result.
  #  Conversion details are specified by _opt_ as String.
  def nkf(opt, str) = Converter.convert(opt, str)

  #  call-seq:
  #     NKF.guess(str)  => encoding
  #
  #  Returns guessed encoding of _str_ by nkf routine.
  def guess(str) = Converter.guess(str)
end
