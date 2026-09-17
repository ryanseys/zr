# frozen_string_literal: true

require "spec_helper"

describe "Date programs" do
  it "allocated native object refuses what ruby refuses" do
    result = ze0(<<~'RUBY')
      # A blank instance is a legal RECEIVER, and answers exactly what ruby's does.
      #
      # Making `allocate` work is only half the job. Ruby draws a line between an
      # uninitialized value and an empty one, and the two are not interchangeable:
      # `Regexp.allocate` refuses `#source` where `//` answers `""`, and
      # `StringIO.allocate` refuses `#read` where `StringIO.new("")` answers `""`.
      # A blank that quietly WORKED would hand back an answer ruby never gives --
      # `//` matching everything is the worst of them.
      #
      # Two classes needed a new marker to tell the states apart, because no
      # existing field could: `IoBackend::Uninit` (an unopened stream is not a
      # closed one -- different message, and ruby names it by address rather than by
      # a path it has not got) and `QueueInner::initialized`. The Queue one is not
      # cosmetic: `SizedQueue.allocate`'s bound is 0, so an unguarded `push`
      # back-pressures on room that can never arrive and the program DEADLOCKS where
      # ruby raises.
      #
      # Every other class already had the state -- `Fiber::uninitialized`,
      # `RDir::open`, zlib's `closed` -- and only needed the blank to select it.

      require "stringio"
      require "strscan"
      require "zlib"
      require "date"

      def row(label)
        puts "#{label}\t#{(yield).inspect}"
      rescue ScriptError, StandardError => e
        puts "#{label}\t!#{e.class}: #{e.message}"
      end

      row("Regexp#source") { Regexp.allocate.source }
      row("Regexp#casefold?") { Regexp.allocate.casefold? }
      row("Regexp#to_s") { Regexp.allocate.to_s }
      # `#encoding` and `#==` are the two rows a blank Regexp DOES answer, and the
      # encoding is the binary one: there is no source to compute one from.
      row("Regexp#encoding") { Regexp.allocate.encoding }
      row("Regexp#==") { r = Regexp.allocate; r == r }

      row("Enumerator#each") { Enumerator.allocate.each { |x| x } }
      row("Enumerator#size") { Enumerator.allocate.size }
      row("Enumerator#inspect") { Enumerator.allocate.inspect }
      row("Lazy#inspect") { Enumerator::Lazy.allocate.inspect }
      row("Lazy#first") { Enumerator::Lazy.allocate.first }

      row("StringIO#read") { StringIO.allocate.read }
      row("StringIO#closed?") { StringIO.allocate.closed? }
      # `reopen` is the row that SEEDS a blank, so it is not a dead end.
      row("StringIO#reopen") { io = StringIO.allocate; io.reopen("hi"); io.read }

      row("StringScanner#scan") { StringScanner.allocate.scan(/a/) }
      row("StringScanner#inspect") { StringScanner.allocate.inspect }

      row("IO#fileno") { IO.allocate.fileno }
      row("IO#closed?") { IO.allocate.closed? }
      row("IO#path") { IO.allocate.path }
      row("File#size") { File.allocate.size }
      row("Dir#read") { Dir.allocate.read }
      row("Dir#path") { Dir.allocate.path }

      row("Queue#push") { Queue.allocate.push(1) }
      row("Queue#size") { Queue.allocate.size }
      row("Queue#closed?") { Queue.allocate.closed? }
      # The seeding row again: `initialize` makes a blank usable.
      row("Queue#initialize") { q = Queue.allocate; q.send(:initialize); q.push(1); q.pop }
      row("SizedQueue#push") { SizedQueue.allocate.push(1) }
      row("SizedQueue#max") { SizedQueue.allocate.max }

      row("Zlib::Deflate#deflate") { Zlib::Deflate.allocate.deflate("x") }
      row("Zlib::Deflate#closed?") { Zlib::Deflate.allocate.closed? }
      row("Fiber#resume") { Fiber.allocate.resume }

      # The blanks ruby lets you USE, which need no marker at all: an empty one IS
      # the blank, and every row reads it.
      row("Set#add") { s = Set.allocate; s.add(1); s.to_a }
      row("Mutex#lock") { m = Mutex.allocate; m.lock; m.unlock; "locked" }
      row("ThreadGroup#list") { ThreadGroup.allocate.list }
      row("WeakMap#size") { ObjectSpace::WeakMap.allocate.size }
      row("Date#to_s") { Date.allocate.to_s }
      row("Date#jd") { Date.allocate.jd }
      row("Process::Status#to_i") { Process::Status.allocate.to_i }
      # ...but `Process::Status` still names the state in `#inspect`, because pid 0
      # with a status word of 0 is a legal REAL status that `#to_s` prints the same.
      row("Process::Status#inspect") { Process::Status.allocate.inspect }
      row("Process::Status#to_s") { Process::Status.allocate.to_s }
    RUBY

    _(result).must_answer <<~'OUT'
      Regexp#source	!TypeError: uninitialized Regexp
      Regexp#casefold?	!TypeError: uninitialized Regexp
      Regexp#to_s	!TypeError: uninitialized Regexp
      Regexp#encoding	#<Encoding:BINARY (ASCII-8BIT)>
      Regexp#==	true
      Enumerator#each	!ArgumentError: uninitialized enumerator
      Enumerator#size	!ArgumentError: uninitialized enumerator
      Enumerator#inspect	"#<Enumerator: uninitialized>"
      Lazy#inspect	"#<Enumerator::Lazy: uninitialized>"
      Lazy#first	!ArgumentError: uninitialized enumerator
      StringIO#read	!IOError: uninitialized stream
      StringIO#closed?	!IOError: uninitialized stream
      StringIO#reopen	!IOError: uninitialized stream
      StringScanner#scan	!ArgumentError: uninitialized StringScanner object
      StringScanner#inspect	"#<StringScanner (uninitialized)>"
      IO#fileno	!IOError: uninitialized stream
      IO#closed?	!IOError: uninitialized stream
      IO#path	nil
      File#size	!IOError: uninitialized stream
      Dir#read	!IOError: closed directory
      Dir#path	nil
      Queue#push	!TypeError: #<Thread::Queue:0xADDR> not initialized
      Queue#size	!TypeError: #<Thread::Queue:0xADDR> not initialized
      Queue#closed?	false
      Queue#initialize	1
      SizedQueue#push	!TypeError: #<Thread::SizedQueue:0xADDR> not initialized
      SizedQueue#max	0
      Zlib::Deflate#deflate	!Zlib::Error: stream is not ready
      Zlib::Deflate#closed?	true
      Fiber#resume	!FiberError: uninitialized fiber
      Set#add	[1]
      Mutex#lock	"locked"
      ThreadGroup#list	[]
      WeakMap#size	0
      Date#to_s	"-4712-01-01"
      Date#jd	0
      Process::Status#to_i	0
      Process::Status#inspect	"#<Process::Status: uninitialized>"
      Process::Status#to_s	"pid 0 exit 0"
    OUT
  end

  it "date commercial week" do
    result = ze0(<<~'RUBY')
      require "date"

      d = Date.new(2024, 2, 29)
      p d.cwday
      p d.cweek
      p d.cwyear
      p Date.new(2021, 1, 1).cwyear
    RUBY

    _(result).must_answer <<~'OUT'
      4
      9
      2024
      2020
    OUT
  end

  it "date ctime asctime" do
    result = ze0(<<~'RUBY')
      require "date"

      d = Date.new(2024, 2, 29)
      p d.ctime
      p d.asctime
    RUBY

    _(result).must_answer <<~'OUT'
      "Thu Feb 29 00:00:00 2024"
      "Thu Feb 29 00:00:00 2024"
    OUT
  end

  it "date error and infinity classes" do
    result = ze0(<<~'RUBY')
      # `require "date"` defines two classes the native half cannot: `Date::Error`
      # (an ArgumentError subclass every invalid-date raise uses) and
      # `Date::Infinity`. A feature-gated native class cannot register a
      # constructible exception here, so both live in the gem's Ruby half and the
      # native half raises `Date::Error` by name -- the split `StringScanner::Error`
      # already takes.
      require "date"

      p Date::Error.superclass.to_s
      p Date::Error.ancestors.include?(ArgumentError)
      p Date::Error.name

      # Every invalid-date raise is a `Date::Error`, and `rescue ArgumentError`
      # still catches it.
      begin
        Date.new(2024, 2, 30)
      rescue => e
        p [e.class.to_s, e.message]
      end
      begin
        Date.parse("nope")
      rescue ArgumentError => e
        p [e.class.to_s, e.message]
      end
      begin
        Date.strptime("x", "%Y")
      rescue Date::Error => e
        p [e.class.to_s, e.message]
      end

      # `Date::Infinity` is a Numeric sentinel with a sign.
      p defined?(Date::Infinity)
      p Date::Infinity.superclass.to_s
      p Date::Infinity.ancestors.first(4).map(&:to_s)
      p Date::Infinity.instance_methods(false).sort

      i = Date::Infinity.new
      p [i.infinite?, i.finite?, i.zero?, i.nan?, i.to_f]
      p [i > 1, i < 1, i == i, (i <=> 5), (5 <=> i)]

      j = Date::Infinity.new(-1)
      p [j.to_f, j.infinite?, j < 1, (j <=> i), (i <=> j)]

      z = Date::Infinity.new(0)
      p [z.to_f, z.nan?, z.infinite?]

      p [(-i).to_f, (+i).to_f, i.abs.to_f]
      p [(i <=> Float::INFINITY), (i <=> -Float::INFINITY)]
      p i.coerce(3)
      p (i + 1 rescue $!.class.to_s)

      # A Date answers `infinite?` too.
      p Date.new(2024, 1, 1).infinite?
    RUBY

    _(result).must_answer <<~'OUT'
      "ArgumentError"
      true
      "Date::Error"
      ["Date::Error", "invalid date"]
      ["Date::Error", "invalid date"]
      ["Date::Error", "invalid date"]
      "constant"
      "Numeric"
      ["Date::Infinity", "Numeric", "Comparable", "Object"]
      [:+@, :-@, :<=>, :abs, :coerce, :d, :finite?, :infinite?, :nan?, :to_f, :zero?]
      [1, false, false, false, Infinity]
      [true, false, true, 1, -1]
      [-Infinity, -1, true, -1, 1]
      [0, true, nil]
      [-Infinity, Infinity, Infinity]
      [0, 1]
      [-1, 1]
      "NoMethodError"
      false
    OUT
  end

  it "date julian day numbers" do
    result = ze0(<<~'RUBY')
      require "date"

      d = Date.new(2024, 2, 29)
      p d.jd
      p d.mjd
      p d.ld
      p d.ajd
      p d.amjd
      p d.day_fraction
    RUBY

    _(result).must_answer <<~'OUT'
      2460370
      60369
      161210
      (4920739/2)
      (60369/1)
      0
    OUT
  end

  it "date range iterates" do
    result = ze0(<<~'RUBY')
      # A Range of Dates iterates via #succ (`to_a`, `each`, `step`); zeo
      # raises TypeError "can't iterate from Date". (Found by the 2026-08-24
      # probe sweep.)
      require "date"
      r = Date.new(2001, 1, 1)..Date.new(2001, 1, 3)
      p r.to_a.length
      p r.map(&:day)
    RUBY

    _(result).must_answer <<~'OUT'
      3
      [1, 2, 3]
    OUT
  end

  it "date weekday predicates" do
    result = ze0(<<~'RUBY')
      require "date"

      d = Date.new(2024, 2, 29)
      p d.monday?
      p d.thursday?
      p d.friday?
      p d.saturday?
      p d.sunday?
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      false
      false
      false
    OUT
  end

  it "module subclass" do
    result = ze0(<<~'RUBY')
      # `class X < Module` -- a module FACTORY, whose instances are real modules.
      #
      # This is NOT the value-subclass payload shape and must not become it: a
      # wrapper holding a module is not a module, so it would fail `include`,
      # `Module#===`, constant lookup and `ancestors`. Instead `X.new` mints a real
      # runtime module id and tags it as belonging to X, so only the question "what
      # is your class?" changes answer.
      #
      # 22 of the gem corpus's `Module` rows come from ONE file --
      # `activesupport/lib/active_support/deprecation/proxy_wrappers.rb` -- which
      # gates actioncable, actionmailer, actionview, activejob, activemodel,
      # activerecord, activestorage and the rest of the Rails stack.

      class LazilyDefineAttributes < Module
        def initialize(attributes)
          @attributes = attributes
        end

        def included(base)
          base.instance_variable_set(:@lazy, @attributes)
        end

        def attributes
          @attributes
        end
      end

      m = LazilyDefineAttributes.new([:a, :b])

      # Its class is the subclass, and it is a module all the same.
      p [m.class, m.is_a?(Module), m.is_a?(LazilyDefineAttributes), m.instance_of?(LazilyDefineAttributes)]
      p Module === m

      # A user instance method runs against it, and ivars persist across calls --
      # `initialize` wrote `@attributes`, `attributes` reads it back.
      p m.attributes

      # `include`ing one runs the user `included` hook, because the value really is
      # a module: `Module#include` reaches it unchanged.
      class Host
        include LazilyDefineAttributes.new([:x])
      end

      p Host.instance_variable_get(:@lazy)
      p Host.ancestors.include?(Module)

      # Reflection on the factory itself.
      p LazilyDefineAttributes.superclass
      p LazilyDefineAttributes.instance_of?(Class)

      # Ivars set from OUTSIDE reach the same store the method bodies use.
      m.instance_variable_set(:@extra, 9)
      p [m.instance_variable_get(:@extra), m.instance_variables.sort]

      # The Rails shape itself: a `self.new` override that can answer a NON-module,
      # and a subclass that inherits `initialize`.
      class DeprecatedConstantProxy < Module
        def self.new(*args, **options, &block)
          object = args.first
          return object unless object
          super
        end

        def initialize(old_const, new_const)
          @old_const = old_const
          @new_const = new_const
        end

        def inspect = "DeprecatedConstantProxy(#{@old_const} -> #{@new_const})"

        def target = @new_const
      end

      # `new` returning something that is not an instance of the class at all.
      p DeprecatedConstantProxy.new(nil)

      pr = DeprecatedConstantProxy.new("OLD", "NEW")
      p [pr.class, pr.inspect, pr.target, pr.is_a?(Module)]

      class Sub < DeprecatedConstantProxy
      end

      s = Sub.new("A", "B")
      p [s.class, s.target, s.is_a?(DeprecatedConstantProxy), s.is_a?(Module)]

      # A factory that defines no `initialize` at all takes no arguments -- `Module`'s
      # own must not run in its place.
      class Bare < Module
      end

      b = Bare.new
      p [b.class, b.is_a?(Module)]

      # `ObjectSpace::WeakMap` is the third native shape, and the cleanest: its
      # constructor already builds `WeakMap::new(class)` from the receiver, so a
      # subclass instance IS the native type -- no payload wrapper, no re-tagging.
      # activesupport's `DescendantsTracker::WeakSet` is the case, and it gates
      # eleven Rails gems on its own.
      class WeakSet < ObjectSpace::WeakMap
        alias_method :to_a, :keys

        def <<(object)
          self[object] = true
          self
        end
      end

      ws = WeakSet.new
      p [ws.class, ws.is_a?(ObjectSpace::WeakMap), WeakSet.superclass]

      one = "one"
      two = "two"
      ws << one
      ws << two
      p [ws.to_a.map(&:itself).sort, ws.size, ws[one]]

      # `Date`/`DateTime` are the fourth native shape, and the mirror image of a
      # payload root: the rows already allocate through the RECEIVER
      # (`RDate::new(jdn, class_of(recv))`, exactly as the equivalent CRuby function
      # threads `klass`), and an `RDate` carries its class id directly -- so there is
      # nothing to wrap and nothing to re-tag. tzinfo's `DateTimeWithOffset` is the
      # case, and activesupport reaches the ledger through it.
      require "date"

      class DateTimeWithOffset < DateTime
        attr_accessor :timezone_offset

        def set_timezone_offset(o)
          @timezone_offset = o
          self
        end
      end

      dt = DateTimeWithOffset.jd(2460000)
      p [dt.class, dt.is_a?(DateTime), dt.is_a?(Date), dt.year, dt.month, dt.day]

      # `RDate` carries no ivar storage of its own, so `@timezone_offset` lands in
      # the identity-keyed side table and reads back from it.
      p dt.set_timezone_offset("+09:00").timezone_offset

      # Every inherited constructor tags with the receiver, `new` included --
      # `Date.new` IS `Date.civil`, a class-method constructor.
      class MyDate < Date
      end

      p [MyDate.civil(2001, 2, 3).class, MyDate.parse("2001-02-03").class, MyDate.today.class]
      p [DateTimeWithOffset.new(2024, 5, 6).class, DateTimeWithOffset.superclass]
      p MyDate.civil(2001, 2, 3).to_s

      # The roots themselves are untouched.
      p [Date.today.class, DateTime.jd(2460000).class, Date.civil(2001, 2, 3).to_s]

      # `Proc` is the fifth native shape, and deliberately NOT a payload wrapper:
      # every call-site fast path, `&blk` conversion and `to_proc` matches on
      # `RubyValue::Proc`, so boxing one inside an object would break all of them.
      # The class rides in the proc itself instead. declarative's
      # `Declarative::Variables::Proc` is the case -- an empty subclass used purely
      # as a tag (`v.is_a?(Variables::Proc)`) on something that is still called.
      class Tagged < ::Proc
      end

      t = Tagged.new { |x| x * 2 }
      p [t.class, t.is_a?(Proc), t.is_a?(Tagged), Tagged.superclass]
      p [t.call(21), t.(21), t[21], t.arity, t.lambda?]

      # It is a real Proc everywhere a Proc is expected -- including as a block, which
      # is where a wrapper object would have failed.
      p [1, 2, 3].map(&t)

      def takes_block(&b)
        b.class
      end

      p takes_block(&t)

      # ...and the base class is untouched.
      p [Proc.new { 1 }.class, t.curry.class]
    RUBY

    _(result).must_answer <<~'OUT'
      [LazilyDefineAttributes, true, true, true]
      true
      [:a, :b]
      [:x]
      false
      Module
      true
      [9, [:@attributes, :@extra]]
      nil
      [DeprecatedConstantProxy, "DeprecatedConstantProxy(OLD -> NEW)", "NEW", true]
      [Sub, "B", true, true]
      [Bare, true]
      [WeakSet, true, ObjectSpace::WeakMap]
      [["one", "two"], 2, true]
      [DateTimeWithOffset, true, true, 2023, 2, 24]
      "+09:00"
      [MyDate, MyDate, MyDate]
      [DateTimeWithOffset, DateTime]
      "2001-02-03"
      [Date, DateTime, "2001-02-03"]
      [Tagged, true, true, Proc]
      [42, 42, 42, 1, false]
      [2, 4, 6]
      Tagged
      [Proc, Proc]
    OUT
  end

  it "range walks anything with succ" do
    result = ze0(<<~'RUBY')
      # `Range#each` falls through to `succ` for ANY value that answers it --
      # CRuby's `range_each` does exactly that test, which is what makes a Date
      # range iterable and what any user class with `succ` and `<=>` gets free.
      #
      # Only three types had walks of their own (Integer, String, Symbol), so
      # everything else answered `can't iterate from <Class>` -- including Date,
      # which is the shape gems actually write.

      require "date"

      r = Date.new(2001, 1, 1)..Date.new(2001, 1, 3)
      p r.to_a.length
      p r.map(&:day)
      p r.first(2).map(&:day)
      p r.include?(Date.new(2001, 1, 2))
      p (Date.new(2001, 1, 1)...Date.new(2001, 1, 3)).to_a.length

      # A user class needs only the two methods.
      class Tick
        include Comparable
        attr_reader :n

        def initialize(n) = @n = n
        def succ = Tick.new(@n + 1)
        def <=>(o) = @n <=> o.n
        def inspect = "T#{@n}"
      end

      p (Tick.new(1)..Tick.new(4)).to_a
      p (Tick.new(1)...Tick.new(4)).to_a
      p (Tick.new(1)..Tick.new(4)).map(&:n)
      p (Tick.new(3)..Tick.new(1)).to_a

      # A value with NO `succ` still cannot be walked, and ruby names the class.
      begin
        (1.0..2.0).each { }
      rescue TypeError => e
        puts e.message
      end
      begin
        (nil..3).each { }
      rescue TypeError => e
        puts e.message
      end

      # The three built-in walks are untouched.
      p (1..4).to_a
      p ("a".."d").to_a
      p (:a..:d).to_a
      p (2**70..2**70 + 2).to_a.length

      # `reverse_each` on an ENDLESS range refuses LAZILY: blockless it answers
      # an Enumerator, and the raise comes when it is walked.
      e = (1..).reverse_each
      puts e.class
      begin
        e.next
      rescue TypeError => err
        puts err.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      3
      [1, 2, 3]
      [1, 2]
      true
      2
      [T1, T2, T3, T4]
      [T1, T2, T3]
      [1, 2, 3, 4]
      []
      can't iterate from Float
      can't iterate from NilClass
      [1, 2, 3, 4]
      ["a", "b", "c", "d"]
      [:a, :b, :c, :d]
      3
      Enumerator
      can't iterate from NilClass
    OUT
  end

  it "strftime case flags" do
    result = ze0(<<~'RUBY')
      # `%#` changes a field's case as a whole -- all-uppercase becomes lowercase,
      # anything else becomes uppercase -- rather than swapping it per character.
      # Per-character swapcase turned "January" into "jANUARY" where CRuby answers
      # "JANUARY"; only fields that are already uppercase (%p, %Z) agreed. Found
      # when a clang build refused lib/sp_time.c for calling tolower with no
      # <ctype.h>, which made the implicit int return the thing to look at.
      t = Time.at(0).utc
      p t.strftime("%#B")
      p t.strftime("%#b")
      p t.strftime("%#A")
      p t.strftime("%#a")
      p t.strftime("%#p")
      p t.strftime("%#P")
      p t.strftime("%#Z")
      p t.strftime("%#j")
      p t.strftime("%^a")
      p t.strftime("%^B")
    RUBY

    _(result).must_answer <<~'OUT'
      "JANUARY"
      "JAN"
      "THURSDAY"
      "THU"
      "am"
      "AM"
      "utc"
      "001"
      "THU"
      "JANUARY"
    OUT
  end

  it "strftime directive surface" do
    result = ze0(<<~'RUBY')
      # The whole `strftime` directive table for both engines. `Time` and `date`
      # share one renderer, and differ in exactly two places: `date` adds `%Q`/`%+`,
      # and a trailing incomplete directive is an ArgumentError for Time where
      # `date` echoes it.
      t = Time.utc(2024, 2, 29, 5, 7, 9, 123456)
      ["%c","%x","%X","%D","%F","%T","%R","%r","%v","%s","%L","%3L","%6L","%9L","%N","%3N",
       "%Y %C %y %m %d %e %j %H %k %I %l %M %S %p %P %u %w %a %A %b %B %h %Z %z %:z %::z",
       "%U %W %V %G %g","%Ey %EY %Od %Om %OH %Ec %EX","%-e|%0e|%_e|%-k|%0k|%-l|%0l",
       "%^a %#A %^Z %#p","%10a|%-10a|%010d","%%","%n%t"].each { |f| p t.strftime(f) }
      ["%","%Y%","%-","abc%","%E","%O"].each { |f| begin; p t.strftime(f); rescue => e; p [e.class, e.message]; end }
      require "date"
      d = Date.new(2024,2,29)
      ["%c","%x","%v","%Ey %Od","%","%Y%","%L","%N","%s","%Q","%+"].each { |f| p d.strftime(f) }
    RUBY

    _(result).must_answer <<~'OUT'
      "Thu Feb 29 05:07:09 2024"
      "02/29/24"
      "05:07:09"
      "02/29/24"
      "2024-02-29"
      "05:07:09"
      "05:07"
      "05:07:09 AM"
      "29-FEB-2024"
      "1709183229"
      "123"
      "123"
      "123456"
      "123456000"
      "123456000"
      "123"
      "2024 20 24 02 29 29 060 05  5 05  5 07 09 AM am 4 4 Thu Thursday Feb February Feb UTC +0000 +00:00 +00:00:00"
      "08 09 09 2024 24"
      "24 2024 29 02 05 Thu Feb 29 05:07:09 2024 05:07:09"
      "29|29|29|5|05|5|05"
      "THU THURSDAY UTC am"
      "       Thu|Thu|0000000029"
      "%"
      "\n\t"
      [ArgumentError, "invalid format: %"]
      [ArgumentError, "invalid format: %Y%"]
      [ArgumentError, "invalid format: %-"]
      [ArgumentError, "invalid format: abc%"]
      "%E"
      "%O"
      "Thu Feb 29 00:00:00 2024"
      "02/29/24"
      "29-FEB-2024"
      "24 29"
      "%"
      "2024%"
      "000"
      "000000000"
      "1709164800"
      "1709164800000"
      "Thu Feb 29 00:00:00 +00:00 2024"
    OUT
  end

  it "strftime modifiers" do
    result = ze0(<<~'RUBY')
      t001 = Time.utc(2024, 2, 29, 5, 7, 9, 123456)
      p t001.strftime("%Ey %EY %Od %Om %OH")
      p t001.strftime("%6L")
      p t001.strftime("%9L")
      p t001.strftime("%-e|%0e|%_e|%-k|%0k|%-l|%0l")
      r001 = (t001.strftime("%") rescue $!.class); p r001
      r002 = (t001.strftime("%Y%") rescue $!.class); p r002
      p t001.strftime("%Y-%m-%d %H:%M:%S")
      p t001.strftime("%L")
    RUBY

    _(result).must_answer <<~'OUT'
      "24 2024 29 02 05"
      "123456"
      "123456000"
      "29|29|29|5|05|5|05"
      ArgumentError
      ArgumentError
      "2024-02-29 05:07:09"
      "123"
    OUT
  end

  it "strftime week and pad directives" do
    result = ze0(<<~'RUBY')
      # Four `strftime` directives are not implemented and pass through as their own
      # literal text -- `%U`, `%W`, `%V` and `%G` -- so a format string asking for a
      # week number gets the two characters back instead:
      #
      #     Time.at(1_700_000_000).utc.strftime("%U %W %V %G")
      #     ruby "46 46 46 2023"      zeo "%U %W %V %G"
      #
      # Emitting the directive verbatim is the worst available failure: nothing
      # raises, and a log line or a filename silently contains "%U" forever. `%V`/%G`
      # are the ISO week-date pair, which is what a weekly rollup or a report bucket
      # keys on.
      #
      # Two flag bugs ride along: `%0e` ignores its zero-pad request (`" 1"` for
      # `"01"`), and `%#A` swapcases rather than upcases, turning "Thursday" into
      # "tHURSDAY" instead of "THURSDAY".
      #
      # Everything else in the probe agrees, including `%j`, `%a`, `%b`, the `%D`/
      # `%F`/`%T`/`%R`/`%r`/`%c`/`%x`/`%X` combinations and the `%-`/`%_`/`%^` flags.

      t0 = Time.at(0).utc
      p [t0.strftime("%U"), t0.strftime("%W"), t0.strftime("%V"), t0.strftime("%G")]
      p Time.at(1_700_000_000).utc.strftime("%U %W %V %G")

      p [t0.strftime("%0e"), t0.strftime("%#A")]

      # Already correct -- a fix must not disturb these.
      p [t0.strftime("%-d"), t0.strftime("%_d"), t0.strftime("%^a")]
      p [t0.strftime("%D"), t0.strftime("%F"), t0.strftime("%T"), t0.strftime("%R")]
      p Time.at(1_700_000_000).utc.strftime("%j %a %b %Y")
    RUBY

    _(result).must_answer <<~'OUT'
      ["00", "00", "01", "1970"]
      "46 46 46 2023"
      ["01", "THURSDAY"]
      ["1", " 1", "THU"]
      ["01/01/70", "1970-01-01", "00:00:00", "00:00"]
      "318 Tue Nov 2023"
    OUT
  end

  it "strftime zone offset flags" do
    result = ze0(<<~'RUBY')
      # `%z` ignores the `-` and `_` pad flags. zeo answers the plain `%z` string
      # for all three spellings; ruby answers something else for each:
      #
      #     Time.at(0).utc.strftime("%-z")   ruby "-0000"   zeo "+0000"
      #     Time.at(0).utc.strftime("%_z")   ruby " +000"   zeo "+0000"
      #
      # Ruby's answers are artifacts rather than intent -- `%z` renders through the
      # same width/precision macro every numeric directive uses, so `-` (which forces
      # precision 1 and clears the pad) and `_` (which pads with spaces) reach a value
      # whose sign has already been folded in, and the result loses a digit or grows
      # one. They are still what the oracle prints, which is what makes this a
      # divergence rather than a preference.
      #
      # zeo's `%z` is `offset_str`, which reads neither `pad` nor `width` -- the flag
      # loop parses them and the directive never asks. `%0z` and `%^z` agree by
      # accident, since ruby's answer for those IS the plain form.
      #
      # Found by differential probe while implementing `%U`/`%W`/`%V`/`%G`; every
      # other directive-and-flag pair in that sweep (129,600 cases) matches.

      t = Time.at(0).utc
      p [t.strftime("%z"), t.strftime("%-z"), t.strftime("%_z")]

      e = Time.at(0).localtime("+05:30")
      p [e.strftime("%z"), e.strftime("%-z"), e.strftime("%_z")]

      w = Time.at(0).localtime("-08:00")
      p [w.strftime("%z"), w.strftime("%-z"), w.strftime("%_z")]

      # The colon forms and the unflagged spellings already agree.
      p [t.strftime("%0z"), t.strftime("%^z"), t.strftime("%:z"), t.strftime("%::z")]
      p [e.strftime("%:z"), w.strftime("%::z")]
    RUBY

    _(result).must_answer <<~'OUT'
      ["+0000", "-0000", " +000"]
      ["+0530", "+0530", " +530"]
      ["-0800", "-0800", " -800"]
      ["+0000", "+0000", "+00:00", "+00:00:00"]
      ["+05:30", "-08:00:00"]
    OUT
  end

  it "time strftime directives" do
    result = ze0(<<~'RUBY')
      t = Time.utc(2026, 7, 16, 13, 45, 30) + 0.123456789
      p t.strftime("%P")   # lowercase am/pm
      p t.strftime("%L")   # milliseconds
      p t.strftime("%6N")  # fractional seconds, 6 digits
      p t.strftime("%^A")  # upcase flag
      p t.strftime("%3S")  # width modifier
      p t.strftime("%+")   # not a Time#strftime directive in CRuby
      p t.strftime("%10Y") # width modifier on %Y
      p Time.utc(2026, 7, 16).strftime("%:z")  # colon offset
    RUBY

    _(result).must_answer <<~'OUT'
      "pm"
      "123"
      "123456"
      "THURSDAY"
      "030"
      "%+"
      "0000002026"
      "+00:00"
    OUT
  end

  it "time strftime directives 2" do
    result = ze0(<<~'RUBY')
      # `strftime`'s directive table, including Ruby's `-`/`_` padding flags and
      # the verbatim-unknown-directive rule.

      t = Time.at(1700000000).getutc
      puts t.strftime("%Y-%m-%d %H:%M:%S")
      puts t.strftime("%F %T")
      puts t.strftime("%a %A %b %B")
      puts t.strftime("%j %u %w %p %I")
      puts t.strftime("%z %Z")
      puts t.strftime("%y %C %s")
      puts t.strftime("100%% literal")
      puts t.strftime("%Q")
      jan = Time.at(1704067200).getutc
      puts jan.strftime("%m|%-m|%_m")
    RUBY

    _(result).must_answer <<~'OUT'
      2023-11-14 22:13:20
      2023-11-14 22:13:20
      Tue Tuesday Nov November
      318 2 2 PM 10
      +0000 UTC
      23 20 1700000000
      100% literal
      %Q
      01|1| 1
    OUT
  end

  it "time strftime epoch zone" do
    result = ze0(<<~'RUBY')
      t = Time.utc(2026, 7, 16, 13, 45, 30)
      p t.strftime("%z")   # zone offset
      p t.strftime("%s")   # seconds since epoch
      p t.to_i             # correct epoch seconds, for comparison
    RUBY

    _(result).must_answer <<~'OUT'
      "+0000"
      "1784209530"
      1784209530
    OUT
  end

  it "time strftime z minimal" do
    result = ze0(<<~'RUBY')
      # %:::z collapses the UTC offset to the minimal precision that loses nothing
      # (#2713); a fixed-offset time (Time.at in:) reports its own offset.
      t = Time.utc(2026, 7, 16, 13, 45, 30)
      p t.strftime("%:z")
      p t.strftime("%::z")
      p t.strftime("%:::z")
      p Time.at(0, in: "+05:30").strftime("%:::z")
      p Time.at(0, in: "+05:00").strftime("%:::z")
      p Time.at(0, in: "-08:00").strftime("%:::z")
      # bare %z comes from the receiver's own offset, never C strftime's tm_gmtoff
      # (platform-varying; macOS reported the machine-local zone for a UTC receiver)
      p t.strftime("%z")
      p Time.at(0, in: "+05:30").strftime("%z")
      p Time.at(0, in: "-08:00").strftime("%z")
    RUBY

    _(result).must_answer <<~'OUT'
      "+00:00"
      "+00:00:00"
      "+00"
      "+05:30"
      "+05"
      "-08"
      "+0000"
      "+0530"
      "-0800"
    OUT
  end

  it "yaml date time scalars are gated" do
    result = ze0(<<~'RUBY')
      # A bare date or timestamp scalar is a TYPED value psych gates behind
      # `permitted_classes` -- plain `safe_load` RAISES Psych::DisallowedClass
      # for `2001-12-14`, and with `[Time]` permitted the timestamp loads as a
      # real Time. zeo answers plain strings in every case. (Found by the
      # 2026-08-24 probe sweep.)
      require "yaml"
      require "date"
      def show
        p yield
      rescue Psych::DisallowedClass => e
        puts "#{e.class}: #{e.message}"
      end
      show { YAML.safe_load("d: 2001-12-14") }
      show { YAML.safe_load("t: 2001-12-14 21:59:43.10 -5") }
      show { YAML.safe_load("t: 2001-12-14 21:59:43 -05:00", permitted_classes: [Time]) }
      show { YAML.safe_load("d: 2001-12-14", permitted_classes: [Date]) }
    RUBY

    _(result).must_answer <<~'OUT'
      Psych::DisallowedClass: Tried to load unspecified class: Date
      Psych::DisallowedClass: Tried to load unspecified class: Time
      {"t" => 2001-12-14 21:59:43 -0500}
      {"d" => #<Date: 2001-12-14 ((2452258j,0s,0n),+0s,-Infj)>}
    OUT
  end

  it "yaml dump styles" do
    result = ze0(<<~'RUBY')
      # Psych's emitter styles: a multiline string dumps as a literal block
      # (`|` / `|-`), binary as `!binary`, unicode plain (unquoted), infinity
      # as `.inf`, Time/Date as native scalars, a Range with its `!ruby/range`
      # tag, a nil key as `! ''`, a leading-space string double-quoted; the
      # `indentation:`/`line_width:`/`header:` options are honored; and two
      # references to ONE object dump as an anchor and alias (`&1`/`*1`). zeo
      # quotes-and-inlines everything and ignores the options. (Found by the
      # 2026-08-24 probe sweep.)
      require "yaml"
      require "date"
      p YAML.dump({ "s" => "l1\nl2\n" })
      p YAML.dump({ "s" => "l1\nl2" })
      p YAML.dump("\xFF\x00".b)
      p YAML.dump("héllo")
      p YAML.dump(" pad")
      p YAML.dump(Float::INFINITY)
      p YAML.dump(Time.utc(2001, 2, 3, 4, 5, 6))
      p YAML.dump(Date.new(2001, 2, 3))
      p YAML.dump(1..3)
      p YAML.dump({ nil => 1 })
      p YAML.dump({ "a" => { "b" => 1 } }, indentation: 4)
      p YAML.dump({ "s" => ("word " * 20).strip }, line_width: 20).lines.length > 2
      p YAML.dump({ "a" => 1 }, header: true)
      shared = [1]
      p YAML.dump({ "a" => shared, "b" => shared })
    RUBY

    _(result).must_answer <<~'OUT'
      "---\ns: |\n  l1\n  l2\n"
      "---\ns: |-\n  l1\n  l2\n"
      "--- !binary |-\n  /wA=\n"
      "--- héllo\n"
      "--- \" pad\"\n"
      "--- .inf\n"
      "--- 2001-02-03 04:05:06.000000000 Z\n"
      "--- 2001-02-03\n"
      "--- !ruby/range\nbegin: 1\nend: 3\nexcl: false\n"
      "---\n! '': 1\n"
      "---\na:\n    b: 1\n"
      true
      "%YAML 1.1\n---\na: 1\n"
      "---\na: &1\n- 1\nb: *1\n"
    OUT
  end
end
