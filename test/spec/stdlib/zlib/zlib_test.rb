# frozen_string_literal: true

require "spec_helper"

describe "Zlib programs" do
  it "const get dynamic" do
    result = zr(<<~'RUBY')
      # A class IS a constant of the scope it sits in, and reflection has to see it
      # under a name computed at run time -- an autoloader, `Marshal`, a YAML class
      # tag and a plain `Object.const_get(config_string)` all resolve that way.
      # zr registers a class by qualified name and never writes it to the constant
      # table (codegen resolves `Zlib::Error` statically), so both halves of
      # constant reflection have to consult the registry too.

      require "zlib"

      puts "-- const_get with a computed name"
      %w[Array String Comparable Float Struct Enumerator Math Zlib RUBY_VERSION].each do |n|
        begin
          puts "#{n} -> #{Object.const_get(n)}"
        rescue NameError
          puts "#{n} -> NameError"
        end
      end

      puts "-- nested, also computed"
      %w[Error GzipFile].each do |n|
        puts "Zlib::#{n} -> #{Zlib.const_get(n)}"
      end

      puts "-- const_defined? agrees with const_get"
      ["Array", "Zlib", "RUBY_VERSION", "Nope"].each do |n|
        found = Object.const_defined?(n)
        resolves = begin
          Object.const_get(n)
          true
        rescue NameError
          false
        end
        puts "#{n}: defined?=#{found} get=#{resolves}"
      end

      puts "-- a class sees a top-level constant through its ancestry"
      p String.const_get("Comparable")
      p Comparable.const_get("Array")
      p Object.const_get("Object")

      puts "-- and misses report the receiver"
      begin
        Object.const_get("Nope")
      rescue NameError => e
        puts e.message
      end
      begin
        Zlib.const_get("Nope")
      rescue NameError => e
        puts e.message
      end

      puts "-- listing"
      p Object.constants.include?(:Array)
      p Object.constants.include?(:Zlib)
      p Object.constants.include?(:RUBY_VERSION)
      p Object.constants.size > 100
      p Zlib.constants.include?(:Error)
      p Array.constants
      p String.constants

      module Holder
        INNER = 1
        class Nested; end
      end
      p Holder.constants.sort
      p Holder.const_get("Nested")
      p Holder.const_get("INNER")

      puts "-- Module.constants is the singleton form, not Module#constants"
      p Module.constants.include?(:Array)
      p Module.constants.include?(:RUBY_VERSION)
      p Module.constants.size > 100
    RUBY

    _(result).must_answer <<~'OUT'
      -- const_get with a computed name
      Array -> Array
      String -> String
      Comparable -> Comparable
      Float -> Float
      Struct -> Struct
      Enumerator -> Enumerator
      Math -> Math
      Zlib -> Zlib
      RUBY_VERSION -> 4.0.6
      -- nested, also computed
      Zlib::Error -> Zlib::Error
      Zlib::GzipFile -> Zlib::GzipFile
      -- const_defined? agrees with const_get
      Array: defined?=true get=true
      Zlib: defined?=true get=true
      RUBY_VERSION: defined?=true get=true
      Nope: defined?=false get=false
      -- a class sees a top-level constant through its ancestry
      Comparable
      Array
      Object
      -- and misses report the receiver
      uninitialized constant Nope
      uninitialized constant Zlib::Nope
      -- listing
      true
      true
      true
      true
      true
      []
      []
      [:INNER, :Nested]
      Holder::Nested
      1
      -- Module.constants is the singleton form, not Module#constants
      true
      true
      true
    OUT
  end

  it "deflate bytes match ruby at every level" do
    result = zr(<<~'RUBY')
      # Deflate writes the bytes ruby's zlib 1.3.1 writes, at every level.
      # The port in runtime/kernel/zlib_*.rb is held to them byte for byte: a
      # short stream is shown whole, a long one by its size and crc.
      require "zlib"

      def show(packed) = packed.bytesize <= 48 ? packed.unpack1("H*") : "#{packed.bytesize} bytes, crc #{Zlib.crc32(packed)}"

      seed = 12345
      noise = Array.new(4000) { seed = (seed * 1103515245 + 12345) & 0x7fffffff; (seed >> 16) & 0xff }.pack("C*")
      words = %w[alpha beta gamma delta epsilon zeta eta theta]
      prose = Array.new(3000) { |i| words[(i * 7 + i / 3) % words.size] }.join(" ")

      samples = {
        "empty" => "",
        "one" => "a",
        "run" => "z" * 5000,
        "prose" => prose,
        "noise" => noise,
        "mixed" => prose[0, 2000] + noise[0, 500] + prose[2000, 2000],
        "periodic" => ("abcdefghij" * 7000),
      }
      levels = [Zlib::DEFAULT_COMPRESSION, *0..9]
      samples.each do |name, text|
        levels.each do |level|
          packed = Zlib::Deflate.deflate(text, level)
          puts "#{name} level #{level}: #{show(packed)}"
          raise "#{name} at #{level} does not round trip" unless Zlib::Inflate.inflate(packed) == text
        end
      end
      puts "every stream round trips"

    RUBY

    _(result).must_answer <<~'OUT'
      empty level -1: 789c030000000001
      empty level 0: 7801010000ffff00000001
      empty level 1: 7801030000000001
      empty level 2: 785e030000000001
      empty level 3: 785e030000000001
      empty level 4: 785e030000000001
      empty level 5: 785e030000000001
      empty level 6: 789c030000000001
      empty level 7: 78da030000000001
      empty level 8: 78da030000000001
      empty level 9: 78da030000000001
      one level -1: 789c4b040000620062
      one level 0: 7801010100feff6100620062
      one level 1: 78014b040000620062
      one level 2: 785e4b040000620062
      one level 3: 785e4b040000620062
      one level 4: 785e4b040000620062
      one level 5: 785e4b040000620062
      one level 6: 789c4b040000620062
      one level 7: 78da4b040000620062
      one level 8: 78da4b040000620062
      one level 9: 78da4b040000620062
      run level -1: 789cedc13101000000c2a0de4b6f0a3fa00000000080b701b6314f58
      run level 0: 5011 bytes, crc 902434172
      run level 1: 7801edd03101000000c2a0de4b6f0a3f884061c0800103060c183060c0800103060c183060c0c07b60b6314f58
      run level 2: 785eedd03101000000c2a0de4b6f0a3f884061c0800103060c183060c0800103060c183060c0c07b60b6314f58
      run level 3: 785eedd03101000000c2a0de4b6f0a3f884061c0800103060c183060c0800103060c183060c0c07b60b6314f58
      run level 4: 785eedc13101000000c2a0de4b6f0a3fa00000000080b701b6314f58
      run level 5: 785eedc13101000000c2a0de4b6f0a3fa00000000080b701b6314f58
      run level 6: 789cedc13101000000c2a0de4b6f0a3fa00000000080b701b6314f58
      run level 7: 78daedc13101000000c2a0de4b6f0a3fa00000000080b701b6314f58
      run level 8: 78daedc13101000000c2a0de4b6f0a3fa00000000080b701b6314f58
      run level 9: 78daedc13101000000c2a0de4b6f0a3fa00000000080b701b6314f58
      prose level -1: 127 bytes, crc 3166210056
      prose level 0: 17510 bytes, crc 1092807311
      prose level 1: 236 bytes, crc 2285061536
      prose level 2: 219 bytes, crc 2937232005
      prose level 3: 218 bytes, crc 1903287824
      prose level 4: 128 bytes, crc 3292914279
      prose level 5: 127 bytes, crc 3849093338
      prose level 6: 127 bytes, crc 3166210056
      prose level 7: 127 bytes, crc 3604344911
      prose level 8: 127 bytes, crc 3604344911
      prose level 9: 127 bytes, crc 3604344911
      noise level -1: 4011 bytes, crc 1244356527
      noise level 0: 4011 bytes, crc 894912878
      noise level 1: 4011 bytes, crc 894912878
      noise level 2: 4011 bytes, crc 2820242766
      noise level 3: 4011 bytes, crc 2820242766
      noise level 4: 4011 bytes, crc 2820242766
      noise level 5: 4011 bytes, crc 2820242766
      noise level 6: 4011 bytes, crc 1244356527
      noise level 7: 4011 bytes, crc 2893588590
      noise level 8: 4011 bytes, crc 2893588590
      noise level 9: 4011 bytes, crc 2893588590
      mixed level -1: 618 bytes, crc 3662414968
      mixed level 0: 4511 bytes, crc 2987515650
      mixed level 1: 641 bytes, crc 1839858168
      mixed level 2: 631 bytes, crc 721330543
      mixed level 3: 631 bytes, crc 1158113330
      mixed level 4: 619 bytes, crc 898827454
      mixed level 5: 618 bytes, crc 3555747363
      mixed level 6: 618 bytes, crc 3662414968
      mixed level 7: 618 bytes, crc 4267710049
      mixed level 8: 616 bytes, crc 1649191813
      mixed level 9: 616 bytes, crc 1649191813
      periodic level -1: 170 bytes, crc 1038977632
      periodic level 0: 70016 bytes, crc 3859861027
      periodic level 1: 410 bytes, crc 3376183294
      periodic level 2: 410 bytes, crc 3605897491
      periodic level 3: 410 bytes, crc 3605897491
      periodic level 4: 170 bytes, crc 2272149627
      periodic level 5: 170 bytes, crc 2272149627
      periodic level 6: 170 bytes, crc 1038977632
      periodic level 7: 170 bytes, crc 4173852971
      periodic level 8: 170 bytes, crc 4173852971
      periodic level 9: 170 bytes, crc 4173852971
      every stream round trips
    OUT
  end

  it "deflate bytes match ruby at every strategy and window" do
    result = zr(<<~'RUBY')
      # Deflate's bytes at every strategy, window size, memory level and
      # wrapper: raw (negative window bits), zlib, and gzip (window bits 16+n,
      # whose header carries the OS byte of the platform: 19 on macOS).
      require "zlib"

      def show(packed) = packed.bytesize <= 48 ? packed.unpack1("H*") : "#{packed.bytesize} bytes, crc #{Zlib.crc32(packed)}"

      seed = 777
      noise = Array.new(2000) { seed = (seed * 1103515245 + 12345) & 0x7fffffff; (seed >> 16) & 0xff }.pack("C*")
      prose = Array.new(1500) { |i| "w#{(i * 13) % 97}" }.join(" ")
      text = prose + noise + prose + ("ab" * 3000)

      strategies = [Zlib::DEFAULT_STRATEGY, Zlib::FILTERED, Zlib::HUFFMAN_ONLY, Zlib::RLE, Zlib::FIXED]
      windows = [-15, -9, 8, 9, 12, 15, 31]
      [1, 6, 9].each do |level|
        strategies.each do |strategy|
          windows.each do |wbits|
            [1, 9].each do |mem|
              label = "level #{level} strategy #{strategy} wbits #{wbits} mem #{mem}"
              d = Zlib::Deflate.new(level, wbits, mem, strategy)
              packed = d.deflate(text, Zlib::FINISH)
              d.close
              puts "#{label}: #{show(packed)}"
              # Deflate widens a window of 8 bits to 9, so inflate gets the
              # widest window of the same wrapper.
              i = Zlib::Inflate.new(wbits.negative? ? -15 : wbits > 15 ? 31 : 15)
              raise "no round trip" unless i.inflate(packed) == text
              i.close
            end
          end
        end
      end
      # A 256-byte window only exists under the zlib wrapper.
      [-8, 24].each do |wbits|
        Zlib::Deflate.new(6, wbits)
      rescue Zlib::Error => e
        puts "wbits #{wbits}: #{e.class}: #{e.message}"
      end
      gz = Zlib::Deflate.new(6, 31).deflate("gzip header on record", Zlib::FINISH)
      puts "gzip: #{gz.unpack1("H*")}"
      puts "os byte: #{gz.getbyte(9)}"

    RUBY

    _(result).must_answer <<~'OUT'
      level 1 strategy 0 wbits -15 mem 1: 2712 bytes, crc 1847954696
      level 1 strategy 0 wbits -15 mem 9: 2556 bytes, crc 1267472279
      level 1 strategy 0 wbits -9 mem 1: 6870 bytes, crc 3274678750
      level 1 strategy 0 wbits -9 mem 9: 6866 bytes, crc 3731452108
      level 1 strategy 0 wbits 8 mem 1: 6876 bytes, crc 2940339392
      level 1 strategy 0 wbits 8 mem 9: 6872 bytes, crc 1417058302
      level 1 strategy 0 wbits 9 mem 1: 6876 bytes, crc 2940339392
      level 1 strategy 0 wbits 9 mem 9: 6872 bytes, crc 1417058302
      level 1 strategy 0 wbits 12 mem 1: 2722 bytes, crc 3389840975
      level 1 strategy 0 wbits 12 mem 9: 2817 bytes, crc 1662921092
      level 1 strategy 0 wbits 15 mem 1: 2718 bytes, crc 3231032299
      level 1 strategy 0 wbits 15 mem 9: 2562 bytes, crc 1154850646
      level 1 strategy 0 wbits 31 mem 1: 2730 bytes, crc 805816651
      level 1 strategy 0 wbits 31 mem 9: 2574 bytes, crc 3909905000
      level 1 strategy 1 wbits -15 mem 1: 2712 bytes, crc 1847954696
      level 1 strategy 1 wbits -15 mem 9: 2556 bytes, crc 1267472279
      level 1 strategy 1 wbits -9 mem 1: 6870 bytes, crc 3274678750
      level 1 strategy 1 wbits -9 mem 9: 6866 bytes, crc 3731452108
      level 1 strategy 1 wbits 8 mem 1: 6876 bytes, crc 2940339392
      level 1 strategy 1 wbits 8 mem 9: 6872 bytes, crc 1417058302
      level 1 strategy 1 wbits 9 mem 1: 6876 bytes, crc 2940339392
      level 1 strategy 1 wbits 9 mem 9: 6872 bytes, crc 1417058302
      level 1 strategy 1 wbits 12 mem 1: 2722 bytes, crc 3389840975
      level 1 strategy 1 wbits 12 mem 9: 2817 bytes, crc 1662921092
      level 1 strategy 1 wbits 15 mem 1: 2718 bytes, crc 3231032299
      level 1 strategy 1 wbits 15 mem 9: 2562 bytes, crc 1154850646
      level 1 strategy 1 wbits 31 mem 1: 2730 bytes, crc 805816651
      level 1 strategy 1 wbits 31 mem 9: 2574 bytes, crc 3909905000
      level 1 strategy 2 wbits -15 mem 1: 10219 bytes, crc 1974792658
      level 1 strategy 2 wbits -15 mem 9: 10582 bytes, crc 1912742102
      level 1 strategy 2 wbits -9 mem 1: 10219 bytes, crc 1974792658
      level 1 strategy 2 wbits -9 mem 9: 10582 bytes, crc 1912742102
      level 1 strategy 2 wbits 8 mem 1: 10225 bytes, crc 3847488650
      level 1 strategy 2 wbits 8 mem 9: 10588 bytes, crc 131492786
      level 1 strategy 2 wbits 9 mem 1: 10225 bytes, crc 3847488650
      level 1 strategy 2 wbits 9 mem 9: 10588 bytes, crc 131492786
      level 1 strategy 2 wbits 12 mem 1: 10225 bytes, crc 436949380
      level 1 strategy 2 wbits 12 mem 9: 10588 bytes, crc 1866595176
      level 1 strategy 2 wbits 15 mem 1: 10225 bytes, crc 4193165121
      level 1 strategy 2 wbits 15 mem 9: 10588 bytes, crc 4263278305
      level 1 strategy 2 wbits 31 mem 1: 10237 bytes, crc 944846172
      level 1 strategy 2 wbits 31 mem 9: 10600 bytes, crc 4213707727
      level 1 strategy 3 wbits -15 mem 1: 10219 bytes, crc 1974792658
      level 1 strategy 3 wbits -15 mem 9: 10582 bytes, crc 1912742102
      level 1 strategy 3 wbits -9 mem 1: 10219 bytes, crc 1974792658
      level 1 strategy 3 wbits -9 mem 9: 10582 bytes, crc 1912742102
      level 1 strategy 3 wbits 8 mem 1: 10225 bytes, crc 3847488650
      level 1 strategy 3 wbits 8 mem 9: 10588 bytes, crc 131492786
      level 1 strategy 3 wbits 9 mem 1: 10225 bytes, crc 3847488650
      level 1 strategy 3 wbits 9 mem 9: 10588 bytes, crc 131492786
      level 1 strategy 3 wbits 12 mem 1: 10225 bytes, crc 436949380
      level 1 strategy 3 wbits 12 mem 9: 10588 bytes, crc 1866595176
      level 1 strategy 3 wbits 15 mem 1: 10225 bytes, crc 4193165121
      level 1 strategy 3 wbits 15 mem 9: 10588 bytes, crc 4263278305
      level 1 strategy 3 wbits 31 mem 1: 10237 bytes, crc 944846172
      level 1 strategy 3 wbits 31 mem 9: 10600 bytes, crc 4213707727
      level 1 strategy 4 wbits -15 mem 1: 2964 bytes, crc 3084569670
      level 1 strategy 4 wbits -15 mem 9: 2663 bytes, crc 2146410827
      level 1 strategy 4 wbits -9 mem 1: 10730 bytes, crc 3471117370
      level 1 strategy 4 wbits -9 mem 9: 10655 bytes, crc 3652446700
      level 1 strategy 4 wbits 8 mem 1: 10736 bytes, crc 267512405
      level 1 strategy 4 wbits 8 mem 9: 10661 bytes, crc 2929037516
      level 1 strategy 4 wbits 9 mem 1: 10736 bytes, crc 267512405
      level 1 strategy 4 wbits 9 mem 9: 10661 bytes, crc 2929037516
      level 1 strategy 4 wbits 12 mem 1: 2986 bytes, crc 3076474677
      level 1 strategy 4 wbits 12 mem 9: 2995 bytes, crc 3725279931
      level 1 strategy 4 wbits 15 mem 1: 2970 bytes, crc 4270732541
      level 1 strategy 4 wbits 15 mem 9: 2669 bytes, crc 1728683188
      level 1 strategy 4 wbits 31 mem 1: 2982 bytes, crc 3999346979
      level 1 strategy 4 wbits 31 mem 9: 2681 bytes, crc 4252787663
      level 6 strategy 0 wbits -15 mem 1: 2412 bytes, crc 3162290945
      level 6 strategy 0 wbits -15 mem 9: 2436 bytes, crc 3823712697
      level 6 strategy 0 wbits -9 mem 1: 7005 bytes, crc 1572054784
      level 6 strategy 0 wbits -9 mem 9: 6867 bytes, crc 1693594839
      level 6 strategy 0 wbits 8 mem 1: 7011 bytes, crc 3535069334
      level 6 strategy 0 wbits 8 mem 9: 6873 bytes, crc 712328508
      level 6 strategy 0 wbits 9 mem 1: 7011 bytes, crc 3535069334
      level 6 strategy 0 wbits 9 mem 9: 6873 bytes, crc 712328508
      level 6 strategy 0 wbits 12 mem 1: 2418 bytes, crc 2600831458
      level 6 strategy 0 wbits 12 mem 9: 2442 bytes, crc 102994356
      level 6 strategy 0 wbits 15 mem 1: 2418 bytes, crc 1932650800
      level 6 strategy 0 wbits 15 mem 9: 2442 bytes, crc 3315109775
      level 6 strategy 0 wbits 31 mem 1: 2430 bytes, crc 1455489490
      level 6 strategy 0 wbits 31 mem 9: 2454 bytes, crc 972921515
      level 6 strategy 1 wbits -15 mem 1: 2417 bytes, crc 322252241
      level 6 strategy 1 wbits -15 mem 9: 2489 bytes, crc 803608194
      level 6 strategy 1 wbits -9 mem 1: 8477 bytes, crc 1716267212
      level 6 strategy 1 wbits -9 mem 9: 7675 bytes, crc 12547861
      level 6 strategy 1 wbits 8 mem 1: 8483 bytes, crc 3528209301
      level 6 strategy 1 wbits 8 mem 9: 7681 bytes, crc 3874424786
      level 6 strategy 1 wbits 9 mem 1: 8483 bytes, crc 3528209301
      level 6 strategy 1 wbits 9 mem 9: 7681 bytes, crc 3874424786
      level 6 strategy 1 wbits 12 mem 1: 2423 bytes, crc 4217658600
      level 6 strategy 1 wbits 12 mem 9: 2495 bytes, crc 1241535890
      level 6 strategy 1 wbits 15 mem 1: 2423 bytes, crc 2259858298
      level 6 strategy 1 wbits 15 mem 9: 2495 bytes, crc 428014277
      level 6 strategy 1 wbits 31 mem 1: 2435 bytes, crc 1005530792
      level 6 strategy 1 wbits 31 mem 9: 2507 bytes, crc 2011115699
      level 6 strategy 2 wbits -15 mem 1: 10219 bytes, crc 1974792658
      level 6 strategy 2 wbits -15 mem 9: 10582 bytes, crc 1912742102
      level 6 strategy 2 wbits -9 mem 1: 10219 bytes, crc 1974792658
      level 6 strategy 2 wbits -9 mem 9: 10582 bytes, crc 1912742102
      level 6 strategy 2 wbits 8 mem 1: 10225 bytes, crc 3847488650
      level 6 strategy 2 wbits 8 mem 9: 10588 bytes, crc 131492786
      level 6 strategy 2 wbits 9 mem 1: 10225 bytes, crc 3847488650
      level 6 strategy 2 wbits 9 mem 9: 10588 bytes, crc 131492786
      level 6 strategy 2 wbits 12 mem 1: 10225 bytes, crc 436949380
      level 6 strategy 2 wbits 12 mem 9: 10588 bytes, crc 1866595176
      level 6 strategy 2 wbits 15 mem 1: 10225 bytes, crc 4193165121
      level 6 strategy 2 wbits 15 mem 9: 10588 bytes, crc 4263278305
      level 6 strategy 2 wbits 31 mem 1: 10237 bytes, crc 944846172
      level 6 strategy 2 wbits 31 mem 9: 10600 bytes, crc 4213707727
      level 6 strategy 3 wbits -15 mem 1: 10219 bytes, crc 1974792658
      level 6 strategy 3 wbits -15 mem 9: 10582 bytes, crc 1912742102
      level 6 strategy 3 wbits -9 mem 1: 10219 bytes, crc 1974792658
      level 6 strategy 3 wbits -9 mem 9: 10582 bytes, crc 1912742102
      level 6 strategy 3 wbits 8 mem 1: 10225 bytes, crc 3847488650
      level 6 strategy 3 wbits 8 mem 9: 10588 bytes, crc 131492786
      level 6 strategy 3 wbits 9 mem 1: 10225 bytes, crc 3847488650
      level 6 strategy 3 wbits 9 mem 9: 10588 bytes, crc 131492786
      level 6 strategy 3 wbits 12 mem 1: 10225 bytes, crc 436949380
      level 6 strategy 3 wbits 12 mem 9: 10588 bytes, crc 1866595176
      level 6 strategy 3 wbits 15 mem 1: 10225 bytes, crc 4193165121
      level 6 strategy 3 wbits 15 mem 9: 10588 bytes, crc 4263278305
      level 6 strategy 3 wbits 31 mem 1: 10237 bytes, crc 944846172
      level 6 strategy 3 wbits 31 mem 9: 10600 bytes, crc 4213707727
      level 6 strategy 4 wbits -15 mem 1: 2520 bytes, crc 2118506536
      level 6 strategy 4 wbits -15 mem 9: 2548 bytes, crc 1945406504
      level 6 strategy 4 wbits -9 mem 1: 10527 bytes, crc 173622269
      level 6 strategy 4 wbits -9 mem 9: 10505 bytes, crc 2900761984
      level 6 strategy 4 wbits 8 mem 1: 10533 bytes, crc 2179258935
      level 6 strategy 4 wbits 8 mem 9: 10511 bytes, crc 2981614539
      level 6 strategy 4 wbits 9 mem 1: 10533 bytes, crc 2179258935
      level 6 strategy 4 wbits 9 mem 9: 10511 bytes, crc 2981614539
      level 6 strategy 4 wbits 12 mem 1: 2526 bytes, crc 3421586112
      level 6 strategy 4 wbits 12 mem 9: 2554 bytes, crc 2894537480
      level 6 strategy 4 wbits 15 mem 1: 2526 bytes, crc 1457830031
      level 6 strategy 4 wbits 15 mem 9: 2554 bytes, crc 3910643156
      level 6 strategy 4 wbits 31 mem 1: 2538 bytes, crc 2913103464
      level 6 strategy 4 wbits 31 mem 9: 2566 bytes, crc 98463435
      level 9 strategy 0 wbits -15 mem 1: 2410 bytes, crc 848227064
      level 9 strategy 0 wbits -15 mem 9: 2434 bytes, crc 1652017149
      level 9 strategy 0 wbits -9 mem 1: 7005 bytes, crc 1572054784
      level 9 strategy 0 wbits -9 mem 9: 6867 bytes, crc 1693594839
      level 9 strategy 0 wbits 8 mem 1: 7011 bytes, crc 518094144
      level 9 strategy 0 wbits 8 mem 9: 6873 bytes, crc 319085848
      level 9 strategy 0 wbits 9 mem 1: 7011 bytes, crc 518094144
      level 9 strategy 0 wbits 9 mem 9: 6873 bytes, crc 319085848
      level 9 strategy 0 wbits 12 mem 1: 2416 bytes, crc 4235211978
      level 9 strategy 0 wbits 12 mem 9: 2440 bytes, crc 2237001895
      level 9 strategy 0 wbits 15 mem 1: 2416 bytes, crc 1722769843
      level 9 strategy 0 wbits 15 mem 9: 2440 bytes, crc 2787422650
      level 9 strategy 0 wbits 31 mem 1: 2428 bytes, crc 790079629
      level 9 strategy 0 wbits 31 mem 9: 2452 bytes, crc 3099230708
      level 9 strategy 1 wbits -15 mem 1: 2417 bytes, crc 105638343
      level 9 strategy 1 wbits -15 mem 9: 2487 bytes, crc 4274477037
      level 9 strategy 1 wbits -9 mem 1: 8477 bytes, crc 1716267212
      level 9 strategy 1 wbits -9 mem 9: 7675 bytes, crc 12547861
      level 9 strategy 1 wbits 8 mem 1: 8483 bytes, crc 2126465264
      level 9 strategy 1 wbits 8 mem 9: 7681 bytes, crc 3293630365
      level 9 strategy 1 wbits 9 mem 1: 8483 bytes, crc 2126465264
      level 9 strategy 1 wbits 9 mem 9: 7681 bytes, crc 3293630365
      level 9 strategy 1 wbits 12 mem 1: 2423 bytes, crc 441176830
      level 9 strategy 1 wbits 12 mem 9: 2493 bytes, crc 784213001
      level 9 strategy 1 wbits 15 mem 1: 2423 bytes, crc 3869259530
      level 9 strategy 1 wbits 15 mem 9: 2493 bytes, crc 3635674192
      level 9 strategy 1 wbits 31 mem 1: 2435 bytes, crc 1035531919
      level 9 strategy 1 wbits 31 mem 9: 2505 bytes, crc 865145861
      level 9 strategy 2 wbits -15 mem 1: 10219 bytes, crc 1974792658
      level 9 strategy 2 wbits -15 mem 9: 10582 bytes, crc 1912742102
      level 9 strategy 2 wbits -9 mem 1: 10219 bytes, crc 1974792658
      level 9 strategy 2 wbits -9 mem 9: 10582 bytes, crc 1912742102
      level 9 strategy 2 wbits 8 mem 1: 10225 bytes, crc 3847488650
      level 9 strategy 2 wbits 8 mem 9: 10588 bytes, crc 131492786
      level 9 strategy 2 wbits 9 mem 1: 10225 bytes, crc 3847488650
      level 9 strategy 2 wbits 9 mem 9: 10588 bytes, crc 131492786
      level 9 strategy 2 wbits 12 mem 1: 10225 bytes, crc 436949380
      level 9 strategy 2 wbits 12 mem 9: 10588 bytes, crc 1866595176
      level 9 strategy 2 wbits 15 mem 1: 10225 bytes, crc 4193165121
      level 9 strategy 2 wbits 15 mem 9: 10588 bytes, crc 4263278305
      level 9 strategy 2 wbits 31 mem 1: 10237 bytes, crc 1259773959
      level 9 strategy 2 wbits 31 mem 9: 10600 bytes, crc 459255376
      level 9 strategy 3 wbits -15 mem 1: 10219 bytes, crc 1974792658
      level 9 strategy 3 wbits -15 mem 9: 10582 bytes, crc 1912742102
      level 9 strategy 3 wbits -9 mem 1: 10219 bytes, crc 1974792658
      level 9 strategy 3 wbits -9 mem 9: 10582 bytes, crc 1912742102
      level 9 strategy 3 wbits 8 mem 1: 10225 bytes, crc 3847488650
      level 9 strategy 3 wbits 8 mem 9: 10588 bytes, crc 131492786
      level 9 strategy 3 wbits 9 mem 1: 10225 bytes, crc 3847488650
      level 9 strategy 3 wbits 9 mem 9: 10588 bytes, crc 131492786
      level 9 strategy 3 wbits 12 mem 1: 10225 bytes, crc 436949380
      level 9 strategy 3 wbits 12 mem 9: 10588 bytes, crc 1866595176
      level 9 strategy 3 wbits 15 mem 1: 10225 bytes, crc 4193165121
      level 9 strategy 3 wbits 15 mem 9: 10588 bytes, crc 4263278305
      level 9 strategy 3 wbits 31 mem 1: 10237 bytes, crc 1259773959
      level 9 strategy 3 wbits 31 mem 9: 10600 bytes, crc 459255376
      level 9 strategy 4 wbits -15 mem 1: 2520 bytes, crc 2112194872
      level 9 strategy 4 wbits -15 mem 9: 2548 bytes, crc 1957965320
      level 9 strategy 4 wbits -9 mem 1: 10527 bytes, crc 173622269
      level 9 strategy 4 wbits -9 mem 9: 10505 bytes, crc 2900761984
      level 9 strategy 4 wbits 8 mem 1: 10533 bytes, crc 2179258935
      level 9 strategy 4 wbits 8 mem 9: 10511 bytes, crc 2981614539
      level 9 strategy 4 wbits 9 mem 1: 10533 bytes, crc 2179258935
      level 9 strategy 4 wbits 9 mem 9: 10511 bytes, crc 2981614539
      level 9 strategy 4 wbits 12 mem 1: 2526 bytes, crc 3248012427
      level 9 strategy 4 wbits 12 mem 9: 2554 bytes, crc 3092570014
      level 9 strategy 4 wbits 15 mem 1: 2526 bytes, crc 1552762564
      level 9 strategy 4 wbits 15 mem 9: 2554 bytes, crc 4257501506
      level 9 strategy 4 wbits 31 mem 1: 2538 bytes, crc 3417833121
      level 9 strategy 4 wbits 31 mem 9: 2566 bytes, crc 2386133671
      wbits -8: Zlib::StreamError: stream error
      wbits 24: Zlib::StreamError: stream error
      gzip: 1f8b08000000000000134bafca2c50c8484d4c492d52c8cf53284a4dce2f4a0100304e789f15000000
      os byte: 19
    OUT
  end

  it "deflate dictionary and copy" do
    result = zr(<<~'RUBY')
      # A preset dictionary, the stream copy, and inflate's need for the same
      # dictionary: NeedDict, then the data after set_dictionary.
      require "zlib"

      def hex(bytes) = bytes.empty? ? "-" : bytes.unpack1("H*")

      dict = "the quick brown fox jumps over the lazy dog "
      text = "the lazy dog sleeps while the quick brown fox jumps and jumps"

      d = Zlib::Deflate.new(6)
      d.set_dictionary(dict)
      packed = d.deflate(text, Zlib::FINISH)
      puts "with dictionary: #{hex(packed)}"
      puts "dictionary adler: #{packed[2, 4].unpack1("N")} = #{Zlib.adler32(dict)}"
      d.close

      i = Zlib::Inflate.new
      begin
        i.inflate(packed)
      rescue Zlib::NeedDict => e
        puts "#{e.class}: #{e.message}"
      end
      i.set_dictionary(dict)
      puts "then: #{i.inflate("")}"
      puts "finished: #{i.finished?}"
      i.close

      i = Zlib::Inflate.new
      begin
        i.inflate(packed)
      rescue Zlib::NeedDict
        begin
          i.set_dictionary("a different dictionary")
        rescue Zlib::Error => e
          puts "wrong dictionary: #{e.class}: #{e.message}"
        end
      end
      i.close

      raw = Zlib::Deflate.new(6, -15)
      raw.set_dictionary(dict)
      rawbytes = raw.deflate(text, Zlib::FINISH)
      raw.close
      puts "raw with dictionary: #{hex(rawbytes)}"
      ri = Zlib::Inflate.new(-15)
      ri.set_dictionary(dict)
      puts "raw inflated: #{ri.inflate(rawbytes)}"
      ri.close

      gz = Zlib::Deflate.new(6, 31)
      begin
        gz.set_dictionary(dict)
      rescue Zlib::Error => e
        puts "gzip refuses: #{e.class}: #{e.message}"
      end
      gz.close

      first = "copied streams share their state so far; "
      rest_a = "then they part: A"
      rest_b = "then they part: B and it is longer"
      d = Zlib::Deflate.new(9)
      head = d.deflate(first)
      copy = d.dup
      a = head + d.deflate(rest_a, Zlib::FINISH)
      b = head + copy.deflate(rest_b, Zlib::FINISH)
      d.close
      copy.close
      puts "copy a: #{hex(a)}"
      puts "copy b: #{hex(b)}"
      puts "a reads: #{Zlib::Inflate.inflate(a)}"
      puts "b reads: #{Zlib::Inflate.inflate(b)}"

    RUBY

    _(result).must_answer <<~'OUT'
      with dictionary: 78bb7156101a43e114e7a4a60255956764e6a48265b09b92989702610100b9d216a5
      dictionary adler: 1901465626 = 1901465626
      Zlib::NeedDict: need dictionary
      then: the lazy dog sleeps while the quick brown fox jumps and jumps
      finished: true
      wrong dictionary: Zlib::DataError: data error
      raw with dictionary: 43e114e7a4a60255956764e6a48265b09b92989702610100
      raw inflated: the lazy dog sleeps while the quick brown fox jumps and jumps
      gzip refuses: Zlib::StreamError: stream error
      copy a: 78da4bce2fc84c4d51282e294a4dcc2d5628ce482c4a5528c948cd2c028a2596a42a14e72ba425165983c4f24044a54241625189958223007f7c14f5
      copy b: 78da15c8b10d80300c04c0557e0ee8d8c4221f6209ecc876c3f690e68a3b7d2a1bb282f22472481035a8f19f14918e2eb1afb3c58b29511b0e8835684113b7dbc5f80015d81ae9
      a reads: copied streams share their state so far; then they part: A
      b reads: copied streams share their state so far; then they part: B and it is longer
    OUT
  end

  it "deflate flush modes and chunks" do
    result = zr(<<~'RUBY')
      # The bytes each flush mode writes at each step of a stream, and that
      # the way input is cut into calls does not change them.
      require "zlib"

      def hex(bytes) = bytes.empty? ? "-" : bytes.unpack1("H*")

      parts = ["the first part, ", "a second part that repeats the first part, ", "and the last part."]
      modes = {
        "NO_FLUSH" => Zlib::NO_FLUSH,
        "SYNC_FLUSH" => Zlib::SYNC_FLUSH,
        "FULL_FLUSH" => Zlib::FULL_FLUSH,
      }
      modes.each do |name, mode|
        d = Zlib::Deflate.new(6)
        parts.each_with_index do |part, n|
          puts "#{name} step #{n}: #{hex(d.deflate(part, mode))}"
        end
        puts "#{name} finish: #{hex(d.finish)}"
        d.close
      end

      d = Zlib::Deflate.new(9)
      puts "flush(SYNC) on nothing: #{hex(d.flush(Zlib::SYNC_FLUSH))}"
      d << "streamed with << "
      puts "flush(SYNC): #{hex(d.flush(Zlib::SYNC_FLUSH))}"
      puts "flush(FULL) on nothing: #{hex(d.flush(Zlib::FULL_FLUSH))}"
      d << "and more"
      puts "flush(FINISH): #{hex(d.flush(Zlib::FINISH))}"
      d.close

      text = ("chunking " * 3000) + ("x" * 70000) + ("chunking " * 100)
      whole = Zlib::Deflate.deflate(text, 6)
      [1, 7, 100, 4096, 65535, 65536].each do |size|
        d = Zlib::Deflate.new(6)
        out = +""
        text.bytes.each_slice(size) { |slice| out << d.deflate(slice.pack("C*")) }
        out << d.finish
        d.close
        puts "chunks of #{size}: #{out == whole ? "the same bytes" : "different bytes"}"
      end
      puts "whole: #{whole.bytesize} bytes, crc #{Zlib.crc32(whole)}"

    RUBY

    _(result).must_answer <<~'OUT'
      NO_FLUSH step 0: 789c
      NO_FLUSH step 1: -
      NO_FLUSH step 2: -
      NO_FLUSH finish: 2bc9485548cb2c2a2e5128482c2ad1514854284e4dcecf4b0173154a32124b148a520b52134b8a811c34a5405520b19c44a8901e003bbb1b9f
      SYNC_FLUSH step 0: 789c2ac9485548cb2c2a2e5128482c2ad15100000000ffff
      SYNC_FLUSH step 1: 4a54284e4dcecf4b0173154a32124b148a520b52134b8a811c54a500000000ffff
      SYNC_FLUSH step 2: 4a04aa0289e5244285f400000000ffff
      SYNC_FLUSH finish: 03003bbb1b9f
      FULL_FLUSH step 0: 789c2ac9485548cb2c2a2e5128482c2ad15100000000ffff
      FULL_FLUSH step 1: 4a54284e4dcecf4b5128482c2a5128c9482c51284a2d484d2c2906725215d2328b8a4bc0723a0a00000000ffff
      FULL_FLUSH step 2: 4acc4b5128c94855c8492c2e5128482c2ad103000000ffff
      FULL_FLUSH finish: 03003bbb1b9f
      flush(SYNC) on nothing: 78da000000ffff
      flush(SYNC): 2a2e294a4dcc4d4d5128cf2cc950b0b15100000000ffff
      flush(FULL) on nothing: 000000ffff
      flush(FINISH): 4bcc4b51c8cd2f4a0500784f08f0
      chunks of 1: the same bytes
      chunks of 7: the same bytes
      chunks of 100: the same bytes
      chunks of 4096: the same bytes
      chunks of 65535: the same bytes
      chunks of 65536: the same bytes
      whole: 167 bytes, crc 973924618
    OUT
  end

  it "deflate params mid stream" do
    result = zr(<<~'RUBY')
      # deflateParams between appends: what the old parameters compressed is
      # flushed, the new ones compress the rest, and the bytes are ruby's.
      # (`<<` keeps the output buffer; ruby's params after `deflate` reads a
      # buffer it gave away, so the row does not do that.)
      require "zlib"

      def hex(bytes) = bytes.empty? ? "-" : bytes.unpack1("H*")

      text = Array.new(400) { |i| "line #{i % 17} of the text\n" }.join

      changes = [
        [1, Zlib::DEFAULT_STRATEGY],
        [9, Zlib::DEFAULT_STRATEGY],
        [6, Zlib::HUFFMAN_ONLY],
        [6, Zlib::RLE],
        [0, Zlib::DEFAULT_STRATEGY],
        [5, Zlib::FIXED],
        [3, Zlib::FILTERED],
      ]
      changes.each do |level, strategy|
        d = Zlib::Deflate.new(6)
        d << text[0, 1500]
        d.params(level, strategy)
        d << text[1500..]
        out = d.finish
        d.close
        puts "to #{level}/#{strategy}: #{out.bytesize} bytes, crc #{Zlib.crc32(out)}"
        raise "no round trip" unless Zlib::Inflate.inflate(out) == text
      end

      d = Zlib::Deflate.new(1)
      d << "a few bytes"
      d.params(9, Zlib::DEFAULT_STRATEGY)
      d << " and a few more bytes, a few more bytes"
      puts "short: #{hex(d.finish)}"
      d.close

      d = Zlib::Deflate.new(9)
      d << text
      d.params(1, Zlib::DEFAULT_STRATEGY)
      d.params(9, Zlib::DEFAULT_STRATEGY)
      d << text
      out = d.finish
      d.close
      puts "two changes: #{out.bytesize} bytes, crc #{Zlib.crc32(out)}"

      d = Zlib::Deflate.new(6)
      d << "same"
      d.params(6, Zlib::DEFAULT_STRATEGY)
      d << " params again"
      puts "same params again: #{hex(d.finish)}"
      d.close

      d = Zlib::Deflate.new(6)
      d << "x" * 3000
      d.params(0, Zlib::DEFAULT_STRATEGY)
      d << "y" * 3000
      d.params(6, Zlib::DEFAULT_STRATEGY)
      d << "z" * 3000
      out = d.finish
      d.close
      puts "through stored: #{out.bytesize} bytes, crc #{Zlib.crc32(out)}"
      puts "reads back: #{Zlib::Inflate.inflate(out) == "x" * 3000 + "y" * 3000 + "z" * 3000}"

    RUBY

    _(result).must_answer <<~'OUT'
      to 1/0: 199 bytes, crc 2061360847
      to 9/0: 123 bytes, crc 255903217
      to 6/2: 2938 bytes, crc 2975596962
      to 6/3: 2938 bytes, crc 2975596962
      to 0/0: 6358 bytes, crc 3179955064
      to 5/4: 157 bytes, crc 2621264724
      to 3/1: 155 bytes, crc 2081641720
      short: 78014a54484b2d5748aa2c492d064c21312f452111cccfcd2f4a8508ea60880000b72e1184
      two changes: 174 bytes, crc 3765246196
      same params again: 789c2b4ecc4d5528482c4acc2d56484c4fcccc030039c6066b
      through stored: 3050 bytes, crc 3422892248
      reads back: true
    OUT
  end

  it "deflate reset and reuse" do
    result = zr(<<~'RUBY')
      # reset takes a stream back to its start: the same bytes come out again,
      # the totals start over, and a finished stream can be reused.
      require "zlib"

      def hex(bytes) = bytes.empty? ? "-" : bytes.unpack1("H*")

      text = "reset me, reset me, reset me again"
      d = Zlib::Deflate.new(6)
      one = d.deflate(text, Zlib::FINISH)
      puts "one: #{hex(one)}"
      puts "totals: #{d.total_in} in, #{d.total_out} out, finished #{d.finished?}"
      d.reset
      puts "after reset: #{d.total_in} in, #{d.total_out} out, finished #{d.finished?}"
      two = d.deflate(text, Zlib::FINISH)
      puts "two: #{hex(two)}"
      puts "same: #{one == two}"

      d.reset
      d << text[0, 10]
      d.reset
      three = d.deflate(text, Zlib::FINISH)
      puts "reset mid-stream: #{one == three}"
      puts "adler: #{d.adler} = #{Zlib.adler32(text)}"
      d.close

      i = Zlib::Inflate.new
      puts "inflate: #{i.inflate(one)}"
      puts "totals: #{i.total_in} in, #{i.total_out} out, finished #{i.finished?}"
      i.reset
      puts "after reset: #{i.total_in} in, #{i.total_out} out, finished #{i.finished?}"
      puts "inflate again: #{i.inflate(two)}"
      i.reset
      half = i.inflate(one[0, 8])
      i.reset
      puts "half then reset then whole: #{half.inspect} #{i.inflate(one).inspect}"
      i.close

      begin
        i.inflate(one)
      rescue Zlib::Error => e
        puts "closed: #{e.class}: #{e.message}"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      one: 789c2b4a2d4e2d51c84dd55128c2602924a62766e60100d2350bf8
      totals: 34 in, 27 out, finished true
      after reset: 0 in, 0 out, finished false
      two: 789c2b4a2d4e2d51c84dd55128c2602924a62766e60100d2350bf8
      same: true
      reset mid-stream: true
      adler: 3526691832 = 3526691832
      inflate: reset me, reset me, reset me again
      totals: 27 in, 34 out, finished true
      after reset: 0 in, 0 out, finished false
      inflate again: reset me, reset me, reset me again
      half then reset then whole: "reset" "reset me, reset me, reset me again"
      closed: Zlib::Error: stream is not ready
    OUT
  end

  it "gzip reader writer edge cases" do
    result = zr(<<~'RUBY')
      # The gzip container's edge surface: line-reading modes, limits, buffers,
      # unget, multi-member streams, and the exact error classes with their
      # `input` payloads. Every row is deterministic -- no timestamps, no
      # compressed bytes printed, only decoded data and error shapes.
      require "zlib"
      require "stringio"

      def show(label)
        print "#{label}: "
        p(yield)
      rescue => e
        puts "#{e.class}: #{e.message}"
      end

      MB = Zlib.gzip("héllo\nwörld\n")
      PARA = Zlib.gzip("aaa\n\n\n\nbbb\nccc\n\nddd")

      # -- gets: separators, paragraph mode, limits -------------------------------

      show("paragraph gets") do
        r = Zlib::GzipReader.new(StringIO.new(PARA))
        [r.gets(""), r.gets(""), r.gets(""), r.gets("")]
      end
      show("gets limit never splits a character") do
        r = Zlib::GzipReader.new(StringIO.new(MB))
        [r.gets(2), r.gets(1), r.gets]
      end
      show("gets limit 0") { Zlib::GzipReader.new(StringIO.new(MB)).gets(0) }
      show("gets sep and limit") { Zlib::GzipReader.new(StringIO.new(Zlib.gzip("axbxc"))).gets("x", 10) }
      show("gets rejects a hash") { Zlib::GzipReader.new(StringIO.new(MB)).gets(chomp: true) }
      show("gets encoding") { Zlib::GzipReader.new(StringIO.new(MB)).gets.encoding.to_s }
      show("gets at eof keeps lineno") do
        r = Zlib::GzipReader.new(StringIO.new(MB))
        r.read
        [r.gets, r.lineno]
      end
      show("readlines with a separator") { Zlib::GzipReader.new(StringIO.new(Zlib.gzip("axbxc"))).readlines("x") }
      show("readlines with a limit") { Zlib::GzipReader.new(StringIO.new(MB)).readlines(4) }
      # The blockless enumerator drops the arguments; the block form honours them.
      show("blockless each_line drops its arguments") { Zlib::GzipReader.new(StringIO.new(MB)).each_line(3).to_a }
      show("each_line block honours the limit") do
        lines = []
        Zlib::GzipReader.new(StringIO.new(MB)).each_line(3) { |l| lines << l }
        lines
      end
      show("lineno=") do
        r = Zlib::GzipReader.new(StringIO.new(MB))
        r.lineno = 5
        r.gets
        r.lineno
      end

      # -- read: buffers, lengths -------------------------------------------------

      show("read into a buffer keeps its encoding") do
        buf = +"seed"
        r = Zlib::GzipReader.new(StringIO.new(MB))
        got = r.read(3, buf)
        [got.equal?(buf), buf, buf.encoding.to_s]
      end
      show("whole-member read ignores the buffer") do
        buf = +"seed"
        r = Zlib::GzipReader.new(StringIO.new(MB))
        got = r.read(nil, buf)
        [got.equal?(buf), buf]
      end
      show("readpartial into a buffer") do
        buf = +"s"
        Zlib::GzipReader.new(StringIO.new(MB)).readpartial(4, buf)
        [buf, buf.encoding.to_s]
      end
      show("negative read") { Zlib::GzipReader.new(StringIO.new(MB)).read(-1) }
      show("empty member") do
        r = Zlib::GzipReader.new(StringIO.new(Zlib.gzip("")))
        [r.eof?, r.read, r.read(3)]
      end
      show("getc completes a multibyte character") do
        r = Zlib::GzipReader.new(StringIO.new(MB))
        [r.getc, r.getc]
      end

      # -- unget and pos ----------------------------------------------------------

      show("pos follows ungetc backwards") do
        r = Zlib::GzipReader.new(StringIO.new(MB))
        a = r.read(3)
        p1 = r.pos
        r.ungetc("x")
        p2 = r.pos
        [a, p1, p2, r.read(2), r.pos]
      end
      show("ungetc accepts a codepoint") do
        r = Zlib::GzipReader.new(StringIO.new(MB))
        r.ungetc(65)
        r.read(3)
      end
      show("ungetbyte takes one byte of a string") do
        r = Zlib::GzipReader.new(StringIO.new(MB))
        r.ungetbyte("AB")
        r.read(4)
      end
      show("ungetbyte wraps an integer") do
        r = Zlib::GzipReader.new(StringIO.new(MB))
        r.ungetbyte(300)
        r.read(2)
      end

      # -- zcat -------------------------------------------------------------------

      show("zcat with a block yields each member") do
        members = []
        answer = Zlib::GzipReader.zcat(StringIO.new(Zlib.gzip("one") + Zlib.gzip("two"))) { |d| members << d }
        [members, answer]
      end
      show("zcat result encoding") { Zlib::GzipReader.zcat(StringIO.new(Zlib.gzip("x"))).encoding.to_s }
      show("zcat refuses trailing garbage") { Zlib::GzipReader.zcat(StringIO.new(Zlib.gzip("one") + "junk")) }

      # -- the error shapes -------------------------------------------------------

      show("a header-phase error carries the input") do
        Zlib::GzipReader.new(StringIO.new("junkdata"))
      rescue Zlib::GzipFile::Error => e
        [e.message, e.input]
      end
      show("an EOF inside the ten header bytes is not gzip") do
        Zlib::GzipReader.new(StringIO.new("\x1f\x8b\x08"))
      rescue Zlib::GzipFile::Error => e
        [e.message, e.input]
      end
      show("an EOF past them is a truncated member") do
        Zlib::GzipReader.new(StringIO.new("\x1f\x8b\x08\x08\x00\x00\x00\x00\x00\x03na"))
      rescue Zlib::GzipFile::Error => e
        [e.message, e.input]
      end
      show("a crc error carries no input") do
        gz = Zlib.gzip("hello") + "TAIL"
        gz.setbyte(gz.bytesize - 12, gz.getbyte(gz.bytesize - 12) ^ 0xff)
        Zlib::GzipReader.new(StringIO.new(gz)).readlines
      rescue Zlib::GzipFile::CRCError => e
        [e.message, e.input]
      end
      show("a missing footer carries no input") do
        gz = Zlib.gzip("hello")
        Zlib::GzipReader.new(StringIO.new(gz[0..-9])).readlines
      rescue Zlib::GzipFile::NoFooter => e
        [e.message, e.input]
      end
      show("GzipFile itself does not construct") { Zlib::GzipFile.new }
      show("a dup arrives closed") do
        Zlib::GzipReader.new(StringIO.new(MB)).dup.read
      end

      # -- the writer's remaining edges -------------------------------------------

      show("write takes several arguments") do
        io = StringIO.new(+"".b)
        w = Zlib::GzipWriter.new(io)
        n = w.write("ab", "cd")
        w.close
        [n, Zlib.gunzip(io.string)]
      end
      show("puts flattens arrays and drops empty ones") do
        io = StringIO.new(+"".b)
        w = Zlib::GzipWriter.new(io)
        w.puts(["a", ["b", []]])
        w.close
        Zlib.gunzip(io.string)
      end
      show("putc writes one byte") do
        io = StringIO.new(+"".b)
        w = Zlib::GzipWriter.new(io)
        w.putc("éx")
        w.putc(233)
        w.close
        Zlib.gunzip(io.string).bytes
      end
      show("mtime= accepts a Time") do
        io = StringIO.new(+"".b)
        w = Zlib::GzipWriter.new(io)
        w.mtime = Time.at(99)
        w.write("x")
        w.close
        Zlib::GzipReader.new(StringIO.new(io.string)).mtime.to_i
      end
      show("flush answers the writer") do
        io = StringIO.new(+"".b)
        w = Zlib::GzipWriter.new(io)
        answered = w.flush.equal?(w)
        w.close
        answered
      end
      show("sync flag round-trips") do
        io = StringIO.new(+"".b)
        w = Zlib::GzipWriter.new(io)
        before = w.sync
        w.sync = true
        read_back = w.sync
        w.close
        [before, read_back]
      end

      # -- the stream counter the layer leans on ----------------------------------

      show("a finished raw inflate counts only consumed input") do
        raw = Zlib::Deflate.new(nil, -Zlib::MAX_WBITS).deflate("hello", Zlib::FINISH)
        z = Zlib::Inflate.new(-Zlib::MAX_WBITS)
        z.inflate(raw + "XYZW")
        [z.total_in, raw.bytesize]
      end
    RUBY

    _(result).must_answer <<~'OUT'
      paragraph gets: ["aaa\n\n", "bbb\nccc\n\n", "ddd", nil]
      gets limit never splits a character: ["hé", "l", "lo\n"]
      gets limit 0: ""
      gets sep and limit: "ax"
      gets rejects a hash: TypeError: no implicit conversion of Hash into Integer
      gets encoding: "UTF-8"
      gets at eof keeps lineno: [nil, 0]
      readlines with a separator: ["ax", "bx", "c"]
      readlines with a limit: ["hél", "lo\n", "wör", "ld\n"]
      blockless each_line drops its arguments: ["héllo\n", "wörld\n"]
      each_line block honours the limit: ["hé", "llo", "\n", "wö", "rld", "\n"]
      lineno=: 6
      read into a buffer keeps its encoding: [true, "hé", "UTF-8"]
      whole-member read ignores the buffer: [false, "seed"]
      readpartial into a buffer: ["hél", "UTF-8"]
      negative read: ArgumentError: negative length -1 given
      empty member: [true, "", nil]
      getc completes a multibyte character: ["h", "é"]
      pos follows ungetc backwards: ["h\xC3\xA9", 3, 2, "xl", 4]
      ungetc accepts a codepoint: "Ah\xC3"
      ungetbyte takes one byte of a string: "Ah\xC3\xA9"
      ungetbyte wraps an integer: ",h"
      zcat with a block yields each member: [["one", "two"], nil]
      zcat result encoding: "ASCII-8BIT"
      zcat refuses trailing garbage: Zlib::GzipFile::Error: not in gzip format
      a header-phase error carries the input: ["not in gzip format", "junkdata"]
      an EOF inside the ten header bytes is not gzip: ["not in gzip format", "\x1F\x8B\b"]
      an EOF past them is a truncated member: ["unexpected end of file", nil]
      a crc error carries no input: ["invalid compressed data -- crc error", nil]
      a missing footer carries no input: ["footer is not found", nil]
      GzipFile itself does not construct: TypeError: allocator undefined for Zlib::GzipFile
      a dup arrives closed: Zlib::GzipFile::Error: closed gzip stream
      write takes several arguments: [4, "abcd"]
      puts flattens arrays and drops empty ones: "a\nb\n"
      putc writes one byte: [195, 233]
      mtime= accepts a Time: 99
      flush answers the writer: true
      sync flag round-trips: [false, true]
      a finished raw inflate counts only consumed input: [7, 7]
    OUT
  end

  it "inflate data type and totals" do
    result = zr(<<~'RUBY')
      # The stream fields ruby exposes: data_type as deflate guesses it, the
      # adler, the totals, the buffers' counts, and the finished flags.
      require "zlib"

      def fields(z) = "type #{z.data_type} adler #{z.adler} in #{z.total_in} out #{z.total_out} avail_in #{z.avail_in} avail_out #{z.avail_out} finished #{z.finished?}"

      d = Zlib::Deflate.new(6)
      puts "new: #{fields(d)}"
      d << "plain text is text, plain text is text\n"
      puts "text: #{fields(d)}"
      d.finish
      puts "finished: #{fields(d)}"
      d.close

      d = Zlib::Deflate.new(6)
      d.deflate((0..255).to_a.pack("C*") * 4, Zlib::FINISH)
      puts "binary: #{fields(d)}"
      d.close

      d = Zlib::Deflate.new(6)
      d.deflate("tabs\tand\nnewlines\rare text; \x1b is not", Zlib::FINISH)
      puts "escape: #{fields(d)}"
      d.close

      d = Zlib::Deflate.new(6)
      d.deflate("\x00\x01\x02 low bytes", Zlib::FINISH)
      puts "low bytes: #{fields(d)}"
      d.close

      d = Zlib::Deflate.new(0)
      d.deflate("stored, so the type is not detected", Zlib::FINISH)
      puts "level 0: #{fields(d)}"
      d.close

      d = Zlib::Deflate.new(6)
      d.deflate("", Zlib::FINISH)
      puts "empty: #{fields(d)}"
      d.close

      d = Zlib::Deflate.new(6, 31)
      d.deflate("gzip carries a crc32", Zlib::FINISH)
      puts "gzip: #{fields(d)} = crc #{Zlib.crc32("gzip carries a crc32")}"
      d.close

      d = Zlib::Deflate.new(6, -15)
      d.deflate("raw keeps an adler anyway", Zlib::FINISH)
      puts "raw: #{fields(d)}"
      d.close

      packed = Zlib::Deflate.deflate("inflate side totals and adler", 6)
      i = Zlib::Inflate.new
      puts "new: #{fields(i)}"
      i.inflate(packed[0, 5])
      puts "partial: #{fields(i)}"
      i.inflate(packed[5..])
      puts "whole: #{fields(i)}"
      puts "stream end: #{i.stream_end?} closed #{i.closed?}"
      i.close
      puts "closed: #{i.closed?}"

      i = Zlib::Inflate.new
      i.inflate(packed + "trailing bytes")
      puts "trailing: #{fields(i)} rest #{i.flush_next_in.inspect}"
      i.close

    RUBY

    _(result).must_answer <<~'OUT'
      new: type 2 adler 1 in 0 out 0 avail_in 0 avail_out 0 finished false
      text: type 2 adler 522456587 in 39 out 2 avail_in 0 avail_out 1022 finished false
      finished: type 1 adler 522456587 in 39 out 28 avail_in 0 avail_out 0 finished true
      binary: type 0 adler 3838443024 in 1024 out 286 avail_in 0 avail_out 0 finished true
      escape: type 1 adler 3927379043 in 36 out 44 avail_in 0 avail_out 0 finished true
      low bytes: type 0 adler 320537533 in 13 out 21 avail_in 0 avail_out 0 finished true
      level 0: type 2 adler 3846114514 in 35 out 46 avail_in 0 avail_out 0 finished true
      empty: type 0 adler 1 in 0 out 8 avail_in 0 avail_out 0 finished true
      gzip: type 1 adler 2544769400 in 20 out 40 avail_in 0 avail_out 0 finished true = crc 2544769400
      raw: type 1 adler 1 in 25 out 25 avail_in 0 avail_out 0 finished true
      new: type 0 adler 1 in 0 out 0 avail_in 0 avail_out 0 finished false
      partial: type 69 adler 21102808 in 5 out 2 avail_in 0 avail_out 0 finished false
      whole: type 64 adler 2764704475 in 37 out 29 avail_in 0 avail_out 0 finished true
      stream end: true closed false
      closed: true
      trailing: type 64 adler 2764704475 in 37 out 29 avail_in 0 avail_out 0 finished true rest ""
    OUT
  end

  it "an invalid block type and a broken stored block each raise DataError" do
    result = zr(<<~'RUBY')
      # Every message inflate gives for a broken stream, from hand-built
      # streams: the block types, the code length sets, the distances, the
      # wrappers' headers and trailers.
      require "zlib"

      # Bits packed least significant first, as deflate packs them; a Huffman
      # code goes in most significant bit first.
      class Bits
        def initialize = @bits = []
        def put(value, n) = n.times { |i| @bits << ((value >> i) & 1) }
        def code(value, n) = n.times { |i| @bits << ((value >> (n - 1 - i)) & 1) }
        def align = @bits.concat([0] * ((8 - @bits.size % 8) % 8))
        def bytes = @bits.each_slice(8).map { |s| s.each_with_index.sum { |b, i| b << i } }.pack("C*")
      end

      def inflate(bytes, wbits, label)
        i = Zlib::Inflate.new(wbits)
        out = i.inflate(bytes)
        out << i.finish if !i.finished? && i.avail_in.zero?
        puts "#{label}: ok #{out.inspect}"
      rescue Zlib::Error => e
        puts "#{label}: #{e.class}: #{e.message}"
      ensure
        i&.close
      end

      def block(&build) = Bits.new.tap(&build).bytes

      # A fixed-Huffman literal, length or distance symbol.
      def fixed_lit(b, sym)
        if sym <= 143 then b.code(0x30 + sym, 8)
        elsif sym <= 255 then b.code(0x190 + sym - 144, 9)
        elsif sym <= 279 then b.code(sym - 256, 7)
        else b.code(0xC0 + sym - 280, 8)
        end
      end

      inflate(block { |b| b.put(1, 1); b.put(3, 2) }, -15, "block type 3")
      inflate(block { |b| b.put(1, 1); b.put(0, 2); b.align; b.put(5, 16); b.put(0, 16) }, -15, "stored lengths")
      inflate(block { |b| b.put(1, 1); b.put(0, 2); b.align; b.put(3, 16); b.put(0xfffc, 16); b.put(0x41, 8) }, -15, "stored block cut short")
      inflate(block { |b| b.put(1, 1); b.put(2, 2); b.put(30, 5); b.put(0, 5); b.put(0, 4) }, -15, "too many symbols")
      inflate(block { |b| b.put(1, 1); b.put(2, 2); b.put(0, 5); b.put(0, 5); b.put(0, 4); 4.times { b.put(1, 3) } }, -15, "code lengths over-subscribed")
      inflate(block { |b|
        b.put(1, 1); b.put(2, 2); b.put(0, 5); b.put(0, 5); b.put(0, 4)
        [1, 2, 2, 0].each { |len| b.put(len, 3) } # 16: "0", 17: "10", 18: "11"
        b.code(0b0, 1) # repeat with nothing before it
      }, -15, "repeat with no previous length")
      inflate(block { |b|
        b.put(1, 1); b.put(2, 2); b.put(0, 5); b.put(0, 5); b.put(0, 4)
        [0, 2, 2, 1].each { |len| b.put(len, 3) } # 0: "0", 17: "10", 18: "11"
        b.code(0b11, 2); b.put(127, 7) # 138 zeros
        b.code(0b11, 2); b.put(109, 7) # 120 zeros: 258 in all
      }, -15, "no end-of-block code")
      inflate(block { |b|
        b.put(1, 1); b.put(2, 2); b.put(0, 5); b.put(0, 5); b.put(0, 4)
        [0, 2, 2, 1].each { |len| b.put(len, 3) }
        b.code(0b11, 2); b.put(127, 7)
        b.code(0b11, 2); b.put(127, 7) # 276 > 258
      }, -15, "repeat runs past the end")
      inflate(block { |b|
        b.put(1, 1); b.put(2, 2); b.put(0, 5); b.put(0, 5); b.put(14, 4)
        # order 16 17 18 0 8 7 9 6 10 5 11 4 12 3 13 2 14 1: lengths for 0 and 18 are 2 bits, for 1 one bit
        [0, 0, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1].each { |len| b.put(len, 3) }
        3.times { b.code(0b0, 1) }          # symbols 0..2 with length 1: over-subscribed
        b.code(0b11, 2); b.put(127, 7)      # 138 zeros
        b.code(0b11, 2); b.put(104, 7)      # 115 zeros: 256 so far
        b.code(0b0, 1)                      # 256 has length 1
        b.code(0b10, 2)                     # the one distance length: 0
      }, -15, "literal lengths over-subscribed")
      inflate(block { |b|
        b.put(1, 1); b.put(2, 2); b.put(0, 5); b.put(2, 5); b.put(14, 4)
        [0, 0, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1].each { |len| b.put(len, 3) }
        b.code(0b0, 1)                      # symbol 0 length 1
        b.code(0b11, 2); b.put(127, 7)      # 138 zeros
        b.code(0b11, 2); b.put(106, 7)      # 117 zeros: 256 so far
        b.code(0b0, 1)                      # 256 length 1: complete
        3.times { b.code(0b0, 1) }          # three distances of length 1: over-subscribed
      }, -15, "distance lengths over-subscribed")
      inflate(block { |b| b.put(1, 1); b.put(1, 2); fixed_lit(b, 0x61); fixed_lit(b, 257); b.code(4, 5); b.put(0, 1); fixed_lit(b, 256) }, -15, "distance before the start")
      inflate(block { |b| b.put(1, 1); b.put(1, 2); fixed_lit(b, 0x61); fixed_lit(b, 257); b.code(30, 5) }, -15, "distance code 30")
      inflate(block { |b| b.put(1, 1); b.put(1, 2); fixed_lit(b, 286) }, -15, "literal code 286")
      inflate(block { |b| b.put(1, 1); b.put(1, 2); fixed_lit(b, 0x61); fixed_lit(b, 0x62); fixed_lit(b, 256) }, -15, "a good fixed block")
      inflate(block { |b| b.put(1, 1); b.put(1, 2); fixed_lit(b, 0x61) }, -15, "cut before the end-of-block")

    RUBY

    _(result).must_answer <<~'OUT'
      block type 3: Zlib::DataError: invalid block type
      stored lengths: Zlib::DataError: invalid stored block lengths
      stored block cut short: Zlib::BufError: buffer error
      too many symbols: Zlib::DataError: too many length or distance symbols
      code lengths over-subscribed: Zlib::DataError: invalid code lengths set
      repeat with no previous length: Zlib::DataError: invalid bit length repeat
      no end-of-block code: Zlib::DataError: invalid code -- missing end-of-block
      repeat runs past the end: Zlib::DataError: invalid bit length repeat
      literal lengths over-subscribed: Zlib::DataError: invalid literal/lengths set
      distance lengths over-subscribed: Zlib::DataError: invalid distances set
      distance before the start: Zlib::DataError: invalid distance too far back
      distance code 30: Zlib::DataError: invalid distance code
      literal code 286: Zlib::DataError: invalid literal/length code
      a good fixed block: ok "ab"
      cut before the end-of-block: Zlib::BufError: buffer error
    OUT
  end

  it "a wrong header check raises DataError and says so" do
    result = zr(<<~'RUBY')
      # Every message inflate gives for a broken stream, from hand-built
      # streams: the block types, the code length sets, the distances, the
      # wrappers' headers and trailers.
      require "zlib"

      # Bits packed least significant first, as deflate packs them; a Huffman
      # code goes in most significant bit first.
      class Bits
        def initialize = @bits = []
        def put(value, n) = n.times { |i| @bits << ((value >> i) & 1) }
        def code(value, n) = n.times { |i| @bits << ((value >> (n - 1 - i)) & 1) }
        def align = @bits.concat([0] * ((8 - @bits.size % 8) % 8))
        def bytes = @bits.each_slice(8).map { |s| s.each_with_index.sum { |b, i| b << i } }.pack("C*")
      end

      def inflate(bytes, wbits, label)
        i = Zlib::Inflate.new(wbits)
        out = i.inflate(bytes)
        out << i.finish if !i.finished? && i.avail_in.zero?
        puts "#{label}: ok #{out.inspect}"
      rescue Zlib::Error => e
        puts "#{label}: #{e.class}: #{e.message}"
      ensure
        i&.close
      end

      def block(&build) = Bits.new.tap(&build).bytes

      # A fixed-Huffman literal, length or distance symbol.
      def fixed_lit(b, sym)
        if sym <= 143 then b.code(0x30 + sym, 8)
        elsif sym <= 255 then b.code(0x190 + sym - 144, 9)
        elsif sym <= 279 then b.code(sym - 256, 7)
        else b.code(0xC0 + sym - 280, 8)
        end
      end

      good = Zlib::Deflate.deflate("hello, hello, hello", 6)
      inflate("\x78\x9d".b, 15, "wrong header check")
      inflate("\x79\x18".b, 15, "compression method 9")
      inflate("\x88\x1c".b, 15, "window 32K past the limit")
      inflate(good[0, 2] + Zlib::Deflate.new(6, -9).deflate("smaller window", Zlib::FINISH), 8, "window larger than asked")
      inflate(good.dup.tap { |s| s.setbyte(-1, s.getbyte(-1) ^ 1) }, 15, "adler32 off by one")
      inflate(good[0..-2], 15, "adler32 cut short")
      inflate(good.dup.tap { |s| s.setbyte(5, s.getbyte(5) ^ 0x40) }, 15, "a flipped bit inside")
      inflate("".b, 15, "nothing")
      inflate(good, 15, "good zlib stream")
      inflate(good, -15, "zlib stream read as raw")
      inflate(good, 31, "zlib stream read as gzip")
      inflate(good, 47, "zlib stream with auto detection")

    RUBY

    _(result).must_answer <<~'OUT'
      wrong header check: Zlib::DataError: incorrect header check
      compression method 9: Zlib::DataError: unknown compression method
      window 32K past the limit: Zlib::DataError: invalid window size
      window larger than asked: Zlib::DataError: invalid window size
      adler32 off by one: Zlib::DataError: incorrect data check
      adler32 cut short: Zlib::BufError: buffer error
      a flipped bit inside: Zlib::DataError: incorrect data check
      nothing: Zlib::BufError: buffer error
      good zlib stream: ok "hello, hello, hello"
      zlib stream read as raw: Zlib::DataError: invalid stored block lengths
      zlib stream read as gzip: Zlib::DataError: incorrect header check
      zlib stream with auto detection: ok "hello, hello, hello"
    OUT
  end

  it "a good gzip stream still reads, whatever the corrupt ones did" do
    result = zr(<<~'RUBY')
      # Every message inflate gives for a broken stream, from hand-built
      # streams: the block types, the code length sets, the distances, the
      # wrappers' headers and trailers.
      require "zlib"

      # Bits packed least significant first, as deflate packs them; a Huffman
      # code goes in most significant bit first.
      class Bits
        def initialize = @bits = []
        def put(value, n) = n.times { |i| @bits << ((value >> i) & 1) }
        def code(value, n) = n.times { |i| @bits << ((value >> (n - 1 - i)) & 1) }
        def align = @bits.concat([0] * ((8 - @bits.size % 8) % 8))
        def bytes = @bits.each_slice(8).map { |s| s.each_with_index.sum { |b, i| b << i } }.pack("C*")
      end

      def inflate(bytes, wbits, label)
        i = Zlib::Inflate.new(wbits)
        out = i.inflate(bytes)
        out << i.finish if !i.finished? && i.avail_in.zero?
        puts "#{label}: ok #{out.inspect}"
      rescue Zlib::Error => e
        puts "#{label}: #{e.class}: #{e.message}"
      ensure
        i&.close
      end

      def block(&build) = Bits.new.tap(&build).bytes

      # A fixed-Huffman literal, length or distance symbol.
      def fixed_lit(b, sym)
        if sym <= 143 then b.code(0x30 + sym, 8)
        elsif sym <= 255 then b.code(0x190 + sym - 144, 9)
        elsif sym <= 279 then b.code(sym - 256, 7)
        else b.code(0xC0 + sym - 280, 8)
        end
      end

      gz = Zlib.gzip("gzip payload, gzip payload")
      inflate(gz, 31, "good gzip")
      inflate(gz, 47, "gzip with auto detection")
      inflate(gz, 15, "gzip read as zlib")
      inflate(gz.dup.tap { |s| s.setbyte(2, 7) }, 31, "gzip method 7")
      inflate(gz.dup.tap { |s| s.setbyte(3, 0xe0) }, 31, "gzip reserved flags")
      inflate(gz.dup.tap { |s| s.setbyte(-1, s.getbyte(-1) ^ 1) }, 31, "gzip length off")
      inflate(gz.dup.tap { |s| s.setbyte(-5, s.getbyte(-5) ^ 1) }, 31, "gzip crc off")
      hcrc = "\x1f\x8b\x08\x02\x00\x00\x00\x00\x00\x03\xff\xff".b + gz[10..]
      inflate(hcrc, 31, "gzip header crc wrong")
      named = "\x1f\x8b\x08\x08\x00\x00\x00\x00\x00\x03name\x00".b + gz[10..]
      inflate(named, 31, "gzip with a name")
      extra = "\x1f\x8b\x08\x04\x00\x00\x00\x00\x00\x03\x03\x00abc".b + gz[10..]
      inflate(extra, 31, "gzip with an extra field")
      inflate(gz + gz, 31, "two gzip members")

    RUBY

    _(result).must_answer <<~'OUT'
      good gzip: ok "gzip payload, gzip payload"
      gzip with auto detection: ok "gzip payload, gzip payload"
      gzip read as zlib: Zlib::DataError: incorrect header check
      gzip method 7: Zlib::DataError: unknown compression method
      gzip reserved flags: Zlib::DataError: unknown header flags set
      gzip length off: Zlib::DataError: incorrect length check
      gzip crc off: Zlib::DataError: incorrect data check
      gzip header crc wrong: Zlib::DataError: header crc mismatch
      gzip with a name: ok "gzip payload, gzip payload"
      gzip with an extra field: ok "gzip payload, gzip payload"
      two gzip members: ok "gzip payload, gzip payload"
    OUT
  end

  it "inflate sync and sync point" do
    result = zr(<<~'RUBY')
      # inflateSync finds the next full-flush point after damage, and
      # sync_point? reports a stream stopped at one.
      require "zlib"

      d = Zlib::Deflate.new(6)
      head = d.deflate("the part before the flush point, ", Zlib::FULL_FLUSH)
      tail = d.deflate("and the part after it", Zlib::FINISH)
      d.close
      puts "head ends with the empty stored block: #{head[-4..].unpack1("H*")}"

      i = Zlib::Inflate.new
      puts "read: #{i.inflate(head[0, 6]).inspect}"
      puts "sync point mid-block: #{i.sync_point?}"
      puts "read: #{i.inflate(head[6..]).inspect}"
      puts "sync point at the flush: #{i.sync_point?}"
      puts "read: #{i.inflate(tail).inspect}"
      puts "finished: #{i.finished?}"
      i.close

      garbage = "\xff\x00\x11\x22".b
      i = Zlib::Inflate.new
      out = +""
      out << i.inflate(head[0, 4])
      begin
        out << i.inflate(garbage + head[4..] + tail)
      rescue Zlib::DataError => e
        puts "damage: #{e.message}"
      end
      puts "sync into the rest: #{i.sync(head[-4..] + tail)}"
      puts "after sync: #{i.inflate("").inspect}"
      puts "finished: #{i.finished?}"
      i.close

      i = Zlib::Inflate.new
      i.inflate(head[0, 4])
      puts "sync with no marker: #{i.sync("no marker in here at all")}"
      puts "sync with a marker later: #{i.sync("xx\x00\x00\xff\xffdata".b)}"
      i.close

      i = Zlib::Inflate.new
      puts "sync before any input: #{i.sync(head + tail)}"
      i.close

      d = Zlib::Deflate.new(6)
      a = d.deflate("sync", Zlib::SYNC_FLUSH)
      b = d.deflate("flush", Zlib::SYNC_FLUSH)
      c = d.finish
      d.close
      i = Zlib::Inflate.new
      [a, b, c].each do |piece|
        got = i.inflate(piece)
        puts "#{got.inspect} sync point #{i.sync_point?} finished #{i.finished?}"
      end
      i.close

    RUBY

    _(result).must_answer <<~'OUT'
      head ends with the empty stored block: 0000ffff
      read: "the"
      sync point mid-block: false
      read: " part before the flush point, "
      sync point at the flush: false
      read: "and the part after it"
      finished: true
      damage: invalid distance too far back
      sync into the rest: true
      after sync: "o\xF0and the part after it"
      finished: true
      sync with no marker: false
      sync with a marker later: true
      sync before any input: true
      "sync" sync point false finished false
      "flush" sync point false finished false
      "" sync point false finished true
    OUT
  end

  it "io copy stream honours length and offset" do
    result = zr(<<~'RUBY')
      # `IO.copy_stream`'s third and fourth arguments.
      #
      # Both were accepted and dropped. `copy_length` is what rubygems unpacks every
      # `.gem` with -- `copy_stream(tar.io, out, entry.size)` -- so every extracted
      # file got the rest of the archive appended to it. A pure-ruby gem survived
      # that (ruby never reads past the code it needs); a C extension did not, and
      # the compiler lexing megabytes of trailing NUL bytes is what made a
      # `gem install` appear to hang.
      #
      # The negative cases are the surprising half and are the reason they are here:
      # a negative length copies EVERYTHING and a negative offset reads from the
      # start, neither of which raises.

      require "stringio"
      require "tempfile"
      require "zlib"

      BODY = (0...1000).map { |i| (97 + i % 26).chr }.join
      DIR = Dir.mktmpdir("copy-stream")
      SRC = File.join(DIR, "src.bin")
      File.binwrite(SRC, BODY)
      GZ = File.join(DIR, "src.gz")
      Zlib::GzipWriter.open(GZ) { |w| w.write BODY }

      def report(label)
        out = File.join(DIR, "out.bin")
        File.binwrite(out, "")
        n = yield out
        data = File.binread(out)
        puts format("%-26s ret=%-5s wrote=%-5d head=%s", label, n.inspect, data.bytesize, data[0, 6].inspect)
      rescue StandardError => e
        puts format("%-26s %s: %s", label, e.class, e.message)
      end

      # --- a length, from a file ------------------------------------------------
      report("no length") { |o| IO.copy_stream(SRC, o) }
      report("length 300") { |o| IO.copy_stream(SRC, o, 300) }
      report("length 0") { |o| IO.copy_stream(SRC, o, 0) }
      report("length past the end") { |o| IO.copy_stream(SRC, o, 99_999) }
      report("length -1") { |o| IO.copy_stream(SRC, o, -1) }
      report("length 5.9") { |o| IO.copy_stream(SRC, o, 5.9) }
      report("length a String") { |o| IO.copy_stream(SRC, o, "5") }

      # --- an offset ------------------------------------------------------------
      report("offset 200") { |o| IO.copy_stream(SRC, o, 10, 200) }
      report("offset -1") { |o| IO.copy_stream(SRC, o, 10, -1) }
      report("offset past the end") { |o| IO.copy_stream(SRC, o, 10, 99_999) }
      report("offset, no length") { |o| IO.copy_stream(SRC, o, nil, 990) }

      # --- an IO source, which advances -----------------------------------------
      report("io, length 300") { |o| File.open(SRC, "rb") { |i| IO.copy_stream(i, o, 300) } }
      report("io, two copies") do |o|
        File.open(SRC, "rb") { |i| IO.copy_stream(i, o, 10) + IO.copy_stream(i, o, 10) }
      end
      # An offset reads without moving the position -- the answer here is `pos`.
      report("io, offset keeps pos") do |o|
        File.open(SRC, "rb") { |i| IO.copy_stream(i, o, 10, 200); i.pos }
      end

      # --- the sources rubygems actually unpacks through ------------------------
      report("StringIO source") { |o| IO.copy_stream(StringIO.new(BODY), o, 300) }
      report("gzip source") { |o| Zlib::GzipReader.open(GZ) { |i| IO.copy_stream(i, o, 300) } }
      report("gzip, two copies") do |o|
        Zlib::GzipReader.open(GZ) { |i| IO.copy_stream(i, o, 10) + IO.copy_stream(i, o, 10) }
      end
      report("StringIO + offset") { |o| IO.copy_stream(StringIO.new(BODY), o, 10, 200) }

      # --- a source shorter than the length asked for ---------------------------
      SHORT = File.join(DIR, "short.bin")
      File.binwrite(SHORT, "abc")
      report("short source") { |o| IO.copy_stream(SHORT, o, 300) }
      EMPTY = File.join(DIR, "empty.bin")
      File.binwrite(EMPTY, "")
      report("empty source") { |o| IO.copy_stream(EMPTY, o, 300) }

      # --- an IO destination ----------------------------------------------------
      report("io destination") { |o| File.open(o, "wb") { |w| IO.copy_stream(SRC, w, 300) } }
      sink = StringIO.new(+"")
      n = IO.copy_stream(StringIO.new(BODY), sink, 7)
      puts format("%-26s ret=%-5s wrote=%-5d head=%s", "StringIO destination", n.inspect,
                  sink.string.bytesize, sink.string[0, 6].inspect)

      # The destination opens first, so a file copied onto itself is truncated
      # before it is read.
      SELF = File.join(DIR, "self.bin")
      File.binwrite(SELF, BODY)
      puts "onto itself: #{IO.copy_stream(SELF, SELF, 5).inspect} #{File.size(SELF)}"

      # A missing source names the OPEN, not the copy.
      begin
        IO.copy_stream(File.join(DIR, "absent"), File.join(DIR, "out2.bin"))
      rescue SystemCallError => e
        puts "missing source: #{e.class} #{e.message.sub(DIR, '<dir>')}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      no length                  ret=1000  wrote=1000  head="abcdef"
      length 300                 ret=300   wrote=300   head="abcdef"
      length 0                   ret=0     wrote=0     head=""
      length past the end        ret=1000  wrote=1000  head="abcdef"
      length -1                  ret=1000  wrote=1000  head="abcdef"
      length 5.9                 ret=5     wrote=5     head="abcde"
      length a String            TypeError: no implicit conversion from string
      offset 200                 ret=10    wrote=10    head="stuvwx"
      offset -1                  ret=10    wrote=10    head="abcdef"
      offset past the end        ret=0     wrote=0     head=""
      offset, no length          ret=10    wrote=10    head="cdefgh"
      io, length 300             ret=300   wrote=300   head="abcdef"
      io, two copies             ret=20    wrote=10    head="klmnop"
      io, offset keeps pos       ret=0     wrote=10    head="stuvwx"
      StringIO source            ret=300   wrote=300   head="abcdef"
      gzip source                ret=300   wrote=300   head="abcdef"
      gzip, two copies           ret=20    wrote=10    head="klmnop"
      StringIO + offset          ArgumentError: cannot specify src_offset for non-IO
      short source               ret=3     wrote=3     head="abc"
      empty source               ret=0     wrote=0     head=""
      io destination             ret=300   wrote=300   head="abcdef"
      StringIO destination       ret=7     wrote=7     head="abcdef"
      onto itself: 0 0
      missing source: Errno::ENOENT No such file or directory @ rb_sysopen - <dir>/absent
    OUT
  end

  it "subclass of zlib inflate inherits the stream" do
    result = zr(<<~'RUBY')
      # `Zlib::Inflate` is a value-builtin payload root: a subclass wraps the
      # native stream as its payload and adds ivars of its own -- `Inflate.new`
      # with no arguments is a real empty form, so a subclass without its own
      # `initialize` seats one directly, and one WITH an `initialize` re-seats
      # through `super`. The single biggest subclassing ask in the gem-probe
      # ledger (35 gems).
      require "zlib"

      deflated = Zlib::Deflate.deflate("hello, payload root")

      class TaggedInflate < Zlib::Inflate
        def initialize(tag)
          @tag = tag
          super()
        end

        attr_reader :tag
      end

      inf = TaggedInflate.new("gzip-ish")
      puts inf.class
      puts inf.tag
      puts inf.inflate(deflated)
      inf.close

      puts TaggedInflate.new("t").is_a?(Zlib::Inflate)
    RUBY

    _(result).must_answer <<~'OUT'
      TaggedInflate
      gzip-ish
      hello, payload root
      true
    OUT
  end

  it "an invalid compression level raises StreamError, and a corrupt gzip trailer still reads" do
    result = zr(<<~'RUBY')
      # Zlib rows beyond the (matching) core: an invalid compression level
      # raises Zlib::StreamError (zr compresses anyway); `Zlib.crc32_combine`
      # and `Zlib.zlib_version`/`Zlib::VERSION` are absent; and a gzip stream
      # with a corrupted ISIZE trailer still reads in ruby where zr refuses
      # with "not in gzip format". (Found by the 2026-08-24 probe sweep.)
      require "zlib"
      require "stringio"
      def show
        p yield
      rescue Exception => e
        puts "#{e.class}: #{e.message}"
      end
      show { Zlib::Deflate.deflate("x", 99) }
      show { Zlib.crc32_combine(Zlib.crc32("he"), Zlib.crc32("llo"), 3) == Zlib.crc32("hello") }
      show { [Zlib.zlib_version.class, Zlib::VERSION.class] }
      show do
        io = StringIO.new(+"".b)
        Zlib::GzipWriter.wrap(io) { |g| g.write("x") }
        bad = io.string.dup
        bad[-5] = (bad[-5].ord ^ 0xFF).chr
        Zlib::GzipReader.new(StringIO.new(bad)).read
      end
    RUBY

    _(result).must_answer <<~'OUT'
      Zlib::StreamError: stream error
      true
      [String, String]
      "x"
    OUT
  end

  it "crc32 and adler32 answer what ruby answers, with and without a seed" do
    result = zr(<<~'RUBY')
      require "zlib"
      puts Zlib.crc32("abc")
      puts Zlib.adler32("abc")
      puts Zlib.crc32("abc", 100)
    RUBY

    _(result).must_answer <<~'OUT'
      891568578
      38600999
      2063213118
    OUT
  end

  it "deflate hands back what has been flushed so far, and << queues the rest" do
    result = zr(<<~'RUBY')
      # zlib's class surface: the incremental `ZStream` pair and the IO-shaped gzip
      # pair. Nothing here prints a timestamp or a whole compressed buffer -- gzip
      # headers carry the current time, and deflate output is only guaranteed to
      # ROUND-TRIP, not to be byte-identical across zlib implementations.
      require "zlib"
      require "stringio"

      def show(label)
        print "#{label}: "
        p(yield)
      rescue => e
        puts "#{e.class}: #{e.message}"
      end

      TEXT = "the quick brown fox jumps over the lazy dog. " * 4

      # -- Deflate/Inflate: the incremental surface -------------------------------

      # `deflate` hands back what has been FLUSHED so far, which with the default
      # NO_FLUSH is usually nothing; `finish` drains the rest.
      show("streamed round-trip") do
        z = Zlib::Deflate.new
        parts = [z.deflate("hello "), z.deflate("world"), z.finish]
        Zlib::Inflate.inflate(parts.join)
      end
      # `<<` queues its output instead of handing it back, so the whole stream
      # arrives on the next detaching call.
      show("shovel queues") do
        z = Zlib::Deflate.new
        z << "hello " << "world"
        Zlib::Inflate.inflate(z.finish)
      end
      show("sync flush mid-stream") do
        z = Zlib::Deflate.new
        first = z.deflate("hello", Zlib::SYNC_FLUSH)
        [first.empty?, Zlib::Inflate.inflate(first + z.finish)]
      end
      show("one-shot class methods") { Zlib::Inflate.inflate(Zlib::Deflate.deflate(TEXT)) == TEXT }
      show("compressed encoding") { Zlib::Deflate.deflate("hi").encoding.to_s }
      show("inflated encoding") { Zlib::Inflate.inflate(Zlib.deflate("hi")).encoding.to_s }

    RUBY

    _(result).must_answer <<~'OUT'
      streamed round-trip: "hello world"
      shovel queues: "hello world"
      sync flush mid-stream: [false, "hello"]
      one-shot class methods: true
      compressed encoding: "ASCII-8BIT"
      inflated encoding: "ASCII-8BIT"
    OUT
  end

  it "the window bits pick the container, which is how a client decodes a raw stream" do
    result = zr(<<~'RUBY')
      # zlib's class surface: the incremental `ZStream` pair and the IO-shaped gzip
      # pair. Nothing here prints a timestamp or a whole compressed buffer -- gzip
      # headers carry the current time, and deflate output is only guaranteed to
      # ROUND-TRIP, not to be byte-identical across zlib implementations.
      require "zlib"
      require "stringio"

      def show(label)
        print "#{label}: "
        p(yield)
      rescue => e
        puts "#{e.class}: #{e.message}"
      end

      TEXT = "the quick brown fox jumps over the lazy dog. " * 4

      # -- Deflate/Inflate: the incremental surface -------------------------------

      # Window bits pick the container, and are the reason `Net::HTTP` can decode a
      # body before it knows which encoding arrived.
      show("raw deflate") do
        raw = Zlib::Deflate.new(9, -Zlib::MAX_WBITS).deflate("hi", Zlib::FINISH)
        [raw[0].unpack1("C"), Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(raw)]
      end
      show("gzip via window bits") do
        gz = Zlib::Deflate.new(9, 16 + Zlib::MAX_WBITS).deflate("hi", Zlib::FINISH)
        [gz.bytes.first(2), Zlib.gunzip(gz)]
      end
      show("auto-detect gzip") { Zlib::Inflate.new(32 + Zlib::MAX_WBITS).inflate(Zlib.gzip("hello")) }
      show("auto-detect zlib") { Zlib::Inflate.new(32 + Zlib::MAX_WBITS).inflate(Zlib.deflate("hello")) }
      show("split across writes") do
        gz = Zlib.gzip(TEXT)
        z = Zlib::Inflate.new(32 + Zlib::MAX_WBITS)
        out = +""
        gz.each_byte { |b| out << z.inflate(b.chr) }
        out == TEXT
      end

    RUBY

    _(result).must_answer <<~'OUT'
      raw deflate: [203, "hi"]
      gzip via window bits: [[31, 139], "hi"]
      auto-detect gzip: "hello"
      auto-detect zlib: "hello"
      split across writes: true
    OUT
  end

  it "the counters and the lifecycle a ZStream shares all answer" do
    result = zr(<<~'RUBY')
      # zlib's class surface: the incremental `ZStream` pair and the IO-shaped gzip
      # pair. Nothing here prints a timestamp or a whole compressed buffer -- gzip
      # headers carry the current time, and deflate output is only guaranteed to
      # ROUND-TRIP, not to be byte-identical across zlib implementations.
      require "zlib"
      require "stringio"

      def show(label)
        print "#{label}: "
        p(yield)
      rescue => e
        puts "#{e.class}: #{e.message}"
      end

      TEXT = "the quick brown fox jumps over the lazy dog. " * 4

      # -- Deflate/Inflate: the incremental surface -------------------------------

      # The counters and lifecycle `ZStream` shares.
      show("counters") do
        z = Zlib::Deflate.new
        z.deflate("hello world", Zlib::FINISH)
        [z.total_in, z.adler, z.data_type, z.avail_in, z.finished?, z.closed?]
      end
      show("avail_out is a knob") do
        z = Zlib::Deflate.new
        z.avail_out = 100
        z.avail_out
      end
      # Only the CONTENT is asserted, not whether the queue had anything in it yet:
      # zlib emits the 2-byte stream header as soon as `<<` runs, miniz_oxide holds
      # it until there is compressed data to go with it. Both produce the same
      # stream (see docs/COMPATIBILITY.md).
      show("flush_next_out drains") do
        z = Zlib::Deflate.new
        z << "hello"
        Zlib::Inflate.inflate(z.flush_next_out + z.finish)
      end
      show("reset starts over") do
        z = Zlib::Deflate.new
        z.deflate("discarded")
        z.reset
        [Zlib::Inflate.inflate(z.deflate("kept", Zlib::FINISH)), z.total_in]
      end
      show("close then use") do
        z = Zlib::Deflate.new
        z.finish
        z.close
        [z.closed?, (z.deflate("x") rescue "#{$!.class}")]
      end
      show("deflate after finish") do
        z = Zlib::Deflate.new
        z.finish
        z.deflate("x")
      end
      show("finish twice") { z = Zlib::Deflate.new; z.finish; z.finish }

    RUBY

    _(result).must_answer <<~'OUT'
      counters: [11, 436929629, 1, 0, true, false]
      avail_out is a knob: 100
      flush_next_out drains: "hello"
      reset starts over: ["kept", 4]
      close then use: [true, "Zlib::Error"]
      deflate after finish: Zlib::StreamError: stream error
      finish twice: ""
    OUT
  end

  it "each failure mode of the incremental surface raises its own class" do
    result = zr(<<~'RUBY')
      # zlib's class surface: the incremental `ZStream` pair and the IO-shaped gzip
      # pair. Nothing here prints a timestamp or a whole compressed buffer -- gzip
      # headers carry the current time, and deflate output is only guaranteed to
      # ROUND-TRIP, not to be byte-identical across zlib implementations.
      require "zlib"
      require "stringio"

      def show(label)
        print "#{label}: "
        p(yield)
      rescue => e
        puts "#{e.class}: #{e.message}"
      end

      TEXT = "the quick brown fox jumps over the lazy dog. " * 4

      # -- Deflate/Inflate: the incremental surface -------------------------------

      # Failure modes, each its own exception class.
      show("not compressed at all") { Zlib::Inflate.inflate("not compressed at all") }
      show("truncated stream") { Zlib::Inflate.inflate(Zlib.deflate(TEXT)[0..5]) }
      show("trailing garbage") do
        z = Zlib::Inflate.new
        [z.inflate(Zlib.deflate("hi") + "EXTRA"), z.finished?]
      end
      show("sync_point?") { Zlib::Inflate.new.sync_point? }

    RUBY

    _(result).must_answer <<~'OUT'
      not compressed at all: Zlib::DataError: incorrect header check
      truncated stream: Zlib::BufError: buffer error
      trailing garbage: ["hi", true]
      sync_point?: false
    OUT
  end

  it "a GzipWriter round-trips its payload and answers the io it closed" do
    result = zr(<<~'RUBY')
      # zlib's class surface: the incremental `ZStream` pair and the IO-shaped gzip
      # pair. Nothing here prints a timestamp or a whole compressed buffer -- gzip
      # headers carry the current time, and deflate output is only guaranteed to
      # ROUND-TRIP, not to be byte-identical across zlib implementations.
      require "zlib"
      require "stringio"

      def show(label)
        print "#{label}: "
        p(yield)
      rescue => e
        puts "#{e.class}: #{e.message}"
      end

      TEXT = "the quick brown fox jumps over the lazy dog. " * 4

      # -- GzipWriter/GzipReader --------------------------------------------------

      GZ = Zlib.gzip("hello\nworld\n")

      show("writer round-trip") do
        io = StringIO.new("".b)
        w = Zlib::GzipWriter.new(io)
        w.write("hello ")
        w << "world"
        w.close
        Zlib.gunzip(io.string)
      end
      show("writer close answers the io") do
        io = StringIO.new("".b)
        Zlib::GzipWriter.new(io).close.equal?(io)
      end
      show("writer wrap answers the block") do
        io = StringIO.new("".b)
        value = Zlib::GzipWriter.wrap(io) { |w| w.write("wrapped"); 42 }
        [value, Zlib.gunzip(io.string)]
      end
      show("writer header fields") do
        io = StringIO.new("".b)
        w = Zlib::GzipWriter.new(io)
        w.mtime = 1234567890
        w.orig_name = "f.txt"
        w.comment = "a note"
        w.write("x")
        w.close
        r = Zlib::GzipReader.new(StringIO.new(io.string))
        [r.orig_name, r.comment, r.mtime.to_i, r.os_code, r.read]
      end
      show("writer header is sealed by the first write") do
        io = StringIO.new("".b)
        w = Zlib::GzipWriter.new(io)
        w.write("x")
        w.orig_name = "too late"
      end
      show("writer print surface") do
        io = StringIO.new("".b)
        w = Zlib::GzipWriter.new(io)
        w.puts("a")
        w.print("b", "c")
        w.printf("%03d", 7)
        w.putc(?Z)
        w.close
        Zlib.gunzip(io.string)
      end
      show("writer pos and write") do
        io = StringIO.new("".b)
        w = Zlib::GzipWriter.new(io)
        n = w.write("hello")
        r = [n, w.pos, w.tell, w.crc, w.to_io.equal?(io), w.closed?]
        w.close
        r << w.closed?
      end
      show("writer level in the header") do
        io = StringIO.new("".b)
        Zlib::GzipWriter.wrap(io, Zlib::BEST_COMPRESSION) { |w| w.write(TEXT) }
        Zlib::GzipReader.new(StringIO.new(io.string)).level
      end
      show("writer accessors after close") do
        io = StringIO.new("".b)
        w = Zlib::GzipWriter.new(io)
        w.close
        w.crc
      end

    RUBY

    _(result).must_answer <<~'OUT'
      writer round-trip: "hello world"
      writer close answers the io: true
      writer wrap answers the block: [42, "wrapped"]
      writer header fields: ["f.txt", "a note", 1234567890, 3, "x"]
      writer header is sealed by the first write: Zlib::GzipFile::Error: header is already written
      writer print surface: "a\nbc007Z"
      writer pos and write: [5, 5, 5, 907060870, true, false, true]
      writer level in the header: 9
      writer accessors after close: Zlib::GzipFile::Error: closed gzip stream
    OUT
  end

  it "a GzipReader reads back the lines and the encoding it was given" do
    result = zr(<<~'RUBY')
      # zlib's class surface: the incremental `ZStream` pair and the IO-shaped gzip
      # pair. Nothing here prints a timestamp or a whole compressed buffer -- gzip
      # headers carry the current time, and deflate output is only guaranteed to
      # ROUND-TRIP, not to be byte-identical across zlib implementations.
      require "zlib"
      require "stringio"

      def show(label)
        print "#{label}: "
        p(yield)
      rescue => e
        puts "#{e.class}: #{e.message}"
      end

      TEXT = "the quick brown fox jumps over the lazy dog. " * 4

      # -- GzipWriter/GzipReader --------------------------------------------------

      GZ = Zlib.gzip("hello\nworld\n")

      show("reader read") { Zlib::GzipReader.new(StringIO.new(GZ)).read }
      show("reader read encoding") { Zlib::GzipReader.new(StringIO.new(GZ)).read.encoding.to_s }
      show("reader read(n) encoding") { Zlib::GzipReader.new(StringIO.new(GZ)).read(3).encoding.to_s }
      show("reader read(n)") do
        r = Zlib::GzipReader.new(StringIO.new(GZ))
        [r.read(3), r.read(3), r.read(100), r.read(3), r.read]
      end
      show("reader gets") do
        r = Zlib::GzipReader.new(StringIO.new(GZ))
        [r.gets, r.lineno, r.gets, r.gets]
      end
      show("reader gets with a separator") do
        r = Zlib::GzipReader.new(StringIO.new(GZ))
        [r.gets("o"), r.gets(nil)]
      end
      show("reader readlines") { Zlib::GzipReader.new(StringIO.new(GZ)).readlines }
      show("reader each_line") { Zlib::GzipReader.new(StringIO.new(GZ)).each_line.to_a }
      show("reader each is Enumerable's") { Zlib::GzipReader.new(StringIO.new(GZ)).map(&:chomp) }
      show("reader chars and bytes") do
        r = Zlib::GzipReader.new(StringIO.new(GZ))
        [r.getc, r.getbyte, r.readchar, r.readbyte]
      end
      show("reader each_byte") { Zlib::GzipReader.new(StringIO.new(Zlib.gzip("ab"))).each_byte.to_a }
      show("reader each_char") { Zlib::GzipReader.new(StringIO.new(Zlib.gzip("ab"))).each_char.to_a }
      show("reader ungetc") do
        r = Zlib::GzipReader.new(StringIO.new(GZ))
        c = r.getc
        r.ungetc(c)
        r.gets
      end
      show("reader readpartial") { Zlib::GzipReader.new(StringIO.new(GZ)).readpartial(4) }
      show("reader eof and pos") do
        r = Zlib::GzipReader.new(StringIO.new(GZ))
        before = r.eof?
        r.read
        [before, r.pos, r.eof?, r.eof]
      end
      show("reader readline past the end") do
        r = Zlib::GzipReader.new(StringIO.new(GZ))
        r.read
        r.readline
      end
      show("reader rewind") do
        r = Zlib::GzipReader.new(StringIO.new(GZ))
        r.read
        r.rewind
        r.gets
      end
      show("reader unused") do
        r = Zlib::GzipReader.new(StringIO.new(GZ + "EXTRA"))
        r.read
        r.unused
      end
      show("reader external_encoding") { Zlib::GzipReader.new(StringIO.new(GZ)).external_encoding.to_s }
      show("reader wrap") { Zlib::GzipReader.wrap(StringIO.new(GZ)) { |r| r.read } }
      show("reader zcat") { Zlib::GzipReader.zcat(StringIO.new(GZ + GZ)) }
      show("reader crc after reading") do
        r = Zlib::GzipReader.new(StringIO.new(GZ))
        r.read
        r.crc == Zlib.crc32("hello\nworld\n")
      end

    RUBY

    _(result).must_answer <<~'OUT'
      reader read: "hello\nworld\n"
      reader read encoding: "UTF-8"
      reader read(n) encoding: "ASCII-8BIT"
      reader read(n): ["hel", "lo\n", "world\n", nil, ""]
      reader gets: ["hello\n", 1, "world\n", nil]
      reader gets with a separator: ["hello", "\nworld\n"]
      reader readlines: ["hello\n", "world\n"]
      reader each_line: ["hello\n", "world\n"]
      reader each is Enumerable's: ["hello", "world"]
      reader chars and bytes: ["h", 101, "l", 108]
      reader each_byte: [97, 98]
      reader each_char: ["a", "b"]
      reader ungetc: "hello\n"
      reader readpartial: "hell"
      reader eof and pos: [false, 12, true, true]
      reader readline past the end: EOFError: end of file reached
      reader rewind: "hello\n"
      reader unused: "EXTRA"
      reader external_encoding: "UTF-8"
      reader wrap: "hello\nworld\n"
      reader zcat: "hello\nworld\nhello\nworld\n"
      reader crc after reading: true
    OUT
  end

  it "a file on disk round-trips through both halves" do
    result = zr(<<~'RUBY')
      # zlib's class surface: the incremental `ZStream` pair and the IO-shaped gzip
      # pair. Nothing here prints a timestamp or a whole compressed buffer -- gzip
      # headers carry the current time, and deflate output is only guaranteed to
      # ROUND-TRIP, not to be byte-identical across zlib implementations.
      require "zlib"
      require "stringio"

      def show(label)
        print "#{label}: "
        p(yield)
      rescue => e
        puts "#{e.class}: #{e.message}"
      end

      TEXT = "the quick brown fox jumps over the lazy dog. " * 4

      # -- GzipWriter/GzipReader --------------------------------------------------

      GZ = Zlib.gzip("hello\nworld\n")

      # A file on disk, through both halves.
      show("open round-trip") do
        Zlib::GzipWriter.open("zlib_classes_tmp.gz") { |w| w.write("through a file") }
        Zlib::GzipReader.open("zlib_classes_tmp.gz") { |r| r.read }
      ensure
        File.unlink("zlib_classes_tmp.gz")
      end

    RUBY

    _(result).must_answer <<~'OUT'
      open round-trip: "through a file"
    OUT
  end

  it "a corrupt member raises GzipFile::Error once the buffer it filled is read" do
    result = zr(<<~'RUBY')
      # zlib's class surface: the incremental `ZStream` pair and the IO-shaped gzip
      # pair. Nothing here prints a timestamp or a whole compressed buffer -- gzip
      # headers carry the current time, and deflate output is only guaranteed to
      # ROUND-TRIP, not to be byte-identical across zlib implementations.
      require "zlib"
      require "stringio"

      def show(label)
        print "#{label}: "
        p(yield)
      rescue => e
        puts "#{e.class}: #{e.message}"
      end

      TEXT = "the quick brown fox jumps over the lazy dog. " * 4

      # -- GzipWriter/GzipReader --------------------------------------------------

      GZ = Zlib.gzip("hello\nworld\n")

      # Corruption. CRuby checks a member's footer only once the buffer it filled
      # has been fully handed out, so `read` (which answers everything at once)
      # reports nothing and the line-at-a-time readers do -- reproduced faithfully.
      def corrupt(offset)
        bad = GZ.dup
        bad.setbyte(bad.bytesize + offset, GZ.getbyte(GZ.bytesize + offset) ^ 0xff)
        bad
      end
      show("not gzip at all") { Zlib::GzipReader.new(StringIO.new("not gzip at all")) }
      show("bad crc via read") { Zlib::GzipReader.new(StringIO.new(corrupt(-8))).read }
      show("bad crc via readlines") { Zlib::GzipReader.new(StringIO.new(corrupt(-8))).readlines }
      show("bad length via gunzip") { Zlib.gunzip(corrupt(-4)) }
      show("bad crc via gunzip") { Zlib.gunzip(corrupt(-8)) }
      show("truncated member") { Zlib::GzipReader.new(StringIO.new(GZ[0..15])).read }

    RUBY

    _(result).must_answer <<~'OUT'
      not gzip at all: Zlib::GzipFile::Error: not in gzip format
      bad crc via read: "hello\nworld\n"
      bad crc via readlines: Zlib::GzipFile::CRCError: invalid compressed data -- crc error
      bad length via gunzip: Zlib::GzipFile::LengthError: invalid compressed data -- length error
      bad crc via gunzip: Zlib::GzipFile::CRCError: invalid compressed data -- crc error
      truncated member: Zlib::GzipFile::Error: unexpected end of file
    OUT
  end

  it "the stream classes report a running crc32 and adler32" do
    result = zr(<<~'RUBY')
      # zlib's class surface: the incremental `ZStream` pair and the IO-shaped gzip
      # pair. Nothing here prints a timestamp or a whole compressed buffer -- gzip
      # headers carry the current time, and deflate output is only guaranteed to
      # ROUND-TRIP, not to be byte-identical across zlib implementations.
      require "zlib"
      require "stringio"

      def show(label)
        print "#{label}: "
        p(yield)
      rescue => e
        puts "#{e.class}: #{e.message}"
      end

      TEXT = "the quick brown fox jumps over the lazy dog. " * 4

      # -- Checksums --------------------------------------------------------------

      show("crc32") { [Zlib.crc32("abc"), Zlib.crc32, Zlib.crc32("abc", 100)] }
      show("adler32") { [Zlib.adler32("abc"), Zlib.adler32] }
      show("crc32 continued") { Zlib.crc32("def", Zlib.crc32("abc")) == Zlib.crc32("abcdef") }
    RUBY

    _(result).must_answer <<~'OUT'
      crc32: [891568578, 0, 2063213118]
      adler32: [38600999, 1]
      crc32 continued: true
    OUT
  end

  it "deflate and inflate round-trip at every level, and inflate reads any zlib's bytes" do
    result = zr(<<~'RUBY')
      require "zlib"

      # deflate / inflate round-trip (and inflate is byte-compatible with any zlib).
      text = "The quick brown fox jumps over the lazy dog. " * 3
      compressed = Zlib.deflate(text)
      p compressed.encoding.name
      p Zlib.inflate(compressed) == text
      p Zlib.inflate(compressed).length

      # Compression levels 0 (store) .. 9 (best) all round-trip.
      p [0, 1, 6, 9].map { |lvl| Zlib.inflate(Zlib.deflate(text, lvl)) == text }

      # gzip / gunzip round-trip.
      gz = Zlib.gzip(text)
      p Zlib.gunzip(gz) == text

      # inflate can read a stream produced by another zlib implementation.
      external = [120, 156, 203, 72, 205, 201, 201, 87, 40, 207, 47, 202, 73, 1, 0, 26, 11, 4, 93].pack("C*")
      p Zlib.inflate(external)
    RUBY

    _(result).must_answer <<~'OUT'
      "ASCII-8BIT"
      true
      135
      [true, true, true, true]
      true
      "hello world"
    OUT
  end

  it "require \"zlib\" brings up the constants, the stream classes and the exception classes" do
    result = zr(<<~'RUBY')
      # `require "zlib"` brings up the whole module: the 38 constants, the six
      # stream classes, and the thirteen exception classes the gem's Ruby half
      # defines. This is the shape check -- behaviour is in zlib_classes.rb.
      require "zlib"
      p Zlib.const_defined?(:Deflate)
      p Zlib.constants.sort
      p Zlib::GzipFile.constants.sort
      p [Zlib::Deflate.superclass, Zlib::Inflate.superclass, Zlib::GzipReader.superclass]
      p Zlib::GzipReader.ancestors.include?(Enumerable)
      p [Zlib::BufError.superclass, Zlib::Error.superclass, Zlib::GzipFile::CRCError.superclass]
    RUBY

    _(result).must_answer <<~'OUT'
      true
      [:ASCII, :BEST_COMPRESSION, :BEST_SPEED, :BINARY, :BufError, :DEFAULT_COMPRESSION, :DEFAULT_STRATEGY, :DEF_MEM_LEVEL, :DataError, :Deflate, :Error, :FILTERED, :FINISH, :FIXED, :FULL_FLUSH, :GzipFile, :GzipReader, :GzipWriter, :HUFFMAN_ONLY, :InProgressError, :Inflate, :MAX_MEM_LEVEL, :MAX_WBITS, :MemError, :NO_COMPRESSION, :NO_FLUSH, :NeedDict, :OS_AMIGA, :OS_ATARI, :OS_CODE, :OS_CPM, :OS_MACOS, :OS_MSDOS, :OS_OS2, :OS_QDOS, :OS_RISCOS, :OS_TOPS20, :OS_UNIX, :OS_UNKNOWN, :OS_VMCMS, :OS_VMS, :OS_WIN32, :OS_ZSYSTEM, :RLE, :SYNC_FLUSH, :StreamEnd, :StreamError, :TEXT, :UNKNOWN, :VERSION, :VersionError, :ZLIB_VERSION, :ZStream]
      [:CRCError, :Error, :LengthError, :NoFooter]
      [Zlib::ZStream, Zlib::ZStream, Zlib::GzipFile]
      true
      [Zlib::Error, StandardError, Zlib::GzipFile::Error]
    OUT
  end

  it "the compressor writes ruby's own bytes on every target" do
    result = zr(<<~'RUBY')
      # zlib on every target: the compressor writes ruby's bytes there too.
      require "zlib"
      text = ("wasm and native agree " * 30) + (0..127).to_a.pack("C*")
      [1, 6, 9].each do |level|
        puts "#{level}: #{Zlib::Deflate.deflate(text, level).unpack1("H*")}"
      end
      raw = Zlib::Deflate.new(6, -15).deflate(text, Zlib::FINISH)
      puts "raw: #{raw.bytesize} #{Zlib.crc32(raw)}"
      puts Zlib::Inflate.new(-15).inflate(raw) == text

    RUBY

    _(result).must_answer <<~'OUT'
      1: 78012b4f2cce5548cc4b51c84b2cc92c4b55484c2f4a4d55281f151d0d87014b0f0c8c4ccc2cac6cec1c9c5cdc3cbc7cfc028242c222a262e2129252d232b272f20a8a4aca2aaa6aea1a9a5ada3aba7afa068646c626a666e6169656d636b676f60e8e4ece2eae6eee1e9e5ede3ebe7efe018141c121a161e1119151d131b171f1098949c929a969e9199959d939b979f9058545c525a565e5159555d535b575f50079c10ea4
      6: 789c2b4f2cce5548cc4b51c84b2cc92c4b55484c2f4a4d55281f151d151d305106462666165636760e4e2e6e1e5e3e7e0141216111513171094929691959397905452565155535750d4d2d6d1d5d3d7d03432363135333730b4b2b6b1b5b3b7b07472767175737770f4f2f6f1f5f3fff80c0a0e090d0b0f088c8a8e898d8b8f884c4a4e494d4b4f48cccacec9cdcbcfc82c2a2e292d2b2f28acaaaea9adaba7a0079c10ea4
      9: 78da2b4f2cce5548cc4b51c84b2cc92c4b55484c2f4a4d55281f151d151d305106462666165636760e4e2e6e1e5e3e7e0141216111513171094929691959397905452565155535750d4d2d6d1d5d3d7d03432363135333730b4b2b6b1b5b3b7b07472767175737770f4f2f6f1f5f3fff80c0a0e090d0b0f088c8a8e898d8b8f884c4a4e494d4b4f48cccacec9cdcbcfc82c2a2e292d2b2f28acaaaea9adaba7a0079c10ea4
      raw: 159 4015053476
      true
    OUT
  end
end
