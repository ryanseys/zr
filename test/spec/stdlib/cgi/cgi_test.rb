# frozen_string_literal: true

require "spec_helper"

describe "CGI programs" do
  it "escapeElement rewrites only the tags it was asked about, each span ending at the next delimiter" do
    result = zr(<<~'RUBY')
      # `CGI.escapeElement` / `CGI.unescapeElement` rewrite only the tags they were
      # asked about, and each span ends at the next DELIMITER.
      #
      # CRuby writes each as a regexp, and the two differ only in the alphabet
      # (`cgi/escape.rb`, ruby 4.0.7):
      #
      #   escapeElement    /<\/?(?:A|B)\b[^<>]*+>?/im
      #   unescapeElement  /&lt;\/?(?:A|B)\b(?>[^&]+|&(?![gl]t;)\w+;)*(?:&gt;)?/im
      #
      # Both read the tag name, then run to the next open or close delimiter, and
      # take the close only when that is what stopped them. So an unterminated tag
      # still matches, and a tag whose attributes carry an escaped delimiter ends
      # AT it rather than running on to the next close.
      #
      # The escaped form also stops at any `&` that does not begin a `&word;`
      # entity, which is why a NUMERIC reference ends a span: `&#62;` has no word
      # character after the `&`.
      require "cgi"

      # The documented shapes.
      p CGI.escapeElement('<BR><A HREF="url"></A>', "A", "IMG")
      p CGI.escapeElement('<BR><A HREF="url"></A>', ["A", "IMG"])
      p CGI.unescapeElement(CGI.escapeHTML('<BR><A HREF="url"></A>'), "A", "IMG")
      p CGI.unescapeElement(CGI.escapeHTML('<BR><A HREF="url"></A>'), ["A", "IMG"])

      # An UNTERMINATED tag matches: the close is optional.
      p CGI.escapeElement("<A", "A")
      p CGI.unescapeElement("&lt;A", "A")
      p CGI.unescapeElement("&lt;/A", "A")

      # A delimiter inside the attributes ENDS the span.
      p CGI.escapeElement('<A HREF="a<b">t</A>', "A")
      p CGI.unescapeElement("&lt;A HREF=&quot;a&lt;b&quot;&gt;t&lt;/A&gt;", "A")

      # A numeric reference ends an escaped span; a named one does not.
      p CGI.unescapeElement("&lt;A ALT=&#62;&gt;t&lt;/A&gt;", "A")
      p CGI.unescapeElement("&lt;A ALT=&quot;q&quot;&gt;t&lt;/A&gt;", "A")
      p CGI.unescapeElement("&lt;A x=&nosemi&gt;", "A")

      # The name is read to its end, so a longer tag is a different tag.
      p CGI.escapeElement("<ABBR>x</ABBR>", "A")
      p CGI.unescapeElement("&lt;AB&gt;t&lt;/AB&gt;", "A")

      # Matching is case-insensitive, and an empty element list rewrites nothing.
      p CGI.escapeElement("<a href=x>", "A")
      p CGI.escapeElement("<A>", [])
      p CGI.unescapeElement("&lt;A&gt;", [])

      # Only the named tags move.
      p CGI.escapeElement("<A>t</A><B>u</B>", "B")
      p CGI.unescapeElement("&lt;A&gt;t&lt;/A&gt;&lt;B&gt;u&lt;/B&gt;", "B")

      # The element forms leave the bytes around a span alone, invalid ones too.
      doc = "&lt;A&gt;t&lt;/A&gt;\xC0".dup.force_encoding("BINARY")
      r = CGI.unescapeElement(doc, "A")
      puts "#{r.inspect} #{r.encoding}"
    RUBY

    _(result).must_answer <<~'OUT'
      "<BR>&lt;A HREF=&quot;url&quot;&gt;&lt;/A&gt;"
      "<BR>&lt;A HREF=&quot;url&quot;&gt;&lt;/A&gt;"
      "&lt;BR&gt;<A HREF=\"url\"></A>"
      "&lt;BR&gt;<A HREF=\"url\"></A>"
      "&lt;A"
      "<A"
      "</A"
      "&lt;A HREF=&quot;a<b\">t&lt;/A&gt;"
      "<A HREF=\"a&lt;b&quot;&gt;t</A>"
      "<A ALT=&#62;&gt;t</A>"
      "<A ALT=\"q\">t</A>"
      "<A x=&nosemi&gt;"
      "<ABBR>x</ABBR>"
      "&lt;AB&gt;t&lt;/AB&gt;"
      "&lt;a href=x&gt;"
      "<A>"
      "&lt;A&gt;"
      "<A>t</A>&lt;B&gt;u&lt;/B&gt;"
      "&lt;A&gt;t&lt;/A&gt;<B>u</B>"
      "<A>t</A>\xC0" ASCII-8BIT
    OUT
  end

  it "escape, escapeHTML and unescape answer what ruby answers" do
    result = zr(<<~'RUBY')
      require "cgi/escape"
      puts CGI.escape("a b&c=d")
      puts CGI.escapeHTML("<x>&'")
      puts CGI.unescape("a+b%26c")
    RUBY

    _(result).must_answer <<~'OUT'
      a+b%26c%3Dd
      &lt;x&gt;&amp;&#39;
      a b&c
    OUT
  end

  it "every escape rewrites bytes, so the answer keeps the encoding it was given" do
    result = zr(<<~'RUBY')
      # Every CGI escape is a BYTE transformation: it rewrites ASCII punctuation
      # and passes every other byte through, so ruby hands back a string in the
      # encoding it was given -- invalid bytes and all.
      #
      # Decoding the argument first breaks that twice over. It re-encodes (a byte
      # read as a codepoint and written back as UTF-8 turns a snowman into three
      # Latin-1 characters), and it loses the encoding (a binary string comes
      # back UTF-8). Both were live: `CGI.escapeHTML("\xC0<")` answered
      # `"À&lt;"` in UTF-8, and rack's `escape_html` specs are what caught it.
      require "cgi/escape"

      snow = "☃"
      bin  = "\xC0<".dup.force_encoding("BINARY")
      lat  = "caf\xE9".dup.force_encoding("ISO-8859-1")

      [snow, bin, lat].each do |s|
        r = CGI.escapeHTML(s)
        puts "escapeHTML(#{s.encoding}) -> #{r.inspect} #{r.encoding}"
      end

      [[snow, "escape"], [bin, "escape"], [snow, "escapeURIComponent"]].each do |s, m|
        r = CGI.public_send(m, s)
        puts "#{m}(#{s.encoding}) -> #{r.inspect} #{r.encoding}"
      end

      # A percent-decode answers BYTES: `%C0` is not valid UTF-8 and survives
      # anyway, where a lossy decode replaced it with U+FFFD.
      r = CGI.unescape("%C0%3C")
      puts "unescape -> #{r.inspect} #{r.encoding}"

      # A named entity is ASCII and always decodes. A NUMERIC one decodes only
      # when the string's encoding can hold the character, and is left standing
      # when it cannot: no byte in a binary string is a snowman, and Latin-1 has
      # a byte for `&#233;` but none for `&#9731;`.
      {
        "utf8"   => "UTF-8",
        "binary" => "BINARY",
        "latin1" => "ISO-8859-1",
      }.each do |label, enc|
        ["&lt;&amp;", "&#9731;", "&#233;"].each do |src|
          r = CGI.unescapeHTML(src.dup.force_encoding(enc))
          puts "unescapeHTML(#{label}, #{src}) -> #{r.inspect} #{r.encoding}"
        end
      end

      # The element forms escape only the tags they were asked about, and leave
      # the bytes around them alone. The span rule itself -- where one tag ends --
      # is `tests/cgi_element_escapes_span_one_tag.rb`; what this file asks of the
      # family is that it stay a BYTE transformation.
      doc = "<A HREF='x'>t</A>\xC0".dup.force_encoding("BINARY")
      r = CGI.escapeElement(doc, "A")
      puts "escapeElement -> #{r.inspect} #{r.encoding}"
      puts CGI.unescapeElement("&lt;A&gt;t&lt;/A&gt;\xC0".dup.force_encoding("BINARY"), "A").inspect
    RUBY

    _(result).must_answer <<~'OUT'
      escapeHTML(UTF-8) -> "☃" UTF-8
      escapeHTML(ASCII-8BIT) -> "\xC0&lt;" ASCII-8BIT
      escapeHTML(ISO-8859-1) -> "caf\xE9" ISO-8859-1
      escape(UTF-8) -> "%E2%98%83" UTF-8
      escape(ASCII-8BIT) -> "%C0%3C" ASCII-8BIT
      escapeURIComponent(UTF-8) -> "%E2%98%83" UTF-8
      unescape -> "\xC0<" UTF-8
      unescapeHTML(utf8, &lt;&amp;) -> "<&" UTF-8
      unescapeHTML(utf8, &#9731;) -> "☃" UTF-8
      unescapeHTML(utf8, &#233;) -> "é" UTF-8
      unescapeHTML(binary, &lt;&amp;) -> "<&" ASCII-8BIT
      unescapeHTML(binary, &#9731;) -> "&#9731;" ASCII-8BIT
      unescapeHTML(binary, &#233;) -> "&#233;" ASCII-8BIT
      unescapeHTML(latin1, &lt;&amp;) -> "<&" ISO-8859-1
      unescapeHTML(latin1, &#9731;) -> "&#9731;" ISO-8859-1
      unescapeHTML(latin1, &#233;) -> "\xE9" ISO-8859-1
      escapeElement -> "&lt;A HREF=&#39;x&#39;&gt;t&lt;/A&gt;\xC0" ASCII-8BIT
      "<A>t</A>\xC0"
    OUT
  end

  it "escapeHTML is an instance method of CGI::EscapeExt, which CGI reaches by include and extend" do
    result = zr(<<~'RUBY')
      # `CGI.escapeHTML` is not a class method of `CGI`. It is an instance method of
      # `CGI::EscapeExt`, reached because `CGI` both INCLUDES and EXTENDS
      # `CGI::Escape`, and `Escape` PREPENDS `EscapeExt`. zr hung the helpers
      # straight on CGI's singleton and had neither module, so erubi's
      # `defined?(::CGI::Escape)` and net-http-persistent's `defined?(CGI::EscapeExt)`
      # both answered nil and took their fallback branch.
      require "cgi/escape"

      p [CGI::Escape.class, CGI::EscapeExt.class]
      p CGI::Escape.name, CGI::EscapeExt.name

      # Four edges, none derivable from the others.
      p CGI.ancestors.take(4)
      p CGI.singleton_class.ancestors.take(3)
      p CGI::Escape.ancestors
      p CGI::EscapeExt.ancestors

      # The two overlap on eight names and differ on the rest: only `Escape` has the
      # `*Element` family, only `EscapeExt` has `h` and the snake spellings.
      p CGI::Escape.instance_methods(false).sort
      p CGI::EscapeExt.instance_methods(false).sort

      p CGI.escapeHTML("<a href='x'>&\"")
      p CGI.unescapeHTML("&lt;a&gt;&amp;&quot;&#39;")
      p CGI.escape("a b+c/d")
      p CGI.unescape("a+b%2Fc")
      p CGI.escapeURIComponent("a b/c")
      p CGI.unescapeURIComponent("a+b%2Fc")
      p CGI.escape_html("<x>")
      p CGI.unescape_html("&lt;x&gt;")
      p CGI.escape_uri_component("a b")
      p CGI.unescape_uri_component("a%20b")
      p CGI.h("<x>")

      # `escapeElement` escapes the TAGS of the elements it was named, and nothing
      # else -- not the text between them, and not a tag it was not asked about.
      p CGI.escapeElement("<A HREF='x'>t</A><B>b</B>", "A")
      p CGI.escapeElement("<A><B>", "A", "B")
      p CGI.escapeElement("<A><B>", ["A"])
      p CGI.escapeElement("<A>")
      # A longer tag is not the one named.
      p CGI.escapeElement("<ABBR><A>", "A")
      p CGI.unescapeElement("&lt;A&gt;&lt;B&gt;", "A")
      p CGI.escape_element("<A><B>", "A")
      p CGI.unescape_element("&lt;A&gt;&lt;B&gt;", "A")

      # Mixing the module in is what the gems that reach for it actually do.
      class Own
        include CGI::Escape
      end
      p Own.new.escapeHTML("<a>")
      p Own.new.escapeElement("<A>", "A")
      p Own.ancestors.take(4)
      p Own.new.is_a?(CGI::EscapeExt)
      p Own.instance_method(:escapeHTML).owner
    RUBY

    _(result).must_answer <<~'OUT'
      [Module, Module]
      "CGI::Escape"
      "CGI::EscapeExt"
      [CGI, CGI::EscapeExt, CGI::Escape, Object]
      [#<Class:CGI>, CGI::EscapeExt, CGI::Escape]
      [CGI::EscapeExt, CGI::Escape]
      [CGI::EscapeExt]
      [:escape, :escapeElement, :escapeHTML, :escapeURIComponent, :escape_element, :escape_uri_component, :unescape, :unescapeElement, :unescapeHTML, :unescapeURIComponent, :unescape_element, :unescape_uri_component]
      [:escape, :escapeHTML, :escapeURIComponent, :escape_html, :escape_uri_component, :h, :unescape, :unescapeHTML, :unescapeURIComponent, :unescape_html, :unescape_uri_component]
      "&lt;a href=&#39;x&#39;&gt;&amp;&quot;"
      "<a>&\"'"
      "a+b%2Bc%2Fd"
      "a b/c"
      "a%20b%2Fc"
      "a+b/c"
      "&lt;x&gt;"
      "<x>"
      "a%20b"
      "a b"
      "&lt;x&gt;"
      "&lt;A HREF=&#39;x&#39;&gt;t&lt;/A&gt;<B>b</B>"
      "&lt;A&gt;&lt;B&gt;"
      "&lt;A&gt;<B>"
      "<A>"
      "<ABBR>&lt;A&gt;"
      "<A>&lt;B&gt;"
      "&lt;A&gt;<B>"
      "<A>&lt;B&gt;"
      "&lt;a&gt;"
      "&lt;A&gt;"
      [Own, CGI::EscapeExt, CGI::Escape, Object]
      true
      CGI::EscapeExt
    OUT
  end

  it "extended modules row answers as the modules own" do
    result = zr(<<~'RUBY')
      # `extend M` seats M in the SINGLETON class's ancestry: the class method it
      # supplies is still M's own instance method, and every reflection answer says
      # so. zr scanned only the class ancestry for a class-method owner, so it
      # found nothing there and fell back to reporting `Class`.
      module Ext
        def hi = 1
      end
      class K
        extend Ext
        def self.own = 2
      end

      m = K.method(:hi)
      p m.owner
      p m.arity, m.name, m.receiver
      p m.unbind.owner
      p m.super_method
      p m.call

      # An own `def self.x` is the other shape and must keep its own answers: it
      # really is minted on the singleton class.
      p K.method(:own).owner
      p K.singleton_methods(false), K.singleton_methods.sort
      p K.singleton_class.instance_methods(false)

      # `module M; def self.x; end; end` is NOT the extend shape either -- `M` owns
      # a real class method there.
      module Mod
        def self.mown = 3
      end
      p Mod.method(:mown).owner

      # A runtime `extend` answers the same way as one written in a class body.
      class L
      end
      L.extend(Ext)
      p L.hi, L.method(:hi).owner, L.respond_to?(:hi)
      o = Object.new
      o.extend(Ext)
      p o.hi, o.respond_to?(:hi), o.is_a?(Ext), o.singleton_class.ancestors.take(2)

      # The builtin that needed this: `CGI` both includes and extends `CGI::Escape`,
      # which prepends `CGI::EscapeExt`, so no escape is a class method of `CGI`.
      require "cgi/escape"
      p CGI.method(:escapeHTML).owner
      p CGI.method(:escapeElement).owner
      p CGI.method(:h).owner
      p CGI.singleton_class.instance_method(:escape).owner
      p CGI.singleton_class.ancestors.take(3)
      p CGI.singleton_class.instance_methods(false)
      p CGI.instance_method(:escapeHTML).owner
      p CGI.escapeHTML("<a>"), CGI.escapeElement("<A>", "A"), CGI.respond_to?(:h)
    RUBY

    _(result).must_answer <<~'OUT'
      Ext
      0
      :hi
      K
      Ext
      nil
      1
      #<Class:K>
      [:own]
      [:hi, :own]
      [:own]
      #<Class:Mod>
      1
      Ext
      true
      1
      true
      true
      [#<Class:#<Object:0xADDR>>, Ext]
      CGI::EscapeExt
      CGI::Escape
      CGI::EscapeExt
      CGI::EscapeExt
      [#<Class:CGI>, CGI::EscapeExt, CGI::Escape]
      []
      CGI::EscapeExt
      "&lt;a&gt;"
      "&lt;A&gt;"
      true
    OUT
  end

  it "extensions" do
    result = zr(<<~'RUBY')
      # In-tree ext/ extensions, activated by `require` and dispatched through the
      # same tables as the core builtins. Each is behind a per-extension build
      # feature (default on). See docs/EXTENSIONS.md.

      require "json"
      require "yaml"
      require "stringio"
      require "strscan"
      require "cgi/escape"
      require "digest"
      require "zlib"

      # --- json (parse and generate) ---
      puts JSON.generate({ "a" => 1, "b" => [2, 3.5, nil, true] })
      puts JSON.parse('{"x":[1,2,3],"y":"hi"}').inspect
      puts JSON.pretty_generate({ "k" => [1, 2] })

      # --- yaml / psych (load, and a Psych-style dump) ---
      print YAML.dump({ "name" => "zr", "tags" => ["aot", "ruby"] })
      puts YAML.load("port: 8080\nhosts:\n- a\n- b").inspect

      # --- stringio (in-memory IO buffer) ---
      io = StringIO.new
      io.puts "line one"
      io.puts "line two"
      io.rewind
      io.each_line { |l| print "got: #{l}" }

      # --- strscan (lexer over the Regexp engine) ---
      sc = StringScanner.new("key = value")
      puts sc.scan(/\w+/)
      sc.skip(/\s*=\s*/)
      puts sc.scan(/\w+/)

      # --- cgi (url/html escaping) ---
      puts CGI.escape("name=zr rb&v=1")
      puts CGI.escapeHTML("<b>bold & 'quoted'</b>")

      # --- digest (hashing) ---
      puts Digest::SHA256.hexdigest("hello")
      puts Digest::MD5.hexdigest("hello")

      # --- zlib (checksums) ---
      puts Zlib.crc32("hello")
      puts Zlib.adler32("hello")
    RUBY

    _(result).must_answer <<~'OUT'
      {"a":1,"b":[2,3.5,null,true]}
      {"x" => [1, 2, 3], "y" => "hi"}
      {
        "k": [
          1,
          2
        ]
      }
      ---
      name: zr
      tags:
      - aot
      - ruby
      {"port" => 8080, "hosts" => ["a", "b"]}
      got: line one
      got: line two
      key
      value
      name%3Dzr+rb%26v%3D1
      &lt;b&gt;bold &amp; &#39;quoted&#39;&lt;/b&gt;
      2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824
      5d41402abc4b2a76b9719d911017c592
      907060870
      103547413
    OUT
  end

  it "is a class not a module" do
    result = zr(<<~'RUBY')
      # CRuby's `CGI` is a CLASS whose superclass is `Object` -- `CGI.new(...)` is the
      # whole CGI API -- and cgi/escape.rb opens it as one (`class CGI`). zr had it
      # registered as a module, so every gem that reopened it stopped at `CGI is not a
      # class`, and thin's `class CGIWrapper < ::CGI` had nothing to subclass.

      require "cgi/escape"

      p [CGI.class, CGI.superclass]
      p [CGI.is_a?(Class), CGI.is_a?(Module), CGI.instance_of?(Class)]

      # The escape methods answer on the class, as they do in ruby.
      p CGI.escape("a b&c=d")
      p CGI.unescape("a+b%26c")
      p CGI.escapeHTML(%(Usage: foo "bar" <baz>))
      p CGI.unescapeHTML("&lt;x&gt;&amp;&quot;y&quot;")
      p CGI.escapeURIComponent("a b&c")
      p CGI.unescapeURIComponent("a%20b%26c")

      # The snake_case aliases are the same methods.
      p [CGI.escape_html("<x>"), CGI.unescape_html("&lt;x&gt;")]
      p [CGI.escape_uri_component("a b"), CGI.unescape_uri_component("a%20b")]

      # Being a class means it can be SUBCLASSED, which is what thin does to wrap a
      # rails request. A subclass is an ordinary ivar-carrying object: CGI itself
      # holds no payload.
      class CGIWrapper < ::CGI
        def initialize(env)
          @env = env
        end

        attr_reader :env

        def escaped_path
          CGI.escape(@env[:path])
        end
      end

      w = CGIWrapper.new(path: "/a b/c")
      p [CGIWrapper.superclass, w.env, w.escaped_path]
      p [w.is_a?(CGI), w.is_a?(Object), CGIWrapper.ancestors.first(2)]

      # A subclass may add to what it inherits, and `super` reaches Object's own.
      class Loud < CGIWrapper
        def escaped_path
          super.upcase
        end
      end

      p Loud.new(path: "/x y").escaped_path
      p [Loud.superclass, Loud.ancestors.first(3)]

      # `CGI` names a real class, so it works as a constant, in a rescue list
      # position, and as a `===` subject the way any class does.
      p [CGI.name, CGI.to_s]
      p [CGI === CGIWrapper.new(path: "/"), CGI === "not a cgi"]
      p CGIWrapper.new(path: "/").instance_variables
    RUBY

    _(result).must_answer <<~'OUT'
      [Class, Object]
      [true, true, true]
      "a+b%26c%3Dd"
      "a b&c"
      "Usage: foo &quot;bar&quot; &lt;baz&gt;"
      "<x>&\"y\""
      "a%20b%26c"
      "a b&c"
      ["&lt;x&gt;", "<x>"]
      ["a%20b", "a b"]
      [CGI, {path: "/a b/c"}, "%2Fa+b%2Fc"]
      [true, true, [CGIWrapper, CGI]]
      "%2FX+Y"
      [CGIWrapper, [Loud, CGIWrapper, CGI]]
      ["CGI", "CGI"]
      [true, false]
      [:@env]
    OUT
  end
end
