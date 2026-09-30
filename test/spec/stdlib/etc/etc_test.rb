# frozen_string_literal: true

require "spec_helper"

describe "Etc programs" do
  it "the user and group databases, sysconf, uname and the processor count all answer their contract" do
    result = zr(<<~'RUBY')
      # Etc: the system user/group databases, sysconf/confstr, uname, and processor
      # count -- CRuby's native `ext/etc` over libc. Host-specific values (the real
      # uid, hostname, cpu count) can't be printed verbatim, so this prints the
      # CONTRACT -- types, round-trips, and member sets -- identical under zr and ruby.
      require "etc"

      # The current user, and a name/uid round-trip through the database.
      pw = Etc.getpwuid
      puts pw.class
      puts pw.name.is_a?(String)
      puts pw.uid.is_a?(Integer)
      puts(Etc.getpwnam(pw.name).uid == pw.uid)
      puts(Etc.getpwuid(pw.uid).name == pw.name)

      # Etc::Passwd is Struct-like.
      puts pw.members.first(4).inspect
      puts pw.to_a.length == pw.members.length
      puts pw.to_h[:uid] == pw.uid
      puts pw[:name] == pw.name

      # The group database, mirroring the user one.
      gr = Etc.getgrgid
      puts gr.class
      puts gr.mem.is_a?(Array)
      puts(Etc.getgrnam(gr.name).gid == gr.gid)

      # uname(2): the five portable system fields.
      u = Etc.uname
      puts u.keys.sort.inspect
      puts u.values.all? { |v| v.is_a?(String) }

      # Runtime configuration + processor count.
      puts Etc.nprocessors > 0
      puts(Etc.nprocessors == Etc.sysconf(Etc::SC_NPROCESSORS_ONLN))
      puts Etc.sysconf(Etc::SC_CLK_TCK) > 0
      puts Etc::SC_OPEN_MAX.is_a?(Integer)
      puts Etc::PC_NAME_MAX.is_a?(Integer)

      # The whole database iterates, and always includes root (uid 0).
      saw_root = false
      Etc.passwd { |p| saw_root = true if p.uid == 0 }
      puts saw_root
    RUBY

    _(result).must_answer <<~'OUT'
      Etc::Passwd
      true
      true
      true
      true
      [:name, :passwd, :uid, :gid]
      true
      true
      true
      Etc::Group
      true
      true
      [:machine, :nodename, :release, :sysname, :version]
      true
      true
      true
      true
      true
      true
      true
    OUT
  end

  it "group lookup types and roundtrip" do
    result = zr(<<~'RUBY', files: {"etc.rb" => fixture("stdlib/etc/etc.rb")})
      require "etc"
      gr = Etc.getgrgid           # current effective gid
      puts gr.class
      puts gr.is_a?(Etc::Group)
      puts gr.name.is_a?(String)
      puts gr.gid.is_a?(Integer)
      puts gr.mem.is_a?(Array)
      puts(Etc.getgrnam(gr.name).gid == gr.gid)
      puts gr.members.inspect
      puts gr.to_h.key?(:mem)
    RUBY

    _(result).must_answer <<~'OUT'
      Etc::Group
      true
      true
      true
      true
      true
      [:name, :passwd, :gid, :mem]
      true
    OUT
  end

  it "missing user or group raises argument error" do
    result = zr(<<~'RUBY', files: {"etc.rb" => fixture("stdlib/etc/etc.rb")})
      require "etc"
      begin
        Etc.getpwnam("no_such_user_zqxjkw")
      rescue ArgumentError => e
        puts "user: #{e.class}"
      end
      begin
        Etc.getgrnam("no_such_group_zqxjkw")
      rescue ArgumentError => e
        puts "group: #{e.class}"
      end
    RUBY

    _(result).must_answer "user: ArgumentError\ngroup: ArgumentError\n"
  end

  it "module paths and processor count" do
    result = zr(<<~'RUBY', files: {"etc.rb" => fixture("stdlib/etc/etc.rb")})
      require "etc"
      puts Etc.sysconfdir.class
      puts Etc.systmpdir.class
      puts Etc.nprocessors.class
      puts Etc.nprocessors > 0
      puts(Etc.getlogin.is_a?(String) || Etc.getlogin.nil?)
    RUBY

    _(result).must_answer <<~'OUT'
      String
      String
      Integer
      true
      true
    OUT
  end

  it "passwd database cursor and block iteration" do
    result = zr(<<~'RUBY', files: {"etc.rb" => fixture("stdlib/etc/etc.rb")})
      require "etc"
      # The block form iterates the whole database; every row is an Etc::Passwd
      # and root (uid 0) is always present.
      count = 0
      saw_root = false
      Etc.passwd do |p|
        count += 1
        saw_root = true if p.uid == 0
      end
      puts count > 0
      puts saw_root
      # setpwent rewinds; getpwent then returns a row (or nil at the end).
      Etc.setpwent
      first = Etc.getpwent
      puts(first.nil? || first.is_a?(Etc::Passwd))
      Etc.endpwent
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
    OUT
  end

  it "passwd lookup types members and roundtrip" do
    result = zr(<<~'RUBY', files: {"etc.rb" => fixture("stdlib/etc/etc.rb")})
      require "etc"
      pw = Etc.getpwuid            # current effective uid
      puts pw.class
      puts pw.is_a?(Etc::Passwd)
      puts pw.name.is_a?(String)
      puts pw.uid.is_a?(Integer)
      puts pw.gid.is_a?(Integer)
      puts pw.dir.is_a?(String)
      puts pw.shell.is_a?(String)
      # getpwnam(name) round-trips back to the same uid.
      puts(Etc.getpwnam(pw.name).uid == pw.uid)
      # getpwuid(uid) round-trips back to the same name.
      puts(Etc.getpwuid(pw.uid).name == pw.name)
      # Struct-like surface.
      puts pw.members.first(4).inspect
      puts pw.to_a.length == pw.members.length
      puts pw.to_h[:uid] == pw.uid
      puts pw[:name] == pw.name
      puts pw[0] == pw.name
    RUBY

    _(result).must_answer <<~'OUT'
      Etc::Passwd
      true
      true
      true
      true
      true
      true
      true
      true
      [:name, :passwd, :uid, :gid]
      true
      true
      true
      true
    OUT
  end

  it "passwd row carries darwins ten fields", only: "macos" do
    result = zr(<<~'RUBY', files: {"etc.rb" => fixture("stdlib/etc/etc.rb")})

      # darwin's struct passwd has ten fields Etc::Passwd carries, in the order
      # etc.c's setup_passwd gives them: the three past the shell are the
      # password's change time, the login class and the account's expiry.
      require "etc"
      p Etc::Passwd.members
      p Etc.getpwnam("root").to_a
      pw = Etc.getpwuid
      p [pw.change.class, pw.uclass.class, pw.expire.class, pw.to_a.size]

    RUBY

    _(result).must_answer <<~'OUT'
      [:name, :passwd, :uid, :gid, :gecos, :dir, :shell, :change, :uclass, :expire]
      ["root", "*", 0, 0, "System Administrator", "/var/root", "/bin/sh", 0, "", 0]
      [Integer, String, Integer, 10]
    OUT
  end

  it "probe messages" do
    result = zr(<<~'RUBY', files: {"etc.rb" => fixture("stdlib/etc/etc.rb")})
      # Differential probe: MESSAGE FIDELITY.
      #
      # Raises on purpose across the surfaces whose text is assembled at the raise
      # site, and prints the exception class and message per row.
      #
      # Message text drifts one site at a time, because each site writes its own.
      # Ruby 3.4 moved the quoting from ``x'` to `'x'`, CRuby names its own C
      # function in an Errno message, and a comparison failure names both operand
      # classes -- each of which zr got right in some places and not others.
      # This probe is how the rest of that family gets found.

      require "tmpdir"

      ROWS = {}

      def probe(name, &blk) = ROWS[name] = blk

      # Rows zr does not answer yet, each naming the gap that tracks it. A carved
      # row is left OUT of the output rather than recorded wrong. When a gap is
      # promoted, delete its entry here and re-bless; the row comes back.
      SKIP = {
        "exec missing" => "tests/gaps/a_failed_exec_names_the_program.rb",
      }.freeze

      DIR = Dir.mktmpdir("zr-probe")
      MISSING = File.join(DIR, "no-such-file")
      EXISTING = File.join(DIR, "a-file")
      File.write(EXISTING, "hi")

      # --- Errno: the site names CRuby's own C function -------------------------
      probe("File.read(missing)") { File.read(MISSING) }
      probe("File.open(missing)") { File.open(MISSING) }
      probe("File.read(directory)") { File.read(DIR) }
      probe("File.stat(missing)") { File.stat(MISSING) }
      probe("File.lstat(missing)") { File.lstat(MISSING) }
      probe("File.size(missing)") { File.size(MISSING) }
      probe("File.mtime(missing)") { File.mtime(MISSING) }
      probe("File.delete(missing)") { File.delete(MISSING) }
      probe("File.unlink(missing)") { File.unlink(MISSING) }
      probe("File.chmod(missing)") { File.chmod(0o600, MISSING) }
      probe("File.utime(missing)") { File.utime(Time.now, Time.now, MISSING) }
      probe("File.realpath(missing)") { File.realpath(MISSING) }
      probe("File.rename(missing)") { File.rename(MISSING, EXISTING) }
      probe("File.symlink(exists)") { File.symlink(EXISTING, EXISTING) }
      probe("File.link(exists)") { File.link(EXISTING, EXISTING) }
      probe("Dir.chdir(missing)") { Dir.chdir(MISSING) }
      probe("Dir.chdir(missing){}") { Dir.chdir(MISSING) { 1 } }
      probe("Dir.mkdir(exists)") { Dir.mkdir(DIR) }
      probe("Dir.entries(missing)") { Dir.entries(MISSING) }
      probe("IO.read(missing)") { IO.read(MISSING) }

      # --- Comparison failures name both operands -------------------------------
      probe("sort mixed") { [1, "a"].sort }
      probe("sort_by mixed") { [1, "a"].sort_by { |x| x } }
      probe("min_by mixed") { [1.0, Float::NAN, "a"].min_by { |x| x } }
      probe("max_by mixed") { [1.0, Float::NAN, "a"].max_by { |x| x } }
      probe("min mixed") { [1, "a"].min }
      probe("max mixed") { [1, "a"].max }
      # TWO elements, not three: with three, which pair the sort reaches first is
      # libc's `qsort_r` decision, so the message names a different operand on glibc
      # than on BSD. Two elements is one comparison, and both agree.
      probe("sort NaN") { [1.0, Float::NAN].sort }
      probe("<=> nil compare") { 1 < "a" }
      probe("Array#<=> mixed") { ([1] <=> ["a"]).inspect }

      # --- Quoting: ruby 3.4 moved from backtick-quote to straight quotes --------
      probe("undefined method") { Object.new.no_such_method }
      probe("undefined local") { eval("no_such_local_or_method", binding) }
      probe("wrong arity") { ->(a) {}.call }
      probe("wrong arity method") do
        c = Class.new { def m(a) = a }
        c.new.m
      end
      probe("private call") do
        c = Class.new do
          private def hidden = 1
        end
        c.new.hidden
      end
      probe("protected call") do
        c = Class.new do
          protected def guarded = 1
        end
        c.new.guarded
      end
      probe("unknown keyword") do
        c = Class.new { def m(a:) = a }
        c.new.m(a: 1, b: 2)
      end
      probe("missing keyword") do
        c = Class.new { def m(a:) = a }
        c.new.m
      end
      probe("uninitialized constant") { Object.const_get(:NoSuchConstant) }
      probe("trap unknown signal") { Signal.trap("SIGNOPE") { } }
      probe("kill unknown signal") { Process.kill("SIGNOPE", 0) }
      probe("NoMethodError on nil") { nil.no_such }
      probe("frozen String") { "x".freeze << "y" }
      probe("frozen Array") { [].freeze << 1 }
      probe("frozen Hash") { {}.freeze[:a] = 1 }
      probe("frozen Class") { Class.new.freeze.const_set(:A, 1) }
      probe("super without method") do
        c = Class.new { def inspect = super }
        Class.new(c).new.method(:inspect).owner.to_s
      end

      # --- Type coercion --------------------------------------------------------
      probe("Array + Integer") { [] + 1 }
      probe("String + Integer") { "" + 1 }
      probe("Integer + String") { 1 + "" }
      probe("Integer + nil") { 1 + nil }
      probe("String * String") { "a" * "b" }
      probe("Hash#[]= frozen key") { {}.merge!(1) }
      probe("implicit to_str") { File.read(1) }
      probe("implicit to_int") { [1][:x] }
      probe("zero division") { 1 / 0 }
      probe("Integer overflow shift") { 1 << -1 }

      # --- Regexp ---------------------------------------------------------------
      probe("bad property") { Regexp.new("\\p{NoSuchProperty}") }
      probe("bad posix class") { Regexp.new("[[:nosuch:]]") }
      probe("unterminated group") { Regexp.new("(") }
      probe("bad repeat") { Regexp.new("a{2,1}") }
      probe("bad backref") { Regexp.new("\\k<nope>") }

      # --- Encoding -------------------------------------------------------------
      probe("encode unknown") { "a".encode("NoSuchEncoding") }
      probe("encode unknown pair") { "a".encode("NoSuchTarget", "NoSuchSource") }
      probe("Encoding.find unknown") { Encoding.find("NoSuchEncoding") }
      probe("Encoding.find symbol") { Encoding.find(:utf8) }
      probe("force_encoding frozen") { "a".freeze.force_encoding("BINARY") }
      probe("undefined conversion") { "é".encode("US-ASCII") }
      probe("invalid byte sequence") { "\xff".dup.force_encoding("UTF-8").encode("UTF-16") }

      # --- Misc -----------------------------------------------------------------
      probe("negative sleep") { sleep(-1) }
      probe("set_backtrace(bad)") { RuntimeError.new("x").set_backtrace(1) }
      probe("Etc user missing") do
        require "etc"
        Etc.getpwnam("no-such-user-zr")
      end
      probe("exec missing") { exec("/no/such/program-zr") }
      probe("backquote missing") { `/no/such/program-zr` }
      probe("system exception") { system("/no/such/program-zr", exception: true) }

      ROWS.each do |name, fn|
        next if SKIP.key?(name)

        r = begin
          v = fn.call
          "ok #{v.inspect}"
        rescue Exception => e
          "#{e.class}: #{e.message}"
        end
        puts "#{name}\t#{r.gsub(DIR, "<TMP>")}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      File.read(missing)	Errno::ENOENT: No such file or directory @ rb_sysopen - <TMP>/no-such-file
      File.open(missing)	Errno::ENOENT: No such file or directory @ rb_sysopen - <TMP>/no-such-file
      File.read(directory)	Errno::EISDIR: Is a directory @ io_fread - <TMP>
      File.stat(missing)	Errno::ENOENT: No such file or directory @ rb_file_s_stat - <TMP>/no-such-file
      File.lstat(missing)	Errno::ENOENT: No such file or directory @ rb_file_s_lstat - <TMP>/no-such-file
      File.size(missing)	Errno::ENOENT: No such file or directory @ rb_file_s_size - <TMP>/no-such-file
      File.mtime(missing)	Errno::ENOENT: No such file or directory @ rb_file_s_mtime - <TMP>/no-such-file
      File.delete(missing)	Errno::ENOENT: No such file or directory @ apply2files - <TMP>/no-such-file
      File.unlink(missing)	Errno::ENOENT: No such file or directory @ apply2files - <TMP>/no-such-file
      File.chmod(missing)	Errno::ENOENT: No such file or directory @ apply2files - <TMP>/no-such-file
      File.utime(missing)	Errno::ENOENT: No such file or directory @ apply2files - <TMP>/no-such-file
      File.realpath(missing)	Errno::ENOENT: No such file or directory @ rb_check_realpath_internal - <TMP>/no-such-file
      File.rename(missing)	Errno::ENOENT: No such file or directory @ rb_file_s_rename - (<TMP>/no-such-file, <TMP>/a-file)
      File.symlink(exists)	Errno::EEXIST: File exists @ syserr_fail2_in - <TMP>/a-file
      File.link(exists)	Errno::EEXIST: File exists @ syserr_fail2_in - <TMP>/a-file
      Dir.chdir(missing)	Errno::ENOENT: No such file or directory @ chdir_path - <TMP>/no-such-file
      Dir.chdir(missing){}	Errno::ENOENT: No such file or directory @ dir_chdir0 - <TMP>/no-such-file
      Dir.mkdir(exists)	Errno::EEXIST: File exists @ dir_s_mkdir - <TMP>
      Dir.entries(missing)	Errno::ENOENT: No such file or directory @ dir_initialize - <TMP>/no-such-file
      IO.read(missing)	Errno::ENOENT: No such file or directory @ rb_sysopen - <TMP>/no-such-file
      sort mixed	ArgumentError: comparison of Integer with String failed
      sort_by mixed	ArgumentError: comparison of Integer with String failed
      min_by mixed	ArgumentError: comparison of Float with 1.0 failed
      max_by mixed	ArgumentError: comparison of Float with 1.0 failed
      min mixed	ArgumentError: comparison of String with 1 failed
      max mixed	ArgumentError: comparison of String with 1 failed
      sort NaN	ArgumentError: comparison of Float with NaN failed
      <=> nil compare	ArgumentError: comparison of Integer with String failed
      Array#<=> mixed	ok "nil"
      undefined method	NoMethodError: undefined method 'no_such_method' for an instance of Object
      undefined local	NameError: undefined local variable or method 'no_such_local_or_method' for main
      wrong arity	ArgumentError: wrong number of arguments (given 0, expected 1)
      wrong arity method	ArgumentError: wrong number of arguments (given 0, expected 1)
      private call	NoMethodError: private method 'hidden' called for an instance of #<Class:0xADDR>
      protected call	NoMethodError: protected method 'guarded' called for an instance of #<Class:0xADDR>
      unknown keyword	ArgumentError: unknown keyword: :b
      missing keyword	ArgumentError: missing keyword: :a
      uninitialized constant	NameError: uninitialized constant NoSuchConstant
      trap unknown signal	ArgumentError: unsupported signal 'SIGNOPE'
      kill unknown signal	ArgumentError: unsupported signal 'SIGNOPE'
      NoMethodError on nil	NoMethodError: undefined method 'no_such' for nil
      frozen String	FrozenError: can't modify frozen String: "x"
      frozen Array	FrozenError: can't modify frozen Array: []
      frozen Hash	FrozenError: can't modify frozen Hash: {}
      frozen Class	FrozenError: can't modify frozen Class: #<Class:0xADDR>
      super without method	ok "#<Class:0xADDR>"
      Array + Integer	TypeError: no implicit conversion of Integer into Array
      String + Integer	TypeError: no implicit conversion of Integer into String
      Integer + String	TypeError: String can't be coerced into Integer
      Integer + nil	TypeError: nil can't be coerced into Integer
      String * String	TypeError: no implicit conversion of String into Integer
      Hash#[]= frozen key	TypeError: no implicit conversion of Integer into Hash
      implicit to_str	TypeError: no implicit conversion of Integer into String
      implicit to_int	TypeError: no implicit conversion of Symbol into Integer
      zero division	ZeroDivisionError: divided by 0
      Integer overflow shift	ok 0
      bad property	RegexpError: invalid character property name {NoSuchProperty}: /\p{NoSuchProperty}/
      bad posix class	RegexpError: invalid POSIX bracket type: /[[:nosuch:]]/
      unterminated group	RegexpError: end pattern with unmatched parenthesis: /(/
      bad repeat	RegexpError: upper is smaller than lower in repeat range: /a{2,1}/
      bad backref	RegexpError: undefined name <nope> reference: /\k<nope>/
      encode unknown	Encoding::ConverterNotFoundError: code converter not found (UTF-8 to NoSuchEncoding)
      encode unknown pair	Encoding::ConverterNotFoundError: code converter not found (NoSuchSource to NoSuchTarget)
      Encoding.find unknown	ArgumentError: unknown encoding name - NoSuchEncoding
      Encoding.find symbol	TypeError: no implicit conversion of Symbol into String
      force_encoding frozen	FrozenError: can't modify frozen String: "a"
      undefined conversion	Encoding::UndefinedConversionError: U+00E9 from UTF-8 to US-ASCII
      invalid byte sequence	Encoding::InvalidByteSequenceError: "\xFF" on UTF-8
      negative sleep	ArgumentError: time interval must not be negative
      set_backtrace(bad)	TypeError: backtrace must be an Array of String or an Array of Thread::Backtrace::Location
      Etc user missing	ArgumentError: can't find user for no-such-user-zr
      backquote missing	Errno::ENOENT: No such file or directory - /no/such/program-zr
      system exception	Errno::ENOENT: No such file or directory - /no/such/program-zr
    OUT
  end

  it "struct backed builtin class is a struct" do
    result = zr(<<~'RUBY', files: {"etc.rb" => fixture("stdlib/etc/etc.rb")})
      # `Etc::Passwd`, `Etc::Group` and `Process::Tms` are real `Struct` subclasses,
      # as `rb_struct_define` makes them in CRuby -- so the whole struct protocol is
      # INHERITED and each class supplies only its members and accessors.
      #
      # The example checks the member WRITERS (`pw.name = "x"`), `Struct` in
      # `ancestors`, and `==` that compares by value, not by identity.
      #
      # Because they are true Struct subclasses, every other row comes from
      # `Struct` itself (`dig`, `size`, `values_at`, `each_pair`, `deconstruct`,
      # `Marshal`).
      #
      # `Etc::Passwd.each` and `Etc::Group.each` are the database cursors, the
      # same walk that `Etc.passwd`/`Etc.group` do with a block.

      require "etc"

      pw = Etc.getpwuid
      p Etc::Passwd.superclass.to_s
      p Etc::Passwd.ancestors.include?(Struct)
      p Etc::Passwd.ancestors.include?(Enumerable)
      p pw.respond_to?(:name=)
      p Etc::Passwd.instance_methods(false).include?(:to_a)
      p Process::Tms.superclass.to_s

      # A Struct's `==`/`eql?` compare BY VALUE.
      p [pw == Etc.getpwuid, pw.eql?(Etc.getpwuid), pw.equal?(Etc.getpwuid)]

      # The inherited protocol, none of which is written per class.
      t = Process.times
      p [t.size, t.to_a.size, t.to_h.keys.map(&:to_s), t.members.map(&:to_s)]
      p [t.each.to_a.size, t.each_pair.to_a.size, t.deconstruct.size]
      p [t.dig(0).class.to_s, t.values_at(0, 1).size, t.select { true }.size]
      p t.to_s.start_with?("#<struct Process::Tms ")
      p Marshal.load(Marshal.dump(t)).to_a == t.to_a

      # The writers, by name and by index.
      pw.name = "zzz"
      p pw.name
      pw[1] = "yyy"
      p pw.passwd

      # The class methods a Struct subclass carries in its OWN singleton.
      p Etc::Passwd.singleton_methods(false).sort.map(&:to_s)
      p Process::Tms.singleton_methods(false).sort.map(&:to_s)
      p Etc::Passwd["a"].to_a.first
      p Etc::Passwd.keyword_init?

      # The database cursors.
      n = 0
      Etc::Passwd.each { |_row| n += 1 }
      p n > 0
    RUBY

    _(result).must_answer <<~'OUT'
      "Struct"
      true
      true
      true
      false
      "Struct"
      [true, true, false]
      [4, 4, ["utime", "stime", "cutime", "cstime"], ["utime", "stime", "cutime", "cstime"]]
      [4, 4, 4]
      ["Float", 2, 4]
      true
      true
      "zzz"
      "yyy"
      ["[]", "each", "inspect", "keyword_init?", "members", "new"]
      ["[]", "inspect", "keyword_init?", "members", "new"]
      "a"
      nil
      true
    OUT
  end

  it "sysconf confstr and constants" do
    result = zr(<<~'RUBY', files: {"etc.rb" => fixture("stdlib/etc/etc.rb")})
      require "etc"
      puts Etc::SC_CLK_TCK.is_a?(Integer)
      puts Etc::SC_OPEN_MAX.is_a?(Integer)
      puts Etc::SC_NPROCESSORS_ONLN.is_a?(Integer)
      puts Etc::PC_NAME_MAX.is_a?(Integer)
      puts Etc::CS_PATH.is_a?(Integer)
      puts Etc.sysconf(Etc::SC_CLK_TCK) > 0
      puts Etc.sysconf(Etc::SC_OPEN_MAX) > 0
      puts(Etc.confstr(Etc::CS_PATH).is_a?(String) || Etc.confstr(Etc::CS_PATH).nil?)
      # nprocessors agrees with the sysconf value.
      puts(Etc.nprocessors == Etc.sysconf(Etc::SC_NPROCESSORS_ONLN))
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      true
      true
      true
      true
      true
    OUT
  end

  it "uname returns the five fields" do
    result = zr(<<~'RUBY', files: {"etc.rb" => fixture("stdlib/etc/etc.rb")})
      require "etc"
      u = Etc.uname
      puts u.class
      puts u.keys.sort.inspect
      puts u.values.all? { |v| v.is_a?(String) }
      puts u[:sysname].empty? == false
    RUBY

    _(result).must_answer <<~'OUT'
      Hash
      [:machine, :nodename, :release, :sysname, :version]
      true
      true
    OUT
  end

  it "etc gives IO#pathconf over fpathconf, and raises its errno" do
    result = zr(<<~'RUBY')
      # etc gives IO#pathconf: fpathconf(3) on the stream's descriptor.
      p IO.method_defined?(:pathconf)
      require "etc"
      p File.open("/") { |f| f.pathconf(Etc::PC_NAME_MAX) }.class, IO.pipe { |r, _| r.pathconf(Etc::PC_PIPE_BUF) }.positive?
      p (File.open("/") { |f| f.pathconf(99999) } rescue $!), (File.open("/") { |f| f.pathconf("x") } rescue $!)
      p IO.instance_method(:pathconf).owner
    RUBY

    _(result).must_answer <<~'OUT'
      false
      Integer
      true
      #<Errno::EINVAL: Invalid argument - fpathconf>
      #<TypeError: no implicit conversion of String into Integer>
      IO
    OUT
  end

  it "etc names the version of its gem, as its C does" do
    result = zr(<<~'RUBY')
      require "etc"
      p Etc::VERSION, Etc.const_defined?(:VERSION, false)
    RUBY

    _(result).must_answer <<~'OUT'
      "1.4.6"
      true
    OUT
  end
end
