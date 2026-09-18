# frozen_string_literal: true

require "spec_helper"

describe "Encoding: case mapping" do
  it "casecmp incompatible encoding is nil" do
    result = ze0(<<~'RUBY')
      # `String#casecmp` and `#casecmp?` against an incompatibly-encoded operand
      # answer nil; zeo compares the bytes anyway and answers an ordering.
      # (Found by the 2026-08-24 probe sweep.)
      p "abc".casecmp("ABC".encode("UTF-16LE"))
      p "abc".casecmp?("ABC".encode("UTF-16LE"))
    RUBY

    _(result).must_answer "nil\nnil\n"
  end

  it "cesu8 holds unicode code points" do
    result = ze0(<<~'RUBY')
      # CESU-8 holds Unicode's code points: three bytes as UTF-8 writes them,
      # or six for a character past the BMP, a pair of surrogates.
      c = "aé日\u{1F600}".encode("CESU-8")
      p c, c.length, c.ord, c[3].ord, c.codepoints, c.bytes.size
      p c.upcase.b, c.swapcase.b, c.capitalize.b, c.reverse.b, c.dump
      p 0xE9.chr("CESU-8").b, 0x1F600.chr("CESU-8").b, (0xD800.chr("CESU-8").b rescue $!), (0x110000.chr("CESU-8") rescue $!)
      s = +"x".encode("CESU-8"); s << 0x1F601; p s.b
      p c.each_grapheme_cluster.count, c.center(9, "*").b, c.inspect, c[3].inspect
      p "\xED\xA0\x80".b.force_encoding("CESU-8").valid_encoding?, "\xED\xA0\x80".b.force_encoding("CESU-8").inspect
      p (("\xFF".b.force_encoding("CESU-8")).ord rescue $!)
      m = "aé".b.force_encoding("UTF8-MAC")
      p (0xD800.chr("UTF8-MAC") rescue $!), ("\xFF".b.force_encoding("UTF8-MAC").ord rescue $!), (m << 0xD800 rescue $!)
      p m.dump, "日".encode("EUC-JP").dump, "é".dump

    RUBY

    _(result).must_answer <<~'OUT'
      "a\u00E9\u65E5\u{1F600}"
      4
      97
      128512
      [97, 233, 26085, 128512]
      12
      "A\xC3\x89\xE6\x97\xA5\xED\xA0\xBD\xED\xB8\x80"
      "A\xC3\x89\xE6\x97\xA5\xED\xA0\xBD\xED\xB8\x80"
      "A\xC3\xA9\xE6\x97\xA5\xED\xA0\xBD\xED\xB8\x80"
      "\xED\xA0\xBD\xED\xB8\x80\xE6\x97\xA5\xC3\xA9a"
      "\"a\\xC3\\xA9\\xE6\\x97\\xA5\\xED\\xA0\\xBD\\xED\\xB8\\x80\""
      "\xC3\xA9"
      "\xED\xA0\xBD\xED\xB8\x80"
      #<RangeError: invalid codepoint 0xD800 in CESU-8>
      #<RangeError: 1114112 out of char range>
      "x\xED\xA0\xBD\xED\xB8\x81"
      4
      "**a\xC3\xA9\xE6\x97\xA5\xED\xA0\xBD\xED\xB8\x80***"
      "\"a\\u00E9\\u65E5\\u{1F600}\""
      "\"\\u{1F600}\""
      false
      "\"\\xED\\xA0\\x80\""
      #<ArgumentError: invalid byte sequence in CESU-8>
      #<RangeError: invalid codepoint 0xD800 in UTF8-MAC>
      #<ArgumentError: invalid byte sequence in UTF8-MAC>
      #<RangeError: invalid codepoint 0xD800 in UTF8-MAC>
      "\"a\\xC3\\xA9\""
      "\"\\xC6\\xFC\""
      "\"\\u00E9\""
    OUT
  end

  it "encoding registry" do
    result = ze0(<<~'RUBY')
      # Every row of `Encoding.list`, generated from the ruby 4.0.6 oracle by
      # `tools/encoding_tables.rb`. The whole list is printed because the registry
      # IS the contract: the order, the names, the aliases, `dummy?` and
      # `ascii_compatible?` are all reflection reads, and each one of them feeds a
      # constant.

      def show(label)
        puts "#{label}: #{yield.inspect}"
      rescue Exception => e # rubocop:disable Lint/RescueException
        puts "#{label}: #{e.class}: #{e.message}"
      end

      puts "list: #{Encoding.list.size}"
      Encoding.list.each do |e|
        puts [e.name, e.names.join(","), e.dummy?, e.ascii_compatible?, e.inspect].join("\t")
      end
      puts "name_list: #{Encoding.name_list.size}"
      puts "aliases: #{Encoding.aliases.size}"
      puts "constants: #{Encoding.constants.count { |c| Encoding.const_get(c).is_a?(Encoding) }}"

      # The two constant spellings CRuby gives one mixed-case name, and the digit
      # rule that gives `646` none of its own.
      show("Windows_1250") { Encoding::Windows_1250 }
      show("WINDOWS_1250") { Encoding::WINDOWS_1250 }
      show("EucJP") { Encoding::EucJP }
      show("EUCJP") { Encoding::EUCJP }
      show("EBCDIC_CP_US") { Encoding::EBCDIC_CP_US }
      show("Big5_HKSCS_2008") { Encoding::Big5_HKSCS_2008 }
      show("no 646 constant") { Encoding.constants.include?(:"646") }
      show("UNICODE_VERSION") { Encoding::UNICODE_VERSION }

      # The runtime selectors follow `default_external`/`default_internal` rather
      # than sitting in any row's alias list.
      show("default_external names") { Encoding.default_external.names }
      show("internal in name_list") { Encoding.name_list.include?("internal") }
      show("aliases has internal") { Encoding.aliases.key?("internal") }
      show("find external") { Encoding.find("external") }
      show("find internal") { Encoding.find("internal") }
      show("find Latin-1") { Encoding.find("Latin-1") }

      # The single-byte families this runtime now maps for real.
      show("ISO-8859-5 cyrillic") { "\xE0".dup.force_encoding("ISO-8859-5").encode("UTF-8") }
      show("KOI8-U ghe") { "\xAD".dup.force_encoding("KOI8-U").encode("UTF-8") }
      show("IBM437 box") { "\xDB".dup.force_encoding("IBM437").encode("UTF-8") }
      show("CP866 be") { "\xE0".dup.force_encoding("CP866").encode("UTF-8") }
      show("macRoman omega") { "\xBD".dup.force_encoding("macRoman").encode("UTF-8") }
      show("TIS-620 thai") { "\xA1".dup.force_encoding("TIS-620").encode("UTF-8") }
      show("Windows-874 thai") { "\xA1".dup.force_encoding("Windows-874").encode("UTF-8") }
      show("Windows-1258 dong") { "\xFE".dup.force_encoding("Windows-1258").encode("UTF-8") }
      show("into ISO-8859-7") { "αβ".encode("ISO-8859-7").bytes }
      show("into IBM866") { "АБ".encode("IBM866").bytes }
      show("ISO-8859-3 unassigned") { "\xA5".dup.force_encoding("ISO-8859-3").encode("UTF-8") }
      show("ISO-8859-3 valid") { "\xA5".dup.force_encoding("ISO-8859-3").valid_encoding? }
      show("ISO-8859-3 length") { "\xA5\xA6".dup.force_encoding("ISO-8859-3").length }
      show("ISO-8859-9 upcase") { "\xFD".dup.force_encoding("ISO-8859-9").upcase.bytes }

      # Registered-only rows answer every reflection question and carry ASCII
      # through. What they cannot do is convert their own high bytes -- see
      # `tests/gaps/encoding_registered_only.rb`.
      show("EUC-KR ascii") { "abc".encode("EUC-KR").bytes }
      show("EUC-KR ascii back") { "abc".dup.force_encoding("EUC-KR").encode("UTF-8") }
      show("EUC-KR compatible?") { Encoding.compatible?("abc", "d".dup.force_encoding("EUC-KR")) }
      show("EUC-KR names") { Encoding::EUC_KR.names }
      show("EUC-KR dummy?") { Encoding::EUC_KR.dummy? }
      show("EUC-KR ascii_compatible?") { Encoding::EUC_KR.ascii_compatible? }
    RUBY

    _(result).must_answer <<~'OUT'
      list: 103
      ASCII-8BIT	ASCII-8BIT,BINARY	false	true	#<Encoding:BINARY (ASCII-8BIT)>
      UTF-8	UTF-8,CP65001,locale,external,filesystem	false	true	#<Encoding:UTF-8>
      US-ASCII	US-ASCII,ASCII,ANSI_X3.4-1968,646	false	true	#<Encoding:US-ASCII>
      UTF-16BE	UTF-16BE,UCS-2BE	false	false	#<Encoding:UTF-16BE>
      UTF-16LE	UTF-16LE	false	false	#<Encoding:UTF-16LE>
      UTF-32BE	UTF-32BE,UCS-4BE	false	false	#<Encoding:UTF-32BE>
      UTF-32LE	UTF-32LE,UCS-4LE	false	false	#<Encoding:UTF-32LE>
      UTF-16	UTF-16	true	false	#<Encoding:UTF-16 (dummy)>
      UTF-32	UTF-32	true	false	#<Encoding:UTF-32 (dummy)>
      UTF8-MAC	UTF8-MAC,UTF-8-MAC,UTF-8-HFS	false	true	#<Encoding:UTF8-MAC>
      EUC-JP	EUC-JP,eucJP	false	true	#<Encoding:EUC-JP>
      Windows-31J	Windows-31J,CP932,csWindows31J,SJIS,PCK	false	true	#<Encoding:Windows-31J>
      Big5	Big5	false	true	#<Encoding:Big5>
      Big5-HKSCS	Big5-HKSCS,Big5-HKSCS:2008	false	true	#<Encoding:Big5-HKSCS>
      Big5-UAO	Big5-UAO	false	true	#<Encoding:Big5-UAO>
      CESU-8	CESU-8	false	true	#<Encoding:CESU-8>
      CP949	CP949	false	true	#<Encoding:CP949>
      Emacs-Mule	Emacs-Mule	false	true	#<Encoding:Emacs-Mule>
      EUC-KR	EUC-KR,eucKR	false	true	#<Encoding:EUC-KR>
      EUC-TW	EUC-TW,eucTW	false	true	#<Encoding:EUC-TW>
      GB18030	GB18030	false	true	#<Encoding:GB18030>
      GBK	GBK,CP936	false	true	#<Encoding:GBK>
      ISO-8859-1	ISO-8859-1,ISO8859-1	false	true	#<Encoding:ISO-8859-1>
      ISO-8859-2	ISO-8859-2,ISO8859-2	false	true	#<Encoding:ISO-8859-2>
      ISO-8859-3	ISO-8859-3,ISO8859-3	false	true	#<Encoding:ISO-8859-3>
      ISO-8859-4	ISO-8859-4,ISO8859-4	false	true	#<Encoding:ISO-8859-4>
      ISO-8859-5	ISO-8859-5,ISO8859-5	false	true	#<Encoding:ISO-8859-5>
      ISO-8859-6	ISO-8859-6,ISO8859-6	false	true	#<Encoding:ISO-8859-6>
      ISO-8859-7	ISO-8859-7,ISO8859-7	false	true	#<Encoding:ISO-8859-7>
      ISO-8859-8	ISO-8859-8,ISO8859-8	false	true	#<Encoding:ISO-8859-8>
      ISO-8859-9	ISO-8859-9,ISO8859-9	false	true	#<Encoding:ISO-8859-9>
      ISO-8859-10	ISO-8859-10,ISO8859-10	false	true	#<Encoding:ISO-8859-10>
      ISO-8859-11	ISO-8859-11,ISO8859-11	false	true	#<Encoding:ISO-8859-11>
      ISO-8859-13	ISO-8859-13,ISO8859-13	false	true	#<Encoding:ISO-8859-13>
      ISO-8859-14	ISO-8859-14,ISO8859-14	false	true	#<Encoding:ISO-8859-14>
      ISO-8859-15	ISO-8859-15,ISO8859-15	false	true	#<Encoding:ISO-8859-15>
      ISO-8859-16	ISO-8859-16,ISO8859-16	false	true	#<Encoding:ISO-8859-16>
      KOI8-R	KOI8-R,CP878	false	true	#<Encoding:KOI8-R>
      KOI8-U	KOI8-U	false	true	#<Encoding:KOI8-U>
      Shift_JIS	Shift_JIS	false	true	#<Encoding:Shift_JIS>
      Windows-1250	Windows-1250,CP1250	false	true	#<Encoding:Windows-1250>
      Windows-1251	Windows-1251,CP1251	false	true	#<Encoding:Windows-1251>
      Windows-1252	Windows-1252,CP1252	false	true	#<Encoding:Windows-1252>
      Windows-1253	Windows-1253,CP1253	false	true	#<Encoding:Windows-1253>
      Windows-1254	Windows-1254,CP1254	false	true	#<Encoding:Windows-1254>
      Windows-1257	Windows-1257,CP1257	false	true	#<Encoding:Windows-1257>
      IBM437	IBM437,CP437	false	true	#<Encoding:IBM437>
      IBM720	IBM720,CP720	false	true	#<Encoding:IBM720>
      IBM737	IBM737,CP737	false	true	#<Encoding:IBM737>
      IBM775	IBM775,CP775	false	true	#<Encoding:IBM775>
      CP850	CP850,IBM850	false	true	#<Encoding:CP850>
      IBM852	IBM852	false	true	#<Encoding:IBM852>
      CP852	CP852	false	true	#<Encoding:CP852>
      IBM855	IBM855	false	true	#<Encoding:IBM855>
      CP855	CP855	false	true	#<Encoding:CP855>
      IBM857	IBM857,CP857	false	true	#<Encoding:IBM857>
      IBM860	IBM860,CP860	false	true	#<Encoding:IBM860>
      IBM861	IBM861,CP861	false	true	#<Encoding:IBM861>
      IBM862	IBM862,CP862	false	true	#<Encoding:IBM862>
      IBM863	IBM863,CP863	false	true	#<Encoding:IBM863>
      IBM864	IBM864,CP864	false	true	#<Encoding:IBM864>
      IBM865	IBM865,CP865	false	true	#<Encoding:IBM865>
      IBM866	IBM866,CP866	false	true	#<Encoding:IBM866>
      IBM869	IBM869,CP869	false	true	#<Encoding:IBM869>
      Windows-1258	Windows-1258,CP1258	false	true	#<Encoding:Windows-1258>
      GB1988	GB1988	false	true	#<Encoding:GB1988>
      macCentEuro	macCentEuro	false	true	#<Encoding:macCentEuro>
      macCroatian	macCroatian	false	true	#<Encoding:macCroatian>
      macCyrillic	macCyrillic	false	true	#<Encoding:macCyrillic>
      macGreek	macGreek	false	true	#<Encoding:macGreek>
      macIceland	macIceland	false	true	#<Encoding:macIceland>
      macRoman	macRoman	false	true	#<Encoding:macRoman>
      macRomania	macRomania	false	true	#<Encoding:macRomania>
      macThai	macThai	false	true	#<Encoding:macThai>
      macTurkish	macTurkish	false	true	#<Encoding:macTurkish>
      macUkraine	macUkraine	false	true	#<Encoding:macUkraine>
      CP950	CP950	false	true	#<Encoding:CP950>
      CP951	CP951	false	true	#<Encoding:CP951>
      IBM037	IBM037,ebcdic-cp-us	true	false	#<Encoding:IBM037 (dummy)>
      stateless-ISO-2022-JP	stateless-ISO-2022-JP	false	true	#<Encoding:stateless-ISO-2022-JP>
      eucJP-ms	eucJP-ms,euc-jp-ms	false	true	#<Encoding:eucJP-ms>
      CP51932	CP51932	false	true	#<Encoding:CP51932>
      EUC-JIS-2004	EUC-JIS-2004,EUC-JISX0213	false	true	#<Encoding:EUC-JIS-2004>
      GB2312	GB2312,EUC-CN,eucCN	false	true	#<Encoding:GB2312>
      GB12345	GB12345	false	true	#<Encoding:GB12345>
      ISO-2022-JP	ISO-2022-JP,ISO2022-JP	true	false	#<Encoding:ISO-2022-JP (dummy)>
      ISO-2022-JP-2	ISO-2022-JP-2,ISO2022-JP2	true	false	#<Encoding:ISO-2022-JP-2 (dummy)>
      CP50220	CP50220	true	false	#<Encoding:CP50220 (dummy)>
      CP50221	CP50221	true	false	#<Encoding:CP50221 (dummy)>
      Windows-1256	Windows-1256,CP1256	false	true	#<Encoding:Windows-1256>
      Windows-1255	Windows-1255,CP1255	false	true	#<Encoding:Windows-1255>
      TIS-620	TIS-620	false	true	#<Encoding:TIS-620>
      Windows-874	Windows-874,CP874	false	true	#<Encoding:Windows-874>
      MacJapanese	MacJapanese,MacJapan	false	true	#<Encoding:MacJapanese>
      UTF-7	UTF-7,CP65000	true	false	#<Encoding:UTF-7 (dummy)>
      UTF8-DoCoMo	UTF8-DoCoMo	false	true	#<Encoding:UTF8-DoCoMo>
      SJIS-DoCoMo	SJIS-DoCoMo	false	true	#<Encoding:SJIS-DoCoMo>
      UTF8-KDDI	UTF8-KDDI	false	true	#<Encoding:UTF8-KDDI>
      SJIS-KDDI	SJIS-KDDI	false	true	#<Encoding:SJIS-KDDI>
      ISO-2022-JP-KDDI	ISO-2022-JP-KDDI	true	false	#<Encoding:ISO-2022-JP-KDDI (dummy)>
      stateless-ISO-2022-JP-KDDI	stateless-ISO-2022-JP-KDDI	false	true	#<Encoding:stateless-ISO-2022-JP-KDDI>
      UTF8-SoftBank	UTF8-SoftBank	false	true	#<Encoding:UTF8-SoftBank>
      SJIS-SoftBank	SJIS-SoftBank	false	true	#<Encoding:SJIS-SoftBank>
      name_list: 175
      aliases: 71
      constants: 211
      Windows_1250: #<Encoding:Windows-1250>
      WINDOWS_1250: #<Encoding:Windows-1250>
      EucJP: #<Encoding:EUC-JP>
      EUCJP: #<Encoding:EUC-JP>
      EBCDIC_CP_US: #<Encoding:IBM037 (dummy)>
      Big5_HKSCS_2008: #<Encoding:Big5-HKSCS>
      no 646 constant: false
      UNICODE_VERSION: "17.0.0"
      default_external names: ["UTF-8", "CP65001", "locale", "external", "filesystem"]
      internal in name_list: true
      aliases has internal: false
      find external: #<Encoding:UTF-8>
      find internal: nil
      find Latin-1: ArgumentError: unknown encoding name - Latin-1
      ISO-8859-5 cyrillic: "р"
      KOI8-U ghe: "ґ"
      IBM437 box: "█"
      CP866 be: "р"
      macRoman omega: "Ω"
      TIS-620 thai: "ก"
      Windows-874 thai: "ก"
      Windows-1258 dong: Encoding::ConverterNotFoundError: code converter not found (Windows-1258 to UTF-8)
      into ISO-8859-7: [225, 226]
      into IBM866: [128, 129]
      ISO-8859-3 unassigned: Encoding::UndefinedConversionError: "\xA5" from ISO-8859-3 to UTF-8
      ISO-8859-3 valid: true
      ISO-8859-3 length: 2
      ISO-8859-9 upcase: [73]
      EUC-KR ascii: [97, 98, 99]
      EUC-KR ascii back: "abc"
      EUC-KR compatible?: #<Encoding:UTF-8>
      EUC-KR names: ["EUC-KR", "eucKR"]
      EUC-KR dummy?: false
      EUC-KR ascii_compatible?: true
    OUT
  end

  it "regexp unicode property" do
    result = ze0(<<~'RUBY')
      # `\p{...}` character properties. The engine used to refuse every one of them
      # at compile time, so a program carrying one did not build at all -- and the
      # property IS the predicate, so nothing on the author's side can rewrite it
      # (#4143).
      #
      # Two tables behind this, generated from CRuby by tools/gen_re_uniprop.rb.
      # General category is a partition, so it is one run table answering `\p{Lu}`
      # and `\p{L}` alike; the emoji properties overlap, so they get a bitmask table.
      # The POSIX-named ones are the types re_ctype.h already carries and route
      # there, which is what makes them fold under /i.

      # The shape this arrived as: once-campfire's String#all_emoji?, verbatim.
      class String
        def all_emoji?
          self.match?(/\A(\p{Emoji_Presentation}|\p{Extended_Pictographic}|️)+\z/u)
        end
      end

      p "🔔".all_emoji?
      p "🔔🎉".all_emoji?
      p "hi".all_emoji?
      p "🔔x".all_emoji?

      # \p{Word}, which rails_autolink uses to trim trailing punctuation.
      p "see http://x.test/a." .sub(/[^\p{Word}\/]+\z/, "")
      p "abc_123".scan(/\p{Word}/).join

      s = "Aa1 _-€é́あ🔔"

      # Two-letter categories, and the one-letter form that stands for all of them.
      p s.scan(/\p{Lu}/)
      p s.scan(/\p{Ll}/).join
      p s.scan(/\p{L}/).join
      p s.scan(/\p{Nd}/)
      p s.scan(/\p{Pc}/) + s.scan(/\p{Pd}/)
      p s.scan(/\p{P}/)
      p s.scan(/\p{Sc}/)
      p s.scan(/\p{Zs}/)
      p s.scan(/\p{Mn}/).length

      # Negated, both spellings.
      p s.scan(/\P{L}/).length
      p s.scan(/[^\p{L}]/).length

      # Inside a class, mixed with literals and POSIX brackets.
      p s.scan(/[\p{Lu}\p{Nd}_]/)
      p s.scan(/[\p{Alpha}[:digit:]]/).join
      p s.scan(/[^\p{L}\p{N}]/).length
      p s.scan(/[\P{L}]/).length

      # The name is matched the way CRuby matches it: case, underscores, hyphens and
      # spaces are all the same name.
      p "é".match?(/\p{alpha}/)
      p "É".match?(/\p{Upper}/)
      p "🔔".match?(/\p{extended pictographic}/)
      p "🔔".match?(/\p{EXTENDED_PICTOGRAPHIC}/)
      p "🔔".match?(/\p{Extended-Pictographic}/)

      # A POSIX-named property folds under /i exactly as its bracket does; a
      # category does not, because the category IS the case distinction.
      p "É".match?(/\p{Lower}/i)
      p "É".match?(/[[:lower:]]/i)
      p "É".match?(/\p{Ll}/)

      # Quantified, anchored, alternated, and inside a group.
      p "Hello".match?(/\A\p{Lu}\p{Ll}+\z/)
      p "hello".match?(/\A\p{Lu}\p{Ll}+\z/)
      p "a1".match?(/\A(\p{L}|\p{N})+\z/)
      p "Wörld! 123".gsub(/\p{L}+/) { |w| w.upcase }
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      false
      "see http://x.test/a"
      "abc_123"
      ["A"]
      "aé"
      "Aaéあ"
      ["1"]
      ["_", "-"]
      ["_", "-"]
      ["€"]
      [" "]
      1
      7
      7
      ["A", "1", "_"]
      "Aa1éあ"
      6
      7
      true
      true
      true
      true
      true
      true
      true
      false
      true
      false
      true
      "WÖRLD! 123"
    OUT
  end

  it "single byte encodings validity length case and lookup" do
    result = ze0(<<~'RUBY')
      s = ("caf" + 0xE9.chr).force_encoding("Windows-1252")
      p s.valid_encoding?
      p s.length
      p s.upcase.bytes
      puts ("stra" + 0xDF.chr + "e").force_encoding("Windows-1252").upcase
      p 0x81.chr.force_encoding("Windows-1252").valid_encoding?
      p Encoding.find("cp1250")
      p Encoding::Windows_1251.name
      p Encoding::CP1252 == Encoding::Windows_1252
      koi = (0xC1.chr + "z").force_encoding("KOI8-R")
      p koi.upcase.bytes
      p 0xB1.chr.force_encoding("ISO-8859-2").upcase.bytes
      p 0xFF.chr.force_encoding("Windows-1252").upcase.bytes
    RUBY

    _(result).must_answer <<~'OUT'
      true
      4
      [67, 65, 70, 201]
      STRASSE
      true
      #<Encoding:Windows-1250>
      "Windows-1251"
      true
      [193, 90]
      [161]
      [159]
    OUT
  end

  it "string encoding ops" do
    result = ze0(<<~'RUBY')
      # String operations are CHARACTER-correct and ENCODING-preserving: a UTF-8
      # multibyte character counts as one, and a substring/reverse/upcase keeps the
      # receiver's encoding instead of silently becoming UTF-8.

      # --- UTF-8: multibyte characters count as one ------------------------------
      s = "café"
      p s.length          # 4   -- characters, not bytes
      p s.bytesize        # 5   -- é is two bytes
      p s[3]              # "é" -- indexed by CHARACTER
      p s[1, 2]           # "af"
      p s[1..]            # "afé"
      p s.reverse         # "éfac"  -- reversed by character
      p s.upcase          # "CAFÉ"  -- full Unicode casing
      p "Straße".upcase   # "STRASSE" -- ß expands to SS
      p "ÀÉÎ".downcase     # "àéî"
      p "résumé".center(10, "·")  # "··résumé··"

      # --- BINARY (ASCII-8BIT): every BYTE is a character ------------------------
      b = "café".b         # the UTF-8 bytes, retagged binary
      p b.length           # 5   -- bytes, not characters
      p b[3].bytes         # [195] -- one raw byte...
      p b[3].encoding      # #<Encoding:BINARY (ASCII-8BIT)>  -- ...still binary
      p b.reverse.bytes    # [169, 195, 102, 97, 99]  -- byte reversal
      p b.upcase.bytes     # [67, 65, 70, 195, 169]  -- only ASCII bytes fold

      # --- ISO-8859-1 (Latin-1): 1 byte per char, its OWN case map ---------------
      latin = "café".encode(Encoding::ISO_8859_1)   # é is one byte (0xE9)
      p latin.length            # 4
      p latin.upcase.bytes      # [67, 65, 70, 201]  -- é (0xE9) -> É (0xC9)
      p latin.upcase.encoding   # #<Encoding:ISO-8859-1>  -- encoding preserved
      p latin[3].bytes          # [233]

      # --- casing on the same accented text differs by encoding ------------------
      # UTF-8 knows é->É; a BINARY copy leaves the é bytes alone.
      p "é".upcase                 # "É"
      p "é".b.upcase.bytes         # [195, 169]  -- unchanged
    RUBY

    _(result).must_answer <<~'OUT'
      4
      5
      "é"
      "af"
      "afé"
      "éfac"
      "CAFÉ"
      "STRASSE"
      "àéî"
      "··résumé··"
      5
      [195]
      #<Encoding:BINARY (ASCII-8BIT)>
      [169, 195, 102, 97, 99]
      [67, 65, 70, 195, 169]
      4
      [67, 65, 70, 201]
      #<Encoding:ISO-8859-1>
      [233]
      "É"
      [195, 169]
    OUT
  end

  it "symbol case setbyte chr toc" do
    result = ze0(<<~'RUBY')
      # Symbol case conversions / succ preserve Symbol class through &:sym blocks
      # and variables; String#setbyte copy-on-write on value-semantics strings;
      # String#chr / #intern / #to_c.
      p([:hello, :world].map(&:upcase))
      p([:az].map(&:succ))
      p(:hello.upcase)
      s = :sym_in_var
      p s.upcase
      a = "hello"
      a.setbyte(0, 72)
      p a
      p a.getbyte(0)
      b = "abc"
      p b.chr
      p "x".intern
      p "42".to_c
      p "3+4i".to_c
      p "1.5-2i".to_c
      p "4i".to_c
    RUBY

    _(result).must_answer <<~'OUT'
      [:HELLO, :WORLD]
      [:ba]
      :HELLO
      :SYM_IN_VAR
      "Hello"
      72
      "a"
      :x
      (42+0i)
      (3+4i)
      (1.5-2i)
      (0+4i)
    OUT
  end

  it "unicode case latin1" do
    result = ze0(<<~'RUBY')
      # String case methods handle ASCII + Latin-1 Supplement + Latin Extended-A
      # (the common accented Latin ranges), not just ASCII a-z. ß upcases to SS.
      p "äöü".upcase
      p "ÄÖÜ".downcase
      p "aßet".upcase
      p "hello WORLD".swapcase
      p "ÀÉÎ".downcase
      p "àéî".upcase
      p "äöü".capitalize
      p "ĉĝĥ".upcase
      p "ĈĜĤ".downcase
      p "HELLO".downcase
      p "hello".upcase
      p "MixedÄcase".swapcase
    RUBY

    _(result).must_answer <<~'OUT'
      "ÄÖÜ"
      "äöü"
      "ASSET"
      "HELLO world"
      "àéî"
      "ÀÉÎ"
      "Äöü"
      "ĈĜĤ"
      "ĉĝĥ"
      "hello"
      "HELLO"
      "mIXEDäCASE"
    OUT
  end

  it "utf16 and utf32 wide encodings" do
    result = ze0(<<~'RUBY')
      # The wide Unicode rows (UTF-16LE/BE, UTF-32LE/BE): NOT ASCII-compatible
      # (never ascii_only, even empty; concatenation with anything else only
      # through an empty side), surrogate-pair walking, scalar-based chr/<<,
      # \uXXXX-escaped inspect. Verbatim ruby 4.0.6 output.

      u = "ab€".encode("UTF-16LE")
      p u.bytes
      p u.length
      p u.valid_encoding?
      p u
      p u.encode("UTF-8")
      p u.upcase.bytes
      p "a€𝄞".encode("UTF-32BE").bytes
      p "a€𝄞".encode("UTF-32BE").length
      p "a€𝄞".encode("UTF-16BE").encode("UTF-32LE").encode("UTF-8")
      p 65.chr(Encoding::UTF_16LE).bytes
      s = "".encode("UTF-16LE"); s << 0x20AC; p s.bytes
      p ("a".encode("UTF-16LE") + "").encoding
      begin; "a".encode("UTF-16LE") + "b"; rescue Encoding::CompatibilityError => e; puts e.message; end
      p ("".encode("UTF-16LE") + "abc").encoding
      p "abc".dup.force_encoding("UTF-16LE").ascii_only?
      p "a".dup.force_encoding("UTF-16LE").valid_encoding?
      bad = (0xD8.chr + 0x34.chr).force_encoding("UTF-16BE")
      p bad.valid_encoding?
      begin; bad.encode("UTF-8"); rescue Encoding::InvalidByteSequenceError => e; puts e.message; end
      p "AB𝄞".encode("UTF-16BE")
      p Encoding::UTF_16LE.ascii_compatible?
      p Encoding.find("UCS-2BE")
    RUBY

    _(result).must_answer <<~'OUT'
      [97, 0, 98, 0, 172, 32]
      3
      true
      "ab\u20AC"
      "ab€"
      [65, 0, 66, 0, 172, 32]
      [0, 0, 0, 97, 0, 0, 32, 172, 0, 1, 209, 30]
      3
      "a€𝄞"
      [65, 0]
      [172, 32]
      #<Encoding:UTF-16LE>
      incompatible character encodings: UTF-16LE and UTF-8
      #<Encoding:UTF-8>
      false
      false
      false
      incomplete "\xD84" on UTF-16BE
      "AB\u{1D11E}"
      false
      #<Encoding:UTF-16BE>
    OUT
  end

  it "utf8 by another name walks as utf8" do
    result = ze0(<<~'RUBY')
      # UTF8-MAC and the carriers' UTF-8 walk as UTF-8 walks: a character is
      # its code point, which inspect shows, and CESU-8, which is not among
      # them, shows its own the same way.
      %w[UTF8-MAC UTF8-DoCoMo UTF8-KDDI UTF8-SoftBank CESU-8].each do |name|
        s = "aé\u{E6A0}ÿ".b.force_encoding(name)
        p [name, s.length, s.chars.size, s.ord, s[1].ord, s.valid_encoding?, s.reverse.b, s.upcase.b, s.codepoints.size]
        p s, s[1], 0xE9.chr(name).b, s.dump, s.unpack("U*").size
        p s.center(8, "*").b, s =~ /é/u rescue p $!
        p "%s!" % s rescue p $!
        p s.scrub.b, s.inspect.encoding, s.each_grapheme_cluster.count
      end

    RUBY

    _(result).must_answer <<~'OUT'
      ["UTF8-MAC", 4, 4, 97, 233, true, "\xC3\xBF\xEE\x9A\xA0\xC3\xA9a", "A\xC3\x89\xEE\x9A\xA0\xC5\xB8", 4]
      "a\u00E9\uE6A0\u00FF"
      "\u00E9"
      "\xC3\xA9"
      "\"a\\xC3\\xA9\\xEE\\x9A\\xA0\\xC3\\xBF\""
      4
      #<Encoding::CompatibilityError: incompatible encoding regexp match (UTF-8 regexp with UTF8-MAC string)>
      "a\u00E9\uE6A0\u00FF!"
      "a\xC3\xA9\xEE\x9A\xA0\xC3\xBF"
      #<Encoding:UTF-8>
      4
      ["UTF8-DoCoMo", 4, 4, 97, 233, true, "\xC3\xBF\xEE\x9A\xA0\xC3\xA9a", "A\xC3\x89\xEE\x9A\xA0\xC5\xB8", 4]
      "a\u00E9\uE6A0\u00FF"
      "\u00E9"
      "\xC3\xA9"
      "\"a\\xC3\\xA9\\xEE\\x9A\\xA0\\xC3\\xBF\""
      4
      #<Encoding::CompatibilityError: incompatible encoding regexp match (UTF-8 regexp with UTF8-DoCoMo string)>
      "a\u00E9\uE6A0\u00FF!"
      "a\xC3\xA9\xEE\x9A\xA0\xC3\xBF"
      #<Encoding:UTF-8>
      4
      ["UTF8-KDDI", 4, 4, 97, 233, true, "\xC3\xBF\xEE\x9A\xA0\xC3\xA9a", "A\xC3\x89\xEE\x9A\xA0\xC5\xB8", 4]
      "a\u00E9\uE6A0\u00FF"
      "\u00E9"
      "\xC3\xA9"
      "\"a\\xC3\\xA9\\xEE\\x9A\\xA0\\xC3\\xBF\""
      4
      #<Encoding::CompatibilityError: incompatible encoding regexp match (UTF-8 regexp with UTF8-KDDI string)>
      "a\u00E9\uE6A0\u00FF!"
      "a\xC3\xA9\xEE\x9A\xA0\xC3\xBF"
      #<Encoding:UTF-8>
      4
      ["UTF8-SoftBank", 4, 4, 97, 233, true, "\xC3\xBF\xEE\x9A\xA0\xC3\xA9a", "A\xC3\x89\xEE\x9A\xA0\xC5\xB8", 4]
      "a\u00E9\uE6A0\u00FF"
      "\u00E9"
      "\xC3\xA9"
      "\"a\\xC3\\xA9\\xEE\\x9A\\xA0\\xC3\\xBF\""
      4
      #<Encoding::CompatibilityError: incompatible encoding regexp match (UTF-8 regexp with UTF8-SoftBank string)>
      "a\u00E9\uE6A0\u00FF!"
      "a\xC3\xA9\xEE\x9A\xA0\xC3\xBF"
      #<Encoding:UTF-8>
      4
      ["CESU-8", 4, 4, 97, 233, true, "\xC3\xBF\xEE\x9A\xA0\xC3\xA9a", "A\xC3\x89\xEE\x9A\xA0\xC5\xB8", 4]
      "a\u00E9\uE6A0\u00FF"
      "\u00E9"
      "\xC3\xA9"
      "\"a\\xC3\\xA9\\xEE\\x9A\\xA0\\xC3\\xBF\""
      4
      #<Encoding::CompatibilityError: incompatible encoding regexp match (UTF-8 regexp with CESU-8 string)>
      "a\u00E9\uE6A0\u00FF!"
      "a\xC3\xA9\xEE\x9A\xA0\xC3\xBF"
      #<Encoding:UTF-8>
      4
    OUT
  end
end
