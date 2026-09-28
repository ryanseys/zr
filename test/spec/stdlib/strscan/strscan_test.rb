# frozen_string_literal: true

require "spec_helper"

describe "StringScanner programs" do
  it "loading the compiler leaves string and strscan alone" do
    result = zr(<<~'RUBY')
      # fileutils defines methods from strings, so the program carries the
      # compiler, and with it prism's polyfills. Each polyfill patches a core
      # class only when a method is missing or reports other parameters than
      # CRuby's, so none of them may fire.
      require "fileutils"
      require "strscan"

      p String.ancestors.first(2), StringScanner.ancestors.first(2)
      p Array.instance_method(:pack).parameters, String.instance_method(:unpack).parameters, String.instance_method(:unpack1).parameters
      p "xyz".unpack1("a", offset: 1), "ab".unpack("C*") { |b| p b }

      s = StringScanner.new("ab")
      p s.scan_byte, s.pos, s.matched, s.peek_byte, s.scan_byte, s.scan_byte

    RUBY

    _(result).must_answer <<~'OUT'
      [String, Comparable]
      [StringScanner, Object]
      [[:req, :fmt], [:key, :buffer]]
      [[:req, :fmt], [:key, :offset]]
      [[:req, :fmt], [:key, :offset]]
      97
      98
      "y"
      nil
      97
      1
      "a"
      98
      98
      nil
    OUT
  end

  it "regexp subclass is a pattern everywhere" do
    result = zr(<<~'RUBY')
      # `class X < Regexp` is a ValueSubclass husk wrapping a real Regexp. Unlike a
      # String or Array subclass, ruby has no conversion protocol for it, so every
      # site that takes a pattern has to see through the husk itself.

      # verbal_expressions' shape: build the source in `initialize`, seat it with
      # `super`.
      class MyRe < Regexp
        def initialize(src)
          super("(#{src})")
        end
      end

      r = MyRe.new("a+")
      p r.class
      p r.source
      p r.inspect
      p r.is_a?(Regexp)

      # As a RECEIVER -- the payload bridge answers these.
      p r =~ "xxaaay"
      p r.match("xxaaay")[0]
      p r.match?("xxaaay")
      p r === "xxaaay"

      # As an ARGUMENT, which is the half that needed the unwrapping.
      p "xxaaay" =~ r
      p "xxaaay".match(r)[1]
      p "xxaaay".match?(r)
      p "xxaaay"[r]
      p "xxaaay"[r, 1]
      p "xxaaay".gsub(r, "Z")
      p "xxaaay".sub(r) { |m| m.upcase }
      p "xxaaay".scan(r)
      p "a1a2a".split(r)
      p "xxaaay".index(r)
      p "xxaaay".rindex(r)
      p "xxaaay".byteindex(r)
      p "xxaaay".start_with?(MyRe.new("x"))
      p "xxaaay".partition(r)
      p "xxaaay".slice!(r)

      case "xxaaay"
      when r then p :matched
      else p :no
      end

      # Through the Regexp class methods.
      p Regexp.union(r, /b/)
      p Regexp.new(r).source
      p Regexp.linear_time?(r)

      # Identity and hashing go by pattern, but the object stays a MyRe.
      p r == /(a+)/
      p({ r => 1 }.keys.first.class)

      # riel's shape: override a match method and call `super`.
      class NegatedRegexp < Regexp
        def match(str)
          !super
        end
      end
      n = NegatedRegexp.new("z")
      p n.match("abc")
      p n.match("zoo")

      # The pattern reaches every OTHER pattern-taking site the same way.
      require 'strscan'
      p ["aaa", "b"].grep(r)
      p ["aaa", "b"].grep_v(r)
      sc = StringScanner.new("aaab")
      p sc.scan(r)
      p sc.check(MyRe.new("b"))
      p sc.skip(MyRe.new("b"))
      t = +"xxaaay"
      t[r] = "Z"
      p t
      p "aaa".rpartition(r)
      p Regexp.try_convert(r).class
      p r.hash == /(a+)/.hash
      p r.eql?(/(a+)/)
      # A subclass marshals as its own class, with the source and flags a bare
      # Regexp carries.
      p Marshal.load(Marshal.dump(r)).class
      p Marshal.load(Marshal.dump(r)).source
    RUBY

    _(result).must_answer <<~'OUT'
      MyRe
      "(a+)"
      "/(a+)/"
      true
      2
      "aaa"
      true
      true
      2
      "aaa"
      true
      "aaa"
      "aaa"
      "xxZy"
      "xxAAAy"
      [["aaa"]]
      ["", "a", "1", "a", "2", "a"]
      2
      4
      2
      true
      ["xx", "aaa", "y"]
      "aaa"
      :matched
      /(?-mix:(a+))|(?-mix:b)/
      "(a+)"
      true
      true
      MyRe
      true
      false
      ["aaa"]
      ["b"]
      "aaa"
      "b"
      1
      "xxZy"
      ["aa", "a", ""]
      MyRe
      true
      true
      MyRe
      "(a+)"
    OUT
  end

  it "an ivar in a method of a reopened builtin belongs to that object" do
    result = zr(<<~'RUBY')
      # An `@ivar` in a method of a reopened builtin.
      #
      # The ivar belongs to the receiver object, as in CRuby.
      #
      # The gems: strscan's own truffleruby shim keeps `@string`/`@pos` on
      # StringScanner, google-apis-generator and importmap-rails keep `@parent_name`
      # on Class, ffi keeps `@fixed` on VariadicInvoker, socksify `@socks_peer` on
      # TCPSocket.

      require "strscan"

      # A builtin whose instances keep ivars as a plain object does.
      class StringScanner
        def tag=(v)
          @tag = v
        end

        def tag
          @tag
        end
      end

      # An `@ivar` in a method of a reopened builtin.
      #
      # The ivar belongs to the receiver object, as in CRuby.
      #
      # The gems: strscan's own truffleruby shim keeps `@string`/`@pos` on
      # StringScanner, google-apis-generator and importmap-rails keep `@parent_name`
      # on Class, ffi keeps `@fixed` on VariadicInvoker, socksify `@socks_peer` on
      # TCPSocket.

      require "strscan"

      # A builtin whose instances keep ivars as a plain object does.
      class StringScanner
        def tag=(v)
          @tag = v
        end

        def tag
          @tag
        end
      end

      sc = StringScanner.new("hello world")
      sc.tag = :first
      p sc.tag
      # The native behaviour is untouched.
      p sc.scan(/hello/)
      p sc.rest

    RUBY

    _(result).must_answer <<~'OUT'
      :first
      "hello"
      " world"
    OUT
  end

  it "a fresh instance of the reopened builtin starts with the ivar unset" do
    result = zr(<<~'RUBY')
      # An `@ivar` in a method of a reopened builtin.
      #
      # The ivar belongs to the receiver object, as in CRuby.
      #
      # The gems: strscan's own truffleruby shim keeps `@string`/`@pos` on
      # StringScanner, google-apis-generator and importmap-rails keep `@parent_name`
      # on Class, ffi keeps `@fixed` on VariadicInvoker, socksify `@socks_peer` on
      # TCPSocket.

      require "strscan"

      # A builtin whose instances keep ivars as a plain object does.
      class StringScanner
        def tag=(v)
          @tag = v
        end

        def tag
          @tag
        end
      end

      sc = StringScanner.new("hello world")
      sc.tag = :first
      # The native behaviour is untouched.

      p StringScanner.new("x").tag

    RUBY

    _(result).must_answer <<~'OUT'
      nil
    OUT
  end

  it "reflection reaches the same storage the method bodies use" do
    result = zr(<<~'RUBY')
      # An `@ivar` in a method of a reopened builtin.
      #
      # The ivar belongs to the receiver object, as in CRuby.
      #
      # The gems: strscan's own truffleruby shim keeps `@string`/`@pos` on
      # StringScanner, google-apis-generator and importmap-rails keep `@parent_name`
      # on Class, ffi keeps `@fixed` on VariadicInvoker, socksify `@socks_peer` on
      # TCPSocket.

      require "strscan"

      # A builtin whose instances keep ivars as a plain object does.
      class StringScanner
        def tag=(v)
          @tag = v
        end

        def tag
          @tag
        end
      end

      sc = StringScanner.new("hello world")
      sc.tag = :first
      # The native behaviour is untouched.


      # Reflection reaches the same storage.
      p sc.instance_variables
      p sc.instance_variable_get(:@tag)
      sc.instance_variable_set(:@tag, :second)
      p sc.tag
      p sc.remove_instance_variable(:@tag)
      p sc.instance_variables

    RUBY

    _(result).must_answer <<~'OUT'
      [:@tag]
      :first
      :second
      :second
      []
    OUT
  end

  it "a class object carries its own ivars, keyed by the class" do
    result = zr(<<~'RUBY')
      # An `@ivar` in a method of a reopened builtin.
      #
      # The ivar belongs to the receiver object, as in CRuby.
      #
      # The gems: strscan's own truffleruby shim keeps `@string`/`@pos` on
      # StringScanner, google-apis-generator and importmap-rails keep `@parent_name`
      # on Class, ffi keeps `@fixed` on VariadicInvoker, socksify `@socks_peer` on
      # TCPSocket.

      require "strscan"

      # A builtin whose instances keep ivars as a plain object does.
      class StringScanner
        def tag=(v)
          @tag = v
        end

        def tag
          @tag
        end
      end

      sc = StringScanner.new("hello world")
      sc.tag = :first
      # The native behaviour is untouched.


      # Reflection reaches the same storage.
      sc.instance_variable_set(:@tag, :second)

      # A CLASS object: `civars`, keyed `(class_id, name)`.
      class Class
        def parent_name=(v)
          @parent_name = v
        end

        def parent_name
          @parent_name
        end
      end

      class Widget; end
      class Gadget; end

      # A CLASS object: `civars`, keyed `(class_id, name)`.
      class Class
        def parent_name=(v)
          @parent_name = v
        end

        def parent_name
          @parent_name
        end
      end

      class Widget; end
      class Gadget; end

      Widget.parent_name = "Assembly"
      p Widget.parent_name
      p Gadget.parent_name

    RUBY

    _(result).must_answer <<~'OUT'
      "Assembly"
      nil
    OUT
  end

  it "a bare heap value carries an ivar in the identity-keyed side table" do
    result = zr(<<~'RUBY')
      # An `@ivar` in a method of a reopened builtin.
      #
      # The ivar belongs to the receiver object, as in CRuby.
      #
      # The gems: strscan's own truffleruby shim keeps `@string`/`@pos` on
      # StringScanner, google-apis-generator and importmap-rails keep `@parent_name`
      # on Class, ffi keeps `@fixed` on VariadicInvoker, socksify `@socks_peer` on
      # TCPSocket.

      require "strscan"

      # A builtin whose instances keep ivars as a plain object does.
      class StringScanner
        def tag=(v)
          @tag = v
        end

        def tag
          @tag
        end
      end

      sc = StringScanner.new("hello world")
      sc.tag = :first
      # The native behaviour is untouched.


      # Reflection reaches the same storage.
      sc.instance_variable_set(:@tag, :second)

      # A CLASS object: `civars`, keyed `(class_id, name)`.
      class Class
        def parent_name=(v)
          @parent_name = v
        end

        def parent_name
          @parent_name
        end
      end

      class Widget; end
      class Gadget; end

      Widget.parent_name = "Assembly"

      # A bare heap value: `value_ivars`' identity-keyed side table.
      class Array
        def label=(v)
          @label = v
        end

        def label
          @label
        end
      end

      # A bare heap value: `value_ivars`' identity-keyed side table.
      class Array
        def label=(v)
          @label = v
        end

        def label
          @label
        end
      end

      xs = [1, 2, 3]
      ys = [1, 2, 3]
      xs.label = "counted"
      p xs.label
      # Identity, not equality -- `ys == xs` yet carries nothing.
      p ys.label
      p xs

    RUBY

    _(result).must_answer <<~'OUT'
      "counted"
      nil
      [1, 2, 3]
    OUT
  end

  it "two values of one class keep their ivars apart" do
    result = zr(<<~'RUBY')
      # An `@ivar` in a method of a reopened builtin.
      #
      # The ivar belongs to the receiver object, as in CRuby.
      #
      # The gems: strscan's own truffleruby shim keeps `@string`/`@pos` on
      # StringScanner, google-apis-generator and importmap-rails keep `@parent_name`
      # on Class, ffi keeps `@fixed` on VariadicInvoker, socksify `@socks_peer` on
      # TCPSocket.

      require "strscan"

      # A builtin whose instances keep ivars as a plain object does.
      class StringScanner
        def tag=(v)
          @tag = v
        end

        def tag
          @tag
        end
      end

      sc = StringScanner.new("hello world")
      sc.tag = :first
      # The native behaviour is untouched.


      # Reflection reaches the same storage.
      sc.instance_variable_set(:@tag, :second)

      # A CLASS object: `civars`, keyed `(class_id, name)`.
      class Class
        def parent_name=(v)
          @parent_name = v
        end

        def parent_name
          @parent_name
        end
      end

      class Widget; end
      class Gadget; end

      Widget.parent_name = "Assembly"

      # A bare heap value: `value_ivars`' identity-keyed side table.
      class Array
        def label=(v)
          @label = v
        end

        def label
          @label
        end
      end

      xs = [1, 2, 3]
      ys = [1, 2, 3]
      xs.label = "counted"
      # Identity, not equality -- `ys == xs` yet carries nothing.

      class String
        def note=(v)
          @note = v
        end

        def note
          @note
        end
      end

      class String
        def note=(v)
          @note = v
        end

        def note
          @note
        end
      end

      s = +"hi"
      s.note = 9
      p s.note
      p s.upcase

    RUBY

    _(result).must_answer <<~'OUT'
      9
      "HI"
    OUT
  end

  it "a method defined on the reopened builtin reaches the same storage" do
    result = zr(<<~'RUBY')
      # An `@ivar` in a method of a reopened builtin.
      #
      # The ivar belongs to the receiver object, as in CRuby.
      #
      # The gems: strscan's own truffleruby shim keeps `@string`/`@pos` on
      # StringScanner, google-apis-generator and importmap-rails keep `@parent_name`
      # on Class, ffi keeps `@fixed` on VariadicInvoker, socksify `@socks_peer` on
      # TCPSocket.

      require "strscan"

      # A builtin whose instances keep ivars as a plain object does.
      class StringScanner
        def tag=(v)
          @tag = v
        end

        def tag
          @tag
        end
      end

      sc = StringScanner.new("hello world")
      sc.tag = :first
      # The native behaviour is untouched.


      # Reflection reaches the same storage.
      sc.instance_variable_set(:@tag, :second)

      # A CLASS object: `civars`, keyed `(class_id, name)`.
      class Class
        def parent_name=(v)
          @parent_name = v
        end

        def parent_name
          @parent_name
        end
      end

      class Widget; end
      class Gadget; end

      Widget.parent_name = "Assembly"

      # A bare heap value: `value_ivars`' identity-keyed side table.
      class Array
        def label=(v)
          @label = v
        end

        def label
          @label
        end
      end

      xs = [1, 2, 3]
      ys = [1, 2, 3]
      xs.label = "counted"
      # Identity, not equality -- `ys == xs` yet carries nothing.

      class String
        def note=(v)
          @note = v
        end

        def note
          @note
        end
      end

      s = +"hi"
      s.note = 9

      # Reaching the same storage through a method defined on the reopened builtin
      # rather than at the call site, so the read and the write cross a call boundary.
      class Array
        def bump
          @label = "#{@label}!"
          self
        end
      end

      # Reaching the same storage through a method defined on the reopened builtin
      # rather than at the call site, so the read and the write cross a call boundary.
      class Array
        def bump
          @label = "#{@label}!"
          self
        end
      end

      p xs.bump.label
    RUBY

    _(result).must_answer <<~'OUT'
      "counted!"
    OUT
  end

  it "scanner walks wide and legacy text by characters" do
    result = zr(<<~'RUBY')
      # A StringScanner over UTF-16, UTF-32 or a legacy multibyte text scans
      # with patterns of the text's encoding, steps a character at a time
      # with getch, and reports byte positions and character positions apart.
      require "strscan"

      def shown(v)
        case v
        when String then v.valid_encoding? && v.encoding != Encoding::BINARY ? [v.encoding.name, v.encode("UTF-8")] : [v.encoding.name, v.b]
        when Array then v.map { |x| shown(x) }
        else v
        end
      end

      def show(label)
        p [label, shown(yield)]
      rescue StandardError => e
        p [label, e.class, e.message.b]
      end

      %w[UTF-16LE UTF-16BE UTF-32LE UTF-32BE GB18030 EUC-JP Shift_JIS Big5 EUC-KR CESU-8].each do |name|
        e = ->(s) { s.encode(name) }
        r = ->(s) { Regexp.new(e.(s)) }
        sample = name.start_with?("EUC-JP", "Shift") ? "カナ 表示 end" : (name == "Big5" ? "中文 測試 end" : (name == "EUC-KR" ? "한국 세계 end" : "Grüße 世界😀 end"))
        show(:"#{name}_scan") do
          s = StringScanner.new(e.(sample))
          [s.scan(r.("\\S+")), s.pos, s.charpos, s.matched, s.matched_size, s.pre_match, s.skip(r.("\\s+")), s.check(r.("\\S")), s.rest_size]
        end
        show(:"#{name}_getch") do
          s = StringScanner.new(e.(sample))
          [s.getch, s.getch, s.get_byte, s.pos, s.charpos, s.peek(2).bytesize, s.rest.encoding]
        end
        show(:"#{name}_until") do
          s = StringScanner.new(e.(sample))
          [s.scan_until(r.("\\s")), s.pos, s.charpos, s.search_full(r.("e"), false, false), s.exist?(r.("d")), s.check_until(r.("d$")), s.eos?]
        end
        show(:"#{name}_groups") do
          s = StringScanner.new(e.(sample))
          s.scan(r.("(?<a>\\S)(\\S)"))
          [s[1], s[:a], s.captures, s.values_at(0, 2), s.size, s.named_captures]
        end
        show(:"#{name}_string_pattern") do
          s = StringScanner.new(e.(sample))
          [s.scan(e.(sample[0, 2])), s.pos, s.skip_until(e.("e")), s.charpos, s.scan_until(e.("d")), s.pos]
        end
        show(:"#{name}_unscan") do
          s = StringScanner.new(e.(sample))
          s.scan(r.("\\S+"))
          s.unscan
          s.pos = 2 * e.("a").bytesize
          [s.pos, s.charpos, s.getch, s.inspect.b]
        end
      end

    RUBY

    _(result).must_answer <<~'OUT'
      [:"UTF-16LE_scan", [["UTF-16LE", "Grüße"], 10, 5, ["UTF-16LE", "Grüße"], 10, ["UTF-16LE", ""], 2, ["UTF-16LE", "世"], 16]]
      [:"UTF-16LE_getch", [["UTF-16LE", "G"], ["UTF-16LE", "r"], ["UTF-16LE", "\xFC"], 5, 3, 2, #<Encoding:UTF-16LE>]]
      [:"UTF-16LE_until", [["UTF-16LE", "Grüße "], 12, 6, 12, 16, ["UTF-16LE", "世界😀 end"], false]]
      [:"UTF-16LE_groups", IndexError, "undefined group name reference: a"]
      [:"UTF-16LE_string_pattern", [["UTF-16LE", "Gr"], 4, 6, 5, ["UTF-16LE", " 世界😀 end"], 28]]
      [:"UTF-16LE_unscan", [4, 2, ["UTF-16LE", "ü"], ["ASCII-8BIT", "#<StringScanner 6/28 \"...\\x00r\\x00\\xFC\\x00\" @ \"\\xDF\\x00e\\x00 ...\">"]]]
      [:"UTF-16BE_scan", [["UTF-16BE", "Grüße"], 10, 5, ["UTF-16BE", "Grüße"], 10, ["UTF-16BE", ""], 2, ["UTF-16BE", "世"], 16]]
      [:"UTF-16BE_getch", [["UTF-16BE", "G"], ["UTF-16BE", "r"], ["UTF-16BE", "\x00"], 5, 3, 2, #<Encoding:UTF-16BE>]]
      [:"UTF-16BE_until", [["UTF-16BE", "Grüße "], 12, 6, 12, 16, ["UTF-16BE", "世界😀 end"], false]]
      [:"UTF-16BE_groups", IndexError, "undefined group name reference: a"]
      [:"UTF-16BE_string_pattern", [["UTF-16BE", "Gr"], 4, 6, 5, ["UTF-16BE", " 世界😀 end"], 28]]
      [:"UTF-16BE_unscan", [4, 2, ["UTF-16BE", "ü"], ["ASCII-8BIT", "#<StringScanner 6/28 \"...G\\x00r\\x00\\xFC\" @ \"\\x00\\xDF\\x00e\\x00...\">"]]]
      [:"UTF-32LE_scan", [["UTF-32LE", "Grüße"], 20, 5, ["UTF-32LE", "Grüße"], 20, ["UTF-32LE", ""], 4, ["UTF-32LE", "世"], 28]]
      [:"UTF-32LE_getch", [["UTF-32LE", "G"], ["UTF-32LE", "r"], ["UTF-32LE", "\xFC"], 9, 3, 2, #<Encoding:UTF-32LE>]]
      [:"UTF-32LE_until", [["UTF-32LE", "Grüße "], 24, 6, 20, 28, ["UTF-32LE", "世界😀 end"], false]]
      [:"UTF-32LE_groups", IndexError, "undefined group name reference: a"]
      [:"UTF-32LE_string_pattern", [["UTF-32LE", "Gr"], 8, 12, 5, ["UTF-32LE", " 世界😀 end"], 52]]
      [:"UTF-32LE_unscan", [8, 2, ["UTF-32LE", "ü"], ["ASCII-8BIT", "#<StringScanner 12/52 \"...\\x00\\xFC\\x00\\x00\\x00\" @ \"\\xDF\\x00\\x00\\x00e...\">"]]]
      [:"UTF-32BE_scan", [["UTF-32BE", "Grüße"], 20, 5, ["UTF-32BE", "Grüße"], 20, ["UTF-32BE", ""], 4, ["UTF-32BE", "世"], 28]]
      [:"UTF-32BE_getch", [["UTF-32BE", "G"], ["UTF-32BE", "r"], ["UTF-32BE", "\x00"], 9, 3, 2, #<Encoding:UTF-32BE>]]
      [:"UTF-32BE_until", [["UTF-32BE", "Grüße "], 24, 6, 20, 28, ["UTF-32BE", "世界😀 end"], false]]
      [:"UTF-32BE_groups", IndexError, "undefined group name reference: a"]
      [:"UTF-32BE_string_pattern", [["UTF-32BE", "Gr"], 8, 12, 5, ["UTF-32BE", " 世界😀 end"], 52]]
      [:"UTF-32BE_unscan", [8, 2, ["UTF-32BE", "ü"], ["ASCII-8BIT", "#<StringScanner 12/52 \"...r\\x00\\x00\\x00\\xFC\" @ \"\\x00\\x00\\x00\\xDF\\x00...\">"]]]
      [:GB18030_scan, [["GB18030", "Grüße"], 9, 5, ["GB18030", "Grüße"], 9, ["GB18030", ""], 1, ["GB18030", "世"], 12]]
      [:GB18030_getch, [["GB18030", "G"], ["GB18030", "r"], ["GB18030", "\xA8"], 3, 3, 2, #<Encoding:GB18030>]]
      [:GB18030_until, [["GB18030", "Grüße "], 10, 6, 10, 12, ["GB18030", "世界😀 end"], false]]
      [:GB18030_groups, [["GB18030", "G"], ["GB18030", "G"], [["GB18030", "G"]], [["GB18030", "Gr"], nil], 2, {"a" => "G"}]]
      [:GB18030_string_pattern, [["GB18030", "Gr"], 2, 7, 5, ["GB18030", " 世界😀 end"], 22]]
      [:GB18030_unscan, [2, 2, ["GB18030", "ü"], ["ASCII-8BIT", "#<StringScanner 4/22 \"Gr\\xA8\\xB9\" @ \"\\x810\\x898e...\">"]]]
      [:"EUC-JP_scan", [["EUC-JP", "カナ"], 4, 2, ["EUC-JP", "カナ"], 4, ["EUC-JP", ""], 1, ["EUC-JP", "表"], 8]]
      [:"EUC-JP_getch", [["EUC-JP", "カ"], ["EUC-JP", "ナ"], ["EUC-JP", " "], 5, 3, 2, #<Encoding:EUC-JP>]]
      [:"EUC-JP_until", [["EUC-JP", "カナ "], 5, 3, 6, 8, ["EUC-JP", "表示 end"], false]]
      [:"EUC-JP_groups", [["EUC-JP", "カ"], ["EUC-JP", "カ"], [["EUC-JP", "カ"]], [["EUC-JP", "カナ"], nil], 2, {"a" => "\x{A5AB}"}]]
      [:"EUC-JP_string_pattern", [["EUC-JP", "カナ"], 4, 7, 7, ["EUC-JP", "nd"], 13]]
      [:"EUC-JP_unscan", [2, 1, ["EUC-JP", "ナ"], ["ASCII-8BIT", "#<StringScanner 4/13 \"\\xA5\\xAB\\xA5\\xCA\" @ \" \\xC9\\xBD\\xBC\\xA8...\">"]]]
      [:Shift_JIS_scan, [["Shift_JIS", "カナ"], 4, 2, ["Shift_JIS", "カナ"], 4, ["Shift_JIS", ""], 1, ["Shift_JIS", "表"], 8]]
      [:Shift_JIS_getch, [["Shift_JIS", "カ"], ["Shift_JIS", "ナ"], ["Shift_JIS", " "], 5, 3, 2, #<Encoding:Shift_JIS>]]
      [:Shift_JIS_until, [["Shift_JIS", "カナ "], 5, 3, 6, 8, ["Shift_JIS", "表示 end"], false]]
      [:Shift_JIS_groups, [["Shift_JIS", "カ"], ["Shift_JIS", "カ"], [["Shift_JIS", "カ"]], [["Shift_JIS", "カナ"], nil], 2, {"a" => "\x{834A}"}]]
      [:Shift_JIS_string_pattern, [["Shift_JIS", "カナ"], 4, 7, 7, ["Shift_JIS", "nd"], 13]]
      [:Shift_JIS_unscan, [2, 1, ["Shift_JIS", "ナ"], ["ASCII-8BIT", "#<StringScanner 4/13 \"\\x83J\\x83i\" @ \" \\x95\\\\\\x8E\\xA6...\">"]]]
      [:Big5_scan, [["Big5", "中文"], 4, 2, ["Big5", "中文"], 4, ["Big5", ""], 1, ["Big5", "測"], 8]]
      [:Big5_getch, [["Big5", "中"], ["Big5", "文"], ["Big5", " "], 5, 3, 2, #<Encoding:Big5>]]
      [:Big5_until, [["Big5", "中文 "], 5, 3, 6, 8, ["Big5", "測試 end"], false]]
      [:Big5_groups, [["Big5", "中"], ["Big5", "中"], [["Big5", "中"]], [["Big5", "中文"], nil], 2, {"a" => "\x{A4A4}"}]]
      [:Big5_string_pattern, [["Big5", "中文"], 4, 7, 7, ["Big5", "nd"], 13]]
      [:Big5_unscan, [2, 1, ["Big5", "文"], ["ASCII-8BIT", "#<StringScanner 4/13 \"\\xA4\\xA4\\xA4\\xE5\" @ \" \\xB4\\xFA\\xB8\\xD5...\">"]]]
      [:"EUC-KR_scan", [["EUC-KR", "한국"], 4, 2, ["EUC-KR", "한국"], 4, ["EUC-KR", ""], 1, ["EUC-KR", "세"], 8]]
      [:"EUC-KR_getch", [["EUC-KR", "한"], ["EUC-KR", "국"], ["EUC-KR", " "], 5, 3, 2, #<Encoding:EUC-KR>]]
      [:"EUC-KR_until", [["EUC-KR", "한국 "], 5, 3, 6, 8, ["EUC-KR", "세계 end"], false]]
      [:"EUC-KR_groups", [["EUC-KR", "한"], ["EUC-KR", "한"], [["EUC-KR", "한"]], [["EUC-KR", "한국"], nil], 2, {"a" => "\x{C7D1}"}]]
      [:"EUC-KR_string_pattern", [["EUC-KR", "한국"], 4, 7, 7, ["EUC-KR", "nd"], 13]]
      [:"EUC-KR_unscan", [2, 1, ["EUC-KR", "국"], ["ASCII-8BIT", "#<StringScanner 4/13 \"\\xC7\\xD1\\xB1\\xB9\" @ \" \\xBC\\xBC\\xB0\\xE8...\">"]]]
      [:"CESU-8_scan", [["CESU-8", "Grüße"], 7, 5, ["CESU-8", "Grüße"], 7, ["CESU-8", ""], 1, ["CESU-8", "世"], 16]]
      [:"CESU-8_getch", [["CESU-8", "G"], ["CESU-8", "r"], ["CESU-8", "\xC3"], 3, 3, 2, #<Encoding:CESU-8>]]
      [:"CESU-8_until", [["CESU-8", "Grüße "], 8, 6, 14, 16, ["CESU-8", "世界😀 end"], false]]
      [:"CESU-8_groups", [["CESU-8", "G"], ["CESU-8", "G"], [["CESU-8", "G"]], [["CESU-8", "Gr"], nil], 2, {"a" => "G"}]]
      [:"CESU-8_string_pattern", [["CESU-8", "Gr"], 2, 5, 5, ["CESU-8", " 世界😀 end"], 24]]
      [:"CESU-8_unscan", [2, 2, ["CESU-8", "ü"], ["ASCII-8BIT", "#<StringScanner 4/24 \"Gr\\xC3\\xBC\" @ \"\\xC3\\x9Fe \\xE4...\">"]]]
    OUT
  end

  it "string scanner answers the same off either implementation" do
    result = zr(<<~'RUBY')
      require "strscan"

      def t(label)
        print label, ": "
        p yield
      rescue => e
        puts "#{e.class}: #{e.message}"
      end

      s = StringScanner.new("This is an example string")
      t("bol0") { s.beginning_of_line? }
      t("eos0") { s.eos? }
      t("scan1") { s.scan(/\w+/) }
      t("scan2") { s.scan(/\w+/) }
      t("scan3") { s.scan(/\s+/) }
      t("pre") { s.pre_match }
      t("post") { s.post_match }
      t("matched") { s.matched }
      t("msize") { s.matched_size }
      t("pos") { s.pos }
      t("charpos") { s.charpos }
      t("bol") { s.beginning_of_line? }
      t("rest") { s.rest }
      t("restq") { s.rest? }
      t("unscan") { s.unscan; [s.pos, s.matched] }
      t("skip") { s.skip(/\s+is\s+/) }
      t("checku") { s.check_until(/example/) }
      t("posu") { s.pos }
      t("scanu") { s.scan_until(/example/) }
      t("preu") { s.pre_match }
      t("postu") { s.post_match }
      t("exist") { s.exist?(/str/) }
      t("skipu") { s.skip_until(/str/) }
      t("m?") { s.match?(/ing/) }
      t("check") { s.check(/ing/) }
      t("getch") { s.getch }
      t("getbyte") { s.get_byte }
      t("scanbyte") { s.scan_byte }
      t("peek") { s.peek(20) }
      t("peekb") { s.peek_byte }
      t("eos") { s.eos? }
      t("scaneos") { s.scan(/x/) }
      t("terminate") { s.terminate; [s.pos, s.eos?] }
      t("reset") { s.reset; [s.pos, s.matched?] }

      # String patterns leave real match state.
      t("strscan") { s.scan("This") }
      t("strm") { [s.matched, s.pre_match, s.post_match, s[0], s.size] }
      t("strmiss") { s.scan("nope") }
      t("strafter") { s.matched? }
      t("struntil") { s.scan_until(" an") }
      t("strupre") { s.pre_match }

      # Captures and names.
      s2 = StringScanner.new("Fri Dec 12 1975")
      t("caps") { s2.scan(/(?<wday>\w+) (?<month>\w+) (?<day>\d+)/) }
      t("bracket0") { s2[0] }
      t("name") { [s2[:wday], s2["month"]] }
      t("named") { s2.named_captures }
      t("capsarr") { s2.captures }
      t("vals") { s2.values_at(0, 2, -1) }
      t("sizec") { s2.size }
      t("rangeidx") { s2[0..1] }

      # Anchoring semantics: \A means the position in default mode.
      s3 = StringScanner.new("abc def")
      s3.pos = 4
      t("anchorA") { s3.scan(/\Adef/) }
      t("caret") { s3.scan(/^def/) }
      s3.pos = 3
      t("caret_mid") { s3.scan(/^\s/) }

      # fixed_anchor: \A means the string head; \G the position.
      f = StringScanner.new("abc def", fixed_anchor: true)
      f.pos = 4
      t("fixedA") { f.scan(/\Adef/) }
      t("fixedG") { f.scan(/def/) }
      t("fixedpre") { f.pre_match }
      t("fixedpost") { f.post_match }

      # Multibyte: positions are bytes.
      u = StringScanner.new("héllo wörld")
      t("uscan") { u.scan(/h\Sllo/) }
      t("upos") { u.pos }
      t("ucharpos") { u.charpos }
      t("upeek") { u.peek(3) }
      t("uget") { u.scan(/\s/) && u.getch }
      t("upos2") { [u.pos, u.charpos] }

      # Growth and replacement.
      g = StringScanner.new(+"ab")
      t("concat") { g << "cd"; g.string }
      t("seteq") { g.string = "xyz"; [g.pos, g.string] }
      t("posneg") { g.pos = -2; g.pos }
      t("posrange") { g.pos = 99 }

      # Errors.
      e = StringScanner.new("q")
      t("unscanerr") { e.unscan }
      t("peekneg") { e.peek(-1) }
      t("scaninty") { StringScanner.new("123abc").scan_integer }
      t("scanint16") { StringScanner.new("0xffz", fixed_anchor: false).scan_integer(base: 16) }
      t("inspect0") { StringScanner.new("test string").inspect }
      t("inspectmid") { w = StringScanner.new("test string"); w.scan(/test /); w.inspect }
      t("inspectfin") { w = StringScanner.new("t"); w.scan(/t/); w.inspect }
    RUBY

    _(result).must_answer <<~'OUT'
      bol0: true
      eos0: false
      scan1: "This"
      scan2: nil
      scan3: " "
      pre: "This"
      post: "is an example string"
      matched: " "
      msize: 1
      pos: 5
      charpos: 5
      bol: false
      rest: "is an example string"
      restq: true
      unscan: [4, nil]
      skip: 4
      checku: "an example"
      posu: 8
      scanu: "an example"
      preu: "This is an "
      postu: " string"
      exist: 4
      skipu: 4
      m?: 3
      check: "ing"
      getch: "i"
      getbyte: "n"
      scanbyte: 103
      peek: ""
      peekb: nil
      eos: true
      scaneos: nil
      terminate: [25, true]
      reset: [0, false]
      strscan: "This"
      strm: ["This", "", " is an example string", "This", 1]
      strmiss: nil
      strafter: false
      struntil: " is an"
      strupre: "This is"
      caps: "Fri Dec 12"
      bracket0: "Fri Dec 12"
      name: ["Fri", "Dec"]
      named: {"wday" => "Fri", "month" => "Dec", "day" => "12"}
      capsarr: ["Fri", "Dec", "12"]
      vals: ["Fri Dec 12", "Dec", "12"]
      sizec: 4
      rangeidx: TypeError: no implicit conversion of Range into Integer
      anchorA: "def"
      caret: nil
      caret_mid: " "
      fixedA: nil
      fixedG: "def"
      fixedpre: "abc "
      fixedpost: ""
      uscan: "héllo"
      upos: 6
      ucharpos: 5
      upeek: " w\xC3"
      uget: "w"
      upos2: [8, 7]
      concat: "abcd"
      seteq: [0, "xyz"]
      posneg: 1
      posrange: RangeError: index out of range
      unscanerr: StringScanner::Error: unscan failed: previous match record not exist
      peekneg: ArgumentError: negative string size (or size too big)
      scaninty: 123
      scanint16: 255
      inspect0: "#<StringScanner 0/11 @ \"test ...\">"
      inspectmid: "#<StringScanner 5/11 \"test \" @ \"strin...\">"
      inspectfin: "#<StringScanner fin>"
    OUT
  end

  it "string scanner matches in place" do
    result = zr(<<~'RUBY')
      # StringScanner matches its pattern at the scan pointer. CRuby hands the
      # compiled pattern the text and the pointer; here each scan copies the
      # rest of the text and compiles the pattern again behind a \A, so a
      # tokenizer over a long text is quadratic in its length.
      require "strscan"
      src = "foo = bar(12, 'baz') + 3.5 * qux # note\n" * 5_000
      count = 0
      ss = StringScanner.new(src)
      until ss.eos?
        if ss.skip(/\s+/) then next
        elsif ss.scan(/[a-z_]\w*/) then count += 1
        elsif ss.scan(/\d+(\.\d+)?/) then count += 1
        elsif ss.scan(/'[^']*'/) then count += 1
        elsif ss.scan(/#.*$/) then count += 1
        else ss.getch; count += 1
        end
      end
      p count

    RUBY

    _(result).must_answer "65000\n"
  end

  it "strscan bytes and bounds" do
    result = zr(<<~'RUBY')
      # Two StringScanner rows: `get_byte` answers the RAW byte (zr converts
      # through lossy UTF-8 and answers the replacement character for each
      # half of a multibyte char -- data corruption, the to_utf8_lossy
      # family), and `pos=` past the end raises RangeError ("index out of
      # range"). (Found by the 2026-08-24 probe sweep.)
      require "strscan"
      s = StringScanner.new("é")
      p s.get_byte.bytes
      p s.get_byte.bytes
      begin
        t = StringScanner.new("ab")
        t.pos = 99
        p t.pos
      rescue RangeError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [195]
      [169]
      index out of range
    OUT
  end

  it "strscan capture surface" do
    result = zr(<<~'RUBY')
      require "strscan"

      s = StringScanner.new("name=zr; version=4")
      p s.scan(/(\w+)=(\w+)/)
      p s[0], s[1], s[2], s[-1], s[9]
      p s.captures
      p s.values_at(0, 2, 7)
      p s.size
      p s.matched_size
      p s.pre_match, s.post_match

      named = StringScanner.new("2026-07-28")
      named.scan(/(?<y>\d{4})-(?<m>\d{2})/)
      p named[:y], named["m"]
      p named.named_captures
      begin
        named[:nope]
      rescue IndexError => e
        puts e.message
      end

      # A miss clears every register.
      miss = StringScanner.new("abc")
      miss.scan(/(a)/)
      p miss.scan(/\d/)
      p miss.matched?, miss.matched, miss.captures, miss.size, miss.matched_size
      p miss[0]

      # Positions: `pos` counts bytes, `charpos` counts characters.
      multi = StringScanner.new("héllo wörld")
      multi.scan(/h.l+o/)
      p multi.pos, multi.charpos, multi.rest_size, multi.rest?
      p multi.pointer
      multi.pointer = 0
      p multi.pos

      p StringScanner.new("abc").inspect
      p StringScanner.new("").inspect
      spent = StringScanner.new("abc")
      spent.terminate
      p spent.inspect
      long = StringScanner.new("a" * 30)
      long.scan(/a{5}/)
      p long.inspect

      # The `*_full` primitives, and the two length-returning walkers.
      full = StringScanner.new("hello")
      p full.scan_full(/he/, false, true), full.pos
      p full.scan_full(/he/, true, false), full.pos
      p full.search_full(/ll/, true, true), full.pos

      p StringScanner.new("abc;def").skip_until(/;/)
      p StringScanner.new("abc").skip_until(/;/)

      # Byte-level reads.
      bytes = StringScanner.new("Zx")
      p bytes.peek_byte, bytes.scan_byte, bytes.scan_byte, bytes.scan_byte
      p StringScanner.new("+12ab").scan_integer
      p StringScanner.new("-0x1f").scan_integer(base: 16)
      p StringScanner.new("ab").scan_integer

      # Appending feeds a scanner incrementally; replacing restarts it.
      feed = StringScanner.new("ab")
      feed.scan(/a/)
      feed << "cd"
      p feed.string, feed.pos
      feed.string = "zz"
      p feed.string, feed.pos
      p feed.fixed_anchor?
      p StringScanner.new("x", fixed_anchor: true).fixed_anchor?
    RUBY

    _(result).must_answer <<~'OUT'
      "name=zr"
      "name=zr"
      "name"
      "zr"
      "zr"
      nil
      ["name", "zr"]
      ["name=zr", "zr", nil]
      3
      7
      ""
      "; version=4"
      "2026"
      "07"
      {"y" => "2026", "m" => "07"}
      undefined group name reference: nope
      nil
      false
      nil
      nil
      nil
      nil
      nil
      6
      5
      7
      true
      6
      0
      "#<StringScanner 0/3 @ \"abc\">"
      "#<StringScanner fin>"
      "#<StringScanner fin>"
      "#<StringScanner 5/30 \"aaaaa\" @ \"aaaaa...\">"
      "he"
      0
      2
      2
      "ll"
      4
      4
      nil
      90
      90
      120
      nil
      12
      -31
      nil
      "abcd"
      1
      "zz"
      0
      false
      true
    OUT
  end

  it "strscan lookahead" do
    result = zr(<<~'RUBY')
      require "strscan"

      s = StringScanner.new("test string")

      # exist? looks ahead without advancing: bytes from here to the match end.
      p s.exist?(/s/)
      p s.pos

      # check_until peeks up to and including the next match (no advance).
      p s.check_until(/str/)
      p s.pos

      # get_byte reads a single byte and advances by one.
      p s.get_byte
      p s.get_byte
      p s.pos

      # unscan backs up over the most recent scan.
      tok = s.scan(/st /)
      p tok
      p s.pos
      s.unscan
      p s.pos
      p s.scan(/st /)
    RUBY

    _(result).must_answer <<~'OUT'
      3
      0
      "test str"
      0
      "t"
      "e"
      2
      "st "
      5
      2
      "st "
    OUT
  end

  it "strscan scans anchored and until" do
    result = zr(<<~'RUBY')
      require "strscan"
      sc = StringScanner.new("foo123bar")
      puts sc.scan(/[a-z]+/)
      puts sc.scan(/\d+/)
      puts sc.rest
      sc2 = StringScanner.new("a=1;b=2")
      puts sc2.scan_until(/;/)
    RUBY

    _(result).must_answer <<~'OUT'
      foo
      123
      bar
      a=1;
    OUT
  end

  it "strscan subclass" do
    result = zr(<<~'RUBY')
      # A native class can be subclassed when it has a payload shape to inherit --
      # csv's parser is `class Scanner < StringScanner` with a `@keeps` stack of its
      # own on top of the inherited scanning behaviour.
      require "strscan"

      class Keeper < StringScanner
        alias_method :scan_all, :scan

        def initialize(*args)
          super
          @keeps = []
        end

        def keep_start = @keeps.push(pos)

        def keep_end
          start = @keeps.pop
          string.byteslice(start, pos - start)
        end

        def keep_back = (self.pos = @keeps.pop)
      end

      k = Keeper.new("hello world")
      p k.class, k.is_a?(StringScanner), Keeper.superclass

      k.scan(/hello/)
      k.keep_start
      k.scan(/ world/)
      p k.keep_end
      p k.pos, k.eos?, k.rest
      p k.instance_variables

      # The inherited surface is all there, including the capture reads.
      k2 = Keeper.new("k=v")
      p k2.scan_all(/(\w+)=(\w+)/)
      p k2[1], k2[2], k2.captures
      k2.keep_start
      p k2.eos?

      # ...and `keep_back` rewinds through the subclass's own state.
      k3 = Keeper.new("abcdef")
      k3.scan(/abc/)
      k3.keep_start
      k3.scan(/def/)
      p k3.pos
      k3.keep_back
      p k3.pos, k3.rest
    RUBY

    _(result).must_answer <<~'OUT'
      Keeper
      true
      StringScanner
      " world"
      11
      true
      ""
      [:@keeps]
      "k=v"
      "k"
      "v"
      ["k", "v"]
      true
      6
      3
      "def"
    OUT
  end

  it "concat grows the scanner's string, and groups and names read as strscan_aref reads them" do
    result = zr(<<~'RUBY')
      # concat grows the scanner's own string; a number counts groups from the
      # end; a name needs a Regexp's groups, and named_captures reads the names
      # of the last Regexp tried.
      require "strscan"
      x = +"ab"
      s = StringScanner.new(x)
      s << "cd"
      p [x, s.string.equal?(x), s.scan(/abcd/)]
      s = StringScanner.new("abc")
      s.scan("ab")
      p [s[-1], s[0], s[1], s[-2], (s[:x] rescue $!)]
      s = StringScanner.new("abc")
      s.scan(/(?<a>x)/)
      p s.named_captures
      s.scan(/(?<a>a)(?<b>b)?/)
      p [s.named_captures, s[:a], s["b"], (s[:zz] rescue $!), s[-1], s[-3]]
      s.scan("c")
      p s.named_captures
    RUBY

    _(result).must_answer <<~'OUT'
      ["abcd", true, "abcd"]
      ["ab", "ab", nil, nil, #<IndexError: undefined group name reference: x>]
      {"a" => nil}
      [{"a" => "a", "b" => "b"}, "a", "b", #<IndexError: undefined group name reference: zz>, "b", "ab"]
      {}
    OUT
  end

  it "the rest past a shrunk string is empty, and a copy scans on by itself" do
    result = zr(<<~'RUBY')
      # The rest past a string that shrank is empty; scan_integer needs an
      # ASCII-compatible string; a copy scans on by itself; there is no clear.
      require "strscan"
      x = +"abcdef"
      s = StringScanner.new(x)
      s.pos = 6
      x.replace("ab")
      p [s.rest, s.rest_size, s.eos?]
      p((StringScanner.new("1".encode("UTF-16LE")).scan_integer rescue $!))
      s = StringScanner.new("abc")
      s.scan(/a/)
      d = s.dup
      d.scan(/b/)
      p [s.pos, d.pos, d.matched, s.matched]
      p((StringScanner.new("a").clear rescue $!), StringScanner.private_instance_methods(false).sort)
    RUBY

    _(result).must_answer <<~'OUT'
      ["", 0, true]
      #<Encoding::CompatibilityError: ASCII incompatible encoding: UTF-16LE>
      [1, 2, "b", "a"]
      #<NoMethodError: undefined method 'clear' for an instance of StringScanner>
      [:initialize, :initialize_copy, :scan_base10_integer, :scan_base16_integer]
    OUT
  end
end
