module Zr::Kern
  # The heap. Cells have four sizes (32, 64, 128 and 256 bytes) and come
  # from arenas. Each cell's state is a bit in its arena's bitmaps. A
  # precise mark-sweep collector starts from the task's frame records and
  # the globals. A freed cell is poisoned and loses FL_ALLOCATED, and the
  # mark phase aborts on a reference to one: a live object that points at
  # a freed cell is a missed root. Under ZR_GC_STRESS, every allocation
  # collects first and never reuses a cell, so a stale pointer finds the
  # poison, not a new object.
  #
  # An arena is ARENA_CELLS cells of one size after a head that describes
  # it. It is aligned to ARENA_BYTES, so a cell's arena is its address with
  # the low bits cleared. Four bitmaps are between the head and the cells:
  # the marks, the ages, the remembered set and the allocated cells. A mark
  # is a bit, never a write into the cell. Thus a collection does not touch
  # the pages that a fork shares, and a sweep reads one word to skip 64
  # live cells.
  #
  # An allocation (`zr_alloc`) takes the first clear bit of the allocated
  # word at its size class's cursor. No cell is read or written before an
  # allocation gives it out, so a new arena costs only its bitmaps. The
  # sweep frees only the cells that died in this collection
  # (`allocated & ~marks`, walked by `ctz`), and writes the marks over the
  # allocated map. It does not touch a cell that was already free. A
  # `popcnt` gives the free count. The arenas that the sweep left with room
  # make the size class's list for the cursor, in address order. An arena
  # with no live cell is reserved: no sweep reads it again, and the cursor
  # takes it when the list is empty. The collector runs when both are
  # empty, and grows each size to two times its live cells. At start, the
  # heap is four arenas of 32,768 cells in total. A malloc'd table that
  # doubles when full lists the arenas, so the heap has no limit but the
  # machine's memory.
  ARENA_BYTES = 4194304
  ARENA_HEAD = 256
  ARENA_CELLS = 8192
  ARENA_TABLE = 64
  # MARK_BYTES: the bytes of an arena's mark bitmap, one bit for each cell.
  # ARENA_MAPS: the number of bitmaps of that shape before the cells (the
  # marks, the ages, the remembered set, the allocated cells, the two bits
  # of each cell's count and the barrier's stores). ALL_MARKED:
  # a bitmap word in which all cells are live. The compiler's barrier reads
  # the first two (`Zr::Lower::Function#cell_barrier`).
  MARK_BYTES = ARENA_CELLS >> 3
  ARENA_MAPS = 7
  ALL_MARKED = 0 - 1
  CELL_MIN = 32
  CELL_MAX = 256
  SIZE_CLASSES = 4
  POISON = 57005 << 8

  # An arena's head: its cell size, that size as a shift, the number of
  # cells after the head, and its size class's index. `next` links it into
  # its size class's list of arenas with room. For a reserved arena (all
  # cells free, no sweep reads it), `next` links it into the reserved list.
  class ArenaHead < Layout
    attr_accessor :cell #: word
    attr_accessor :shift #: word
    attr_accessor :ncells #: word
    attr_accessor :index #: word
    attr_accessor :reserved #: word
    attr_accessor :remembered #: word
    attr_accessor :next #: ptr
    attr_accessor :exivars #: ptr
    # Two words each, one bit for each RELEASE_PAGE of the cells
    # (zr_arena_pages_trim).
    attr_accessor :idle_low #: word
    attr_accessor :idle_high #: word
    attr_accessor :gone_low #: word
    attr_accessor :gone_high #: word
  end

  # One cell size. `cursor` is the allocated-map word that gives the next
  # cell (`zr_full` while the cursor is in no arena). `origin` and `shift`
  # (the cell size as a shift) convert a cursor word's address and bit into
  # a cell address. `room` is its arenas with room, in address order.
  # `freed` is the free cells after the last sweep. Then its arena count,
  # its reserved arenas, and the number of objects it has allocated.
  class SizeClass < Layout
    attr_accessor :cursor #: ptr
    attr_accessor :origin #: ptr
    attr_accessor :shift #: word
    attr_accessor :room #: ptr
    attr_accessor :freed #: word
    attr_accessor :arenas #: word
    attr_accessor :reserve #: ptr
    attr_accessor :allocated #: word
  end

  # Heap state: the collection count, the stress flag, the arena count,
  # the time spent collecting, the arena table and its capacity, the
  # malloc'd payload bytes (zr_xmalloc, zr_xfree) and the limit that starts
  # the collector, whether an allocation takes the slow path
  # (zr_heap_slow_update), the collection counts and times by kind, whether
  # ZR_GC_TRACE is on, the collection number and freed bytes of the last
  # major, what started the last collection and why it was major
  # (`last_info`, GC_INFO_*), and the weak references that its prune saw
  # and kept. `by_address` is the arena table again, in address order, for
  # the conservative scan of C's frames (zr_live_cell_p); `collecting` is
  # set while a collection runs.
  class Heap < Layout
    attr_accessor :collections #: word
    attr_accessor :stress #: word
    attr_accessor :disabled #: word
    attr_accessor :arenas #: word
    attr_accessor :nanoseconds #: word
    attr_accessor :table #: ptr
    attr_accessor :capacity #: word
    attr_accessor :malloced #: word
    attr_accessor :malloc_limit #: word
    attr_accessor :slow #: word
    attr_accessor :minors #: word
    attr_accessor :verify #: word
    attr_accessor :verifying #: word
    attr_accessor :live #: word
    attr_accessor :old_limit #: word
    # RUBY_GC_HEAP_OLDOBJECT_LIMIT_FACTOR, in hundredths (OLD_LIMIT_FACTOR).
    attr_accessor :old_factor #: word
    attr_accessor :majors #: word
    attr_accessor :marking #: word
    attr_accessor :sweeping #: word
    attr_accessor :trace #: word
    attr_accessor :last_major #: word
    attr_accessor :reclaimed #: word
    attr_accessor :last_info #: word
    attr_accessor :weak_refs #: word
    attr_accessor :unmeasured #: word
    attr_accessor :released #: word
    attr_accessor :freed_pages #: word
    attr_accessor :by_address #: ptr
    attr_accessor :collecting #: word
    attr_accessor :malloc_total #: word
    attr_accessor :free_total #: word
  end

  # The bits of Heap#last_info, which GC.latest_gc_info reads: GC.start
  # ran the collection (1), the payload was over its limit (2), the sweep
  # was not immediate (4: GC.start asked so, or an allocation started the
  # collection), and why a major ran, in the bits
  # from 8 up: GC.start asked for it, the old objects grew, or a minor
  # freed too little. A minor has no reason.
  # Heap#stress: off (0), on with minor collections (ZR_GC_STRESS, or a
  # GC.stress number with CRuby's "no major" bit), or on with a full mark
  # each time, as GC.stress = true is in CRuby.
  STRESS_MINOR = 1
  STRESS_FULL = 2

  GC_INFO_METHOD = 1
  GC_INFO_MALLOC = 2
  GC_INFO_LAZY = 4
  GC_INFO_FORCE = 8
  GC_INFO_OLDGEN = 16
  GC_INFO_NOFREE = 24

  # The rows that GC::Profiler reads: while `on`, each collection appends
  # PROFILE_ROW words to the malloc'd `rows` (`zr_gc_profile_push`). With
  # a `max` (GC::Profiler.configure's max_records; 0 for none), the rows
  # are a ring of that many, whose oldest is at `head` once it is full.
  # `sequence` numbers every row since the start, through a clear.
  class GcProfile < Layout
    attr_accessor :on #: word
    attr_accessor :rows #: ptr
    attr_accessor :count #: word
    attr_accessor :capacity #: word
    attr_accessor :max #: word
    attr_accessor :head #: word
    attr_accessor :sequence #: word
    attr_accessor :configured #: word
  end

  # A profile row's words: the monotonic start in nanoseconds, the
  # nanoseconds it took, the live bytes and all bytes after it, the cells
  # of all arenas, flags (1: major, 2: GC.start or stress asked), the
  # nanoseconds of the mark and of the sweep, and the row's sequence number.
  PROFILE_ROW = 9

  # GC_PROFILE_RECORD_DEFAULT_MAX_RECORDS: the rows that the profiler keeps
  # until GC::Profiler.configure sets another number.
  PROFILE_MAX_DEFAULT = 4096

  # The payload increase that a collection permits before the next
  # collection starts for that reason, and the limits on that increase.
  # CRuby keeps the same counter between GC_MALLOC_LIMIT_MIN and
  # GC_MALLOC_LIMIT_MAX (16 and 32 MB), and grows it by 1.4 times the live
  # payload. These limits are four times CRuby's, because a collection here
  # marks all objects where CRuby's marks the young. A limit is necessary:
  # with `malloced * 2`, a build with 4 GB of payload collects only at 8 GB.
  MALLOC_LIMIT = 67108864
  MALLOC_LIMIT_MAX = 134217728
  MALLOC_GROWTH = 140

  # The free cells that a size class must have after a sweep, as hundredths
  # of its capacity, and the maximum growth in one collection. The shape is
  # CRuby's `heap_allocatable_slots_expand`: it grows a heap only when the
  # sweep left it below the free floor, grows it to the goal, and never by
  # more than the factor in one step (0.20, 0.40 and 1.8 in
  # gc/default/default.c). The goal here is half, not two fifths, because
  # a collection marks all objects: a class that grows has two times its
  # live set.
  FREE_FLOOR = 20
  FREE_GOAL = 50
  GROWTH = 180

  # The limit on old-generation growth before a major collection runs, as
  # a multiple of the live set of the last major, and the minimum for that
  # limit. A minor frees young dead objects and skips all older objects.
  # Thus only a major frees a dead old graph or the floating garbage that a
  # minor leaves. It is CRuby's `old_objects_limit`, which is also two
  # times the live count of the last major.
  OLD_LIMIT_FACTOR = 2
  OLD_LIMIT_MIN = 16777216

  # The old-generation limit after a major: `old_factor` hundredths of the
  # live set, at least OLD_LIMIT_MIN. A factor below one makes every
  # collection a major one, as CRuby's does when its limit is below the
  # old objects.
  #: (ptr, word) -> void
  def zr_old_limit_update(h, live)
    if Heap[h].old_factor < 100
      Heap[h].old_limit = 0
      return
    end
    limit = (live / 100) * Heap[h].old_factor
    Heap[h].old_limit = limit < OLD_LIMIT_MIN ? OLD_LIMIT_MIN : limit
  end

  # Makes each allocated cell old, as rb_gc_prepare_heap does for
  # Process.warmup after its major collection: then each live cell is
  # old, so none contains a young object and none needs to be remembered.
  #: () -> value
  def zr_gc_promote_all
    n = Heap[zr_heap()].arenas
    i = 0
    while i < n
      a = zr_arena_at(i)
      if ArenaHead[a].reserved == 0
        zr_memcpy(zr_arena_ages(a), zr_arena_allocated(a), MARK_BYTES)
        Libc.memset(zr_arena_remembered(a), Machine.i32(0), MARK_BYTES)
        Libc.memset(zr_arena_count_low(a), Machine.i32(0), MARK_BYTES * 3)
        ArenaHead[a].remembered = 0
      end
      i += 1
    end
    Machine.value(QNIL)
  end

  # RUBY_GC_HEAP_OLDOBJECT_LIMIT_FACTOR, which GC.read_tuning gives in
  # hundredths.
  #: (value) -> value
  def zr_gc_old_factor_set_m(hundredths)
    h = zr_heap()
    Heap[h].old_factor = zr_fix2long(hundredths)
    zr_old_limit_update(h, Heap[h].live)
    Machine.value(QNIL)
  end

  # A second limit: the number of minor collections before a major, even
  # if the old set does not grow. A program with a constant old generation
  # still needs its weak references and finalizers processed.
  #
  # A heap at its share of the machine asks for a major sooner, because
  # only a major frees an old dead graph. It does not ask for a major every
  # time: that makes the collector non-generational where the heap is
  # largest and a trace costs most. On a cold self-compile, it made 100 of
  # 114 collections major, and most of the 231.1 s of marking.
  #
  # A pressed heap keeps the short interval only while its last major freed
  # at least this fraction of the live set. Otherwise it uses the normal
  # interval. A cold self-compile under the compiled compiler had 6 GB live
  # and no old dead objects, and each fourth collection traced 6 GB in three
  # seconds to free 15 MB.
  MAJOR_EVERY = 16
  MAJOR_EVERY_PRESSED = 4
  MAJOR_YIELD = 16

  # The number of collections after a major before a minor that left a size
  # class short can force another major. In that interval, the class grows
  # instead: the last major showed that live objects fill it, and a second
  # trace shows the same. CRuby's `gc_sweep_finish_heap` delays NOFREE
  # majors for RVALUE_OLD_AGE collections in the same way. Without this,
  # on a cold self-compile under the compiled compiler, a short class forced
  # 60 of 62 majors. Each traced 6 GB in four seconds to free 4 MB.
  MAJOR_AGE = 3

  # The share of the machine's memory, in hundredths, that the cells can
  # use before growth goes down to the floor. Above it, a collection costs
  # less than a page-in, so the collector runs more frequently and asks for
  # no more memory. Six compiler workers with no limit put a 16 GB machine
  # into 16.4 GB of swap. A run that swaps does not fail, but it takes ten
  # times as long.
  HEAP_SHARE = 50

  #: () -> ptr
  def zr_heap
    Machine.static(:heap, Heap.size)
  end

  #: (word) -> ptr
  def zr_arena_at(i)
    Machine.ptr(Machine.load64(Heap[zr_heap()].table + (i * 8), 0))
  end

  # Makes room in the arena table for one more arena.
  #: () -> void
  def zr_arena_table_grow
    h = zr_heap()
    n = Heap[h].arenas
    if n < Heap[h].capacity
      return
    end
    capacity = n == 0 ? ARENA_TABLE : n * 2
    table = zr_xmalloc(capacity * 8)
    by_address = zr_xmalloc(capacity * 8)
    if n != 0
      zr_memcpy(table, Heap[h].table, n * 8)
      zr_memcpy(by_address, Heap[h].by_address, n * 8)
      zr_xfree(Heap[h].table)
      zr_xfree(Heap[h].by_address)
    end
    Heap[h].table = table
    Heap[h].by_address = by_address
    Heap[h].capacity = capacity
  end

  # Adds arena `a` to the table in address order. The arena table keeps
  # the order in which the arenas came, because a walk of the heap can
  # allocate, and a new arena must not move the ones it has yet to visit.
  #: (ptr) -> void
  def zr_arena_index_add(a)
    h = zr_heap()
    index = Heap[h].by_address
    i = Heap[h].arenas
    while i > 0 && Machine.ptr(Machine.load64(index + ((i - 1) * 8), 0)) > a
      Machine.store64(index + (i * 8), 0, Machine.load64(index + ((i - 1) * 8), 0))
      i -= 1
    end
    Machine.store64(index + (i * 8), 0, Machine.word(a))
  end

  # Whether `a` is the base of one of the heap's arenas: a binary search
  # of the table in address order.
  #: (ptr) -> bool
  def zr_arena_p(a)
    h = zr_heap()
    index = Heap[h].by_address
    lo = 0
    hi = Heap[h].arenas
    while lo < hi
      mid = (lo + hi) >> 1
      at = Machine.ptr(Machine.load64(index + (mid * 8), 0))
      if at == a
        return true
      end
      if at < a
        lo = mid + 1
      else
        hi = mid
      end
    end
    false
  end

  # Whether the word `w` is a live cell: the scan of C's frames reads
  # words that can be anything, so each test comes before the read that
  # needs it. It must be in an arena, at the start of a cell (CRuby's
  # contract keeps a pointer to the start of each object that C uses), and
  # allocated.
  #: (word) -> bool
  def zr_live_cell_p(w)
    if (w & 7) != 0 || w == 0
      return false
    end
    a = Machine.ptr(w & (0 - ARENA_BYTES))
    unless zr_arena_p(a)
      return false
    end
    first = Machine.word(zr_arena_first(a))
    if w < first
      return false
    end
    offset = w - first
    i = offset >> ArenaHead[a].shift
    if i >= ArenaHead[a].ncells || (offset & (ArenaHead[a].cell - 1)) != 0
      return false
    end
    if (Machine.load64(zr_arena_allocated(a) + ((i >> 6) * 8), 0) & zr_marks_bit(i)) == 0
      return false
    end
    (Machine.load64(Machine.ptr(w), 0) & FL_ALLOCATED) != 0
  end

  # Whether the word `w` is an address in one of the heap's arenas, a
  # cell or not. An arena is aligned to ARENA_BYTES but is smaller, and
  # malloc may give the rest of that span to other blocks (musl's does),
  # so an address past the arena's last cell is not in it.
  #: (word) -> bool
  def zr_heap_address_p(w)
    a = Machine.ptr(w & (0 - ARENA_BYTES))
    unless zr_arena_p(a)
      return false
    end
    w < Machine.word(zr_arena_first(a)) + (ArenaHead[a].ncells * ArenaHead[a].cell)
  end

  # Marks the word `w` if it is a live cell, as CRuby's
  # rb_gc_mark_maybe does.
  #: (word) -> void
  def zr_mark_maybe(w)
    if zr_live_cell_p(w)
      zr_mark(Machine.value(w))
    end
  end

  # Marks each word in [lo, hi) that is a live cell.
  #: (ptr, ptr) -> void
  def zr_mark_range(lo, hi)
    at = Machine.ptr(Machine.word(lo) & (0 - 8))
    while at < hi
      zr_mark_maybe(Machine.load64(at, 0))
      at += 8
    end
  end

  #: (value) -> ptr
  def zr_arena_of(v)
    Machine.ptr(Machine.word(v) & (0 - ARENA_BYTES))
  end

  # Size class `c` (0 to 3): cells of CELL_MIN << c bytes.
  #: (word) -> ptr
  def zr_size_class(c)
    Machine.static(:size_classes, SizeClass.size * SIZE_CLASSES) + (c * SizeClass.size)
  end

  # The size class whose cells fit `bytes` (CELL_MAX at most). Each
  # constructor gives its struct's size, or clamps a payload to the largest
  # cell and mallocs the remainder. It is one expression, so the allocation
  # can inline it.
  #: (word) -> word
  def zr_size_class_for(bytes)
    bytes <= CELL_MIN ? 0 : (bytes <= CELL_MIN * 2 ? 1 : (bytes <= CELL_MIN * 4 ? 2 : 3))
  end

  # The bytes of `v`'s cell: the cell size of its arena.
  #: (value) -> word
  def zr_cell_bytes(v)
    ArenaHead[zr_arena_of(v)].cell
  end

  # Arena `a`'s mark bitmap, between its head and its cells. It is at a
  # fixed offset, so to find a cell's bit, the only value read from the
  # head is the shift that converts an address into an index.
  #: (ptr) -> ptr
  def zr_arena_marks(a)
    a + ARENA_HEAD
  end

  # Arena `a`'s age bitmap, next to its marks: the old objects, which lived
  # through three collections (zr_arena_count_low). The write barrier and a
  # minor collection read this
  # map. The marks go back to zero at the end of each collection, so no
  # cell is marked outside a collection. Thus ObjectSpace's walk of an
  # object's references (lib/zr/runtime/kernel/objspace.rb) can use the mark
  # bitmap as scratch.
  #: (ptr) -> ptr
  def zr_arena_ages(a)
    a + ARENA_HEAD + MARK_BYTES
  end

  # Arena `a`'s remembered bitmap, next to its ages. A cell's bit is set
  # when the cell is old and contains a reference to a young object. A
  # minor collection must trace that cell again, although it is marked.
  #: (ptr) -> ptr
  def zr_arena_remembered(a)
    a + ARENA_HEAD + (MARK_BYTES * 2)
  end

  # Arena `a`'s allocated bitmap, next to its remembered set. A cell's bit
  # is set from its allocation until the sweep frees it. An allocation
  # finds a free cell with it, and each walk of the heap's objects reads it
  # in place of the cells. Thus no code touches a cell before its
  # allocation.
  #: (ptr) -> ptr
  def zr_arena_allocated(a)
    a + ARENA_HEAD + (MARK_BYTES * 3)
  end

  # Arena `a`'s two bitmaps of a count for each cell, after its allocated
  # map: the low bit and the high bit.
  #
  # A young cell counts the collections that it lived through. The third
  # makes it old, as RVALUE_OLD_AGE does in CRuby, and the sweep moves its
  # bit to the ages. So an object that dies soon after a collection does
  # not wait in the old generation for a major.
  #
  # An old cell counts the collections in which it stays remembered. A
  # promotion and a store of a young object (zr_arena_stored) set it to
  # two. A young object that the cell then contains is at least one
  # collection old, so it is old itself after two more. CRuby finds the
  # same cells with `rgengc_check_relation`, a check of each reference in
  # each trace; a count costs the trace nothing.
  #: (ptr) -> ptr
  def zr_arena_count_low(a)
    a + ARENA_HEAD + (MARK_BYTES * 4)
  end

  #: (ptr) -> ptr
  def zr_arena_count_high(a)
    a + ARENA_HEAD + (MARK_BYTES * 5)
  end

  # Arena `a`'s map of the old cells that the barrier remembered since the
  # last collection. The sweep sets their counts.
  #: (ptr) -> ptr
  def zr_arena_stored(a)
    a + ARENA_HEAD + (MARK_BYTES * 6)
  end

  # The first cell of arena `a`, after its head and its bitmaps.
  #: (ptr) -> ptr
  def zr_arena_first(a)
    a + ARENA_HEAD + (MARK_BYTES * ARENA_MAPS)
  end

  # The index of the first allocated cell of `a` at `i` or after it, or
  # ARENA_CELLS if there is none. A walk of the heap's objects uses it to
  # step.
  #: (ptr, word) -> word
  def zr_arena_next_allocated(a, i)
    map = zr_arena_allocated(a)
    while i < ARENA_CELLS
      word = Machine.load64(map + ((i >> 6) * 8), 0) >> (i & 63)
      if word != 0
        return i + Machine.ctz(word)
      end
      i = (i | 63) + 1
    end
    ARENA_CELLS
  end

  # The number of cells of `a` that are allocated and not yet freed.
  #: (ptr) -> word
  def zr_arena_live(a)
    map = zr_arena_allocated(a)
    n = 0
    w = 0
    while w < MARK_BYTES
      n += Machine.popcnt(Machine.load64(map + w, 0))
      w += 8
    end
    n
  end

  # The exivar slots of arena `a`, one for each cell, or 0 if no cell in it
  # has a generic ivar. The slots are separate so that most arenas do not
  # pay for them (eight bytes a cell is a quarter of a 32-byte-cell arena).
  # Only a kind with no ivar table of its own uses a generic ivar
  # (`zr_ivtab_for_write`, lib/zr/runtime/kernel/object.rb): an ivar on a String,
  # an Array, a Float or a Proc, and the ivars that a clone copies.
  #: (ptr) -> ptr
  def zr_arena_exivars(a)
    ArenaHead[a].exivars
  end

  # The same, but makes the slots if the arena has none. CRuby also keeps
  # generic ivars in a separate table for the same reason.
  #: (ptr) -> ptr
  def zr_arena_exivars_for_write(a)
    slots = ArenaHead[a].exivars
    if slots == 0
      bytes = ArenaHead[a].ncells * 8
      slots = zr_xmalloc(bytes)
      Libc.memset(slots, Machine.i32(0), bytes)
      ArenaHead[a].exivars = slots
    end
    slots
  end

  # The word of each of `a`'s bitmaps that contains cell `i`'s bit, and
  # that bit. The maps have the same shape, so one bit applies to all.
  #: (ptr, word) -> ptr
  def zr_marks_word(a, i)
    zr_arena_marks(a) + ((i >> 6) * 8)
  end

  #: (ptr, word) -> ptr
  def zr_ages_word(a, i)
    zr_arena_ages(a) + ((i >> 6) * 8)
  end

  #: (ptr, word) -> ptr
  def zr_remembered_word(a, i)
    zr_arena_remembered(a) + ((i >> 6) * 8)
  end

  #: (word) -> word
  def zr_marks_bit(i)
    Machine.shl_wrap(1, i & 63)
  end

  # The index of cell `v` in arena `a`.
  #: (ptr, value) -> word
  def zr_cell_index_in(a, v)
    (Machine.word(v) - zr_arena_first(a)) >> ArenaHead[a].shift
  end

  # The index of `v`'s cell in its arena.
  #: (value) -> word
  def zr_cell_index(v)
    zr_cell_index_in(zr_arena_of(v), v)
  end

  # Whether `v` is marked, and the two writes to its bit. A Proc or an Env
  # on the machine stack is in no arena and has no bit, so each caller
  # here checks FL_STACK first.
  #: (value) -> bool
  def zr_marked_p(v)
    a = zr_arena_of(v)
    i = zr_cell_index_in(a, v)
    (Machine.load64(zr_marks_word(a, i), 0) & zr_marks_bit(i)) != 0
  end

  #: (value) -> void
  def zr_mark_set(v)
    a = zr_arena_of(v)
    i = zr_cell_index_in(a, v)
    at = zr_marks_word(a, i)
    Machine.store64(at, 0, Machine.load64(at, 0) | zr_marks_bit(i))
  end

  #: (value) -> void
  def zr_mark_unset(v)
    a = zr_arena_of(v)
    i = zr_cell_index_in(a, v)
    at = zr_marks_word(a, i)
    Machine.store64(at, 0, Machine.load64(at, 0) & (0 - 1 - zr_marks_bit(i)))
  end

  # Whether `v` survived a collection ("old" means this here). An immediate
  # has no cell, and a Proc or an Env on the machine stack is in no arena,
  # so neither has a bit to read.
  #: (value) -> bool
  def zr_aged_p(v)
    a = zr_arena_of(v)
    i = zr_cell_index_in(a, v)
    (Machine.load64(zr_ages_word(a, i), 0) & zr_marks_bit(i)) != 0
  end

  # The collections that `v` lived through, at most 3 (old), for
  # ObjectSpace.dump's age.
  #: (value) -> word
  def zr_age(v)
    if zr_special_p(v) || (RBasic[v].flags & FL_STACK) != 0
      return 0
    end
    a = zr_arena_of(v)
    i = zr_cell_index_in(a, v)
    w = (i >> 6) * 8
    bit = zr_marks_bit(i)
    if (Machine.load64(zr_arena_ages(a) + w, 0) & bit) != 0
      return 3
    end
    high = (Machine.load64(zr_arena_count_high(a) + w, 0) & bit) != 0
    low = (Machine.load64(zr_arena_count_low(a) + w, 0) & bit) != 0
    (high ? 2 : 0) + (low ? 1 : 0)
  end

  #: (value) -> bool
  def zr_old_p(v)
    !zr_special_p(v) && (RBasic[v].flags & FL_STACK) == 0 && zr_aged_p(v)
  end

  inline :zr_old_p

  # Sets `v`'s bit in its arena's remembered map, and flags the arena, so
  # a minor collection reads only the maps of flagged arenas. The bits are
  # a map, not a list: nothing to allocate, de-duplicate or overflow. This
  # is what CRuby's `rgengc_rememberset_mark` gets from `remembered_bits`.
  #: (value) -> void
  def zr_remember(v)
    a = zr_arena_of(v)
    i = zr_cell_index_in(a, v)
    bit = zr_marks_bit(i)
    at = zr_remembered_word(a, i)
    Machine.store64(at, 0, Machine.load64(at, 0) | bit)
    at = zr_arena_stored(a) + ((i >> 6) * 8)
    Machine.store64(at, 0, Machine.load64(at, 0) | bit)
    ArenaHead[a].remembered = 1
  end

  # The write barrier: `owner` now contains a reference to `value`.
  #
  # A minor collection starts from the roots and the remembered cells, and
  # stops at each object that is already marked. Thus an old object that
  # gets a reference to a young one must be remembered, or the sweep frees
  # the young one. Nothing is necessary when the owner is young (a minor
  # collection gets to it from the roots), or when the value is an
  # immediate or is old.
  #
  # CRuby needs the same barrier but cannot check it: each C function that
  # stores a VALUE into an object must call `RB_OBJ_WRITE` by hand. Thus
  # CRuby has wb-unprotected objects that it never promotes, and a second
  # collector (gc/wbcheck) that finds missing calls. Here the compiler
  # emits the store, so it emits the barrier too: `Machine::Lower#field`
  # writes one after each store into a Value field of a struct that starts
  # with an RBasic, which means a cell.
  #: (value, value) -> void
  def zr_write_barrier(owner, value)
    if zr_old_p(owner) && !zr_old_p(value)
      zr_remember(owner)
    end
  end

  inline :zr_write_barrier

  # Remembers `owner` if it is old, whatever it now contains. A bulk write
  # into a buffer that `owner` keeps calls this. Checking each value one at
  # a time costs more than one more trace of the cell.
  #: (value) -> void
  def zr_write_barrier_all(owner)
    if zr_old_p(owner)
      zr_remember(owner)
    end
  end

  inline :zr_write_barrier_all

  # The bytes of an arena of size class `c`: its head, its bitmaps and
  # its cells. This does not include the exivar slots; an arena that needs
  # them mallocs them.
  #: (word) -> word
  def zr_arena_bytes(c)
    ARENA_HEAD + (MARK_BYTES * ARENA_MAPS) + (ARENA_CELLS * (CELL_MIN << c))
  end

  # The bytes of live cells in the heap, as counted by the sweep.
  #: () -> word
  def zr_live_bytes
    bytes = 0
    c = 0
    while c < SIZE_CLASSES
      sc = zr_size_class(c)
      bytes += ((SizeClass[sc].arenas * ARENA_CELLS) - SizeClass[sc].freed) * (CELL_MIN << c)
      c += 1
    end
    bytes
  end

  # The bytes of all arenas in the heap, live and free cells.
  #: () -> word
  def zr_heap_bytes
    bytes = 0
    c = 0
    while c < SIZE_CLASSES
      bytes += SizeClass[zr_size_class(c)].arenas * zr_arena_bytes(c)
      c += 1
    end
    bytes
  end

  # The memory that this machine has for a heap. The host is asked one
  # time. If the host does not tell, the value is 4 GB, which is also all
  # that a wasm32 module can address.
  #
  # The OS layer asks, because the method is not portable:
  # `zr_os_machine_bytes` reads sysconf where it exists and returns 0 where
  # it does not.
  #: () -> word
  def zr_machine_bytes
    at = Machine.static(:machine_bytes, 8)
    known = Machine.load64(at, 0)
    if known != 0
      return known
    end
    bytes = zr_os_machine_bytes()
    if bytes == 0
      bytes = 4294967296
    end
    Machine.store64(at, 0, bytes)
    bytes
  end

  # Makes a new reserved arena of size class `c`: its head written and its
  # four bitmaps clear. It does not touch the cells: no cell is read before
  # an allocation gives it out and writes its header. It has no exivar
  # slots; the first generic ivar in it makes them.
  #: (word) -> void
  def zr_arena_add(c)
    h = zr_heap()
    zr_arena_table_grow()
    n = Heap[h].arenas
    slot = Machine.slot(8)
    if Libc.posix_memalign(slot, ARENA_BYTES, zr_arena_bytes(c)) != Machine.i32(0)
      zr_memory_exhausted()
    end
    a = Machine.ptr(Machine.load64(slot, 0))
    ArenaHead[a].cell = CELL_MIN << c
    ArenaHead[a].shift = 5 + c
    ArenaHead[a].ncells = ARENA_CELLS
    ArenaHead[a].index = c
    Machine.store64(Heap[h].table + (n * 8), 0, Machine.word(a))
    zr_arena_index_add(a)
    Heap[h].arenas = n + 1
    sc = zr_size_class(c)
    SizeClass[sc].arenas = SizeClass[sc].arenas + 1
    ArenaHead[a].exivars = 0
    ArenaHead[a].idle_low = 0
    ArenaHead[a].idle_high = 0
    ArenaHead[a].gone_low = 0
    ArenaHead[a].gone_high = 0
    Libc.memset(zr_arena_marks(a), Machine.i32(0), MARK_BYTES * ARENA_MAPS)
    zr_arena_reserve(a)
  end

  # ArenaHead#reserved of a reserved arena whose cells' pages went back to
  # the system (zr_arenas_release), and of one that a major collection
  # found reserved already and left in memory.
  ARENA_RELEASED = 2
  ARENA_IDLE = 3
  # The page size that a release rounds to: the largest of the hosts'.
  RELEASE_PAGE = 16384

  # Puts arena `a`, with all cells free, into its size class's reserve.
  #: (ptr) -> void
  def zr_arena_reserve(a)
    sc = zr_size_class(ArenaHead[a].index)
    ArenaHead[a].reserved = 1
    ArenaHead[a].next = SizeClass[sc].reserve
    SizeClass[sc].reserve = a
  end

  # A word with all bits set. A size class's cursor points here while it is
  # in no arena, so `zr_alloc` finds no free cell and takes the slow path,
  # which moves the cursor.
  #: () -> ptr
  def zr_full
    Machine.static(:full_word, 8)
  end

  # Sets the cursor of size class `sc` to its arena's allocated word.
  # `origin` is the base from which the word's address and a bit give the
  # cell's address (`zr_cell_take`).
  #: (ptr, ptr, ptr) -> void
  def zr_cursor_set(sc, a, at)
    zr_arena_pages_taken(a, at)
    SizeClass[sc].cursor = at
    # The origin is a virtual address, and it can be below 0: only the
    # sum in zr_cell_take is a real address.
    SizeClass[sc].origin = Machine.usub_wrap(zr_arena_first(a), Machine.word(zr_arena_allocated(a)) << (3 + ArenaHead[a].shift))
  end

  # Moves the cursor of `sc` to the next allocated word with a clear bit:
  # first in its arena, then from the start of each arena on its list with
  # room, then in a reserved arena (all words clear). Returns false if none
  # of the three has one; the caller then collects or makes an arena.
  #: (ptr) -> bool
  def zr_cursor_advance(sc)
    # @type var a: ptr
    # @type var stop: ptr
    # @type var at: ptr
    at = SizeClass[sc].cursor
    if at != zr_full()
      a = zr_arena_of(Machine.value(at))
      stop = zr_arena_allocated(a) + MARK_BYTES
      while at < stop
        if Machine.load64(at, 0) != ALL_MARKED
          zr_arena_pages_taken(a, at)
          SizeClass[sc].cursor = at
          return true
        end
        at += 8
      end
    end
    while SizeClass[sc].room != 0
      a = SizeClass[sc].room
      SizeClass[sc].room = ArenaHead[a].next
      at = zr_arena_allocated(a)
      stop = at + MARK_BYTES
      while at < stop
        if Machine.load64(at, 0) != ALL_MARKED
          zr_cursor_set(sc, a, at)
          return true
        end
        at += 8
      end
    end
    a = SizeClass[sc].reserve
    if a == 0
      SizeClass[sc].cursor = zr_full()
      return false
    end
    SizeClass[sc].reserve = ArenaHead[a].next
    if ArenaHead[a].reserved == ARENA_RELEASED
      zr_arena_pages(a, false)
    end
    ArenaHead[a].reserved = 0
    zr_cursor_set(sc, a, zr_arena_allocated(a))
    true
  end

  # Gives the memory of reserved arenas back to the system after a major
  # collection, as CRuby's heap_pages_free_unused_pages frees the pages
  # that a sweep left empty. A size class keeps the arenas it needs for
  # two times its live cells, and one arena more, so a release adds no
  # collection and no growth. A released arena keeps its place in the
  # table and its maps, so a walk of the arenas is not changed. Its cells
  # come back when the cursor takes it.
  #
  # Unless `now` (GC.start), an arena goes back only when it was reserved
  # at the major before this one too. An arena that a burst of short-lived
  # objects empties and fills again between majors stays in memory: on
  # the GC benchmark, a release at each major made the run 2.4% slower.
  #: (bool) -> void
  def zr_arenas_release(now)
    n = Heap[zr_heap()].arenas
    i = 0
    while i < n
      a = zr_arena_at(i)
      if ArenaHead[a].reserved == 0
        zr_arena_pages_trim(a, now)
      end
      i += 1
    end
    c = 0
    while c < SIZE_CLASSES
      sc = zr_size_class(c)
      capacity = SizeClass[sc].arenas * ARENA_CELLS
      spare = capacity - ((capacity - SizeClass[sc].freed) * 2) - ARENA_CELLS
      a = SizeClass[sc].reserve
      while a != 0
        state = ArenaHead[a].reserved
        if spare < ARENA_CELLS
          if state != ARENA_RELEASED
            ArenaHead[a].reserved = ARENA_IDLE
          end
        elsif state == ARENA_IDLE || (now && state != ARENA_RELEASED)
          zr_arena_pages(a, true)
        elsif state != ARENA_RELEASED
          ArenaHead[a].reserved = ARENA_IDLE
        end
        spare -= ARENA_CELLS
        a = ArenaHead[a].next
      end
      c += 1
    end
  end

  # The first RELEASE_PAGE boundary in arena `a`'s cells: page 0 of its
  # page bits.
  #: (ptr) -> word
  def zr_arena_page_base(a)
    (Machine.word(zr_arena_first(a)) + RELEASE_PAGE - 1) & (0 - RELEASE_PAGE)
  end

  # The bit of page `p` in the two words of a page map, as a mask in the
  # word that `high` names.
  #: (word) -> word
  def zr_page_bit(p)
    Machine.shl_wrap(1, p & 63)
  end

  # Gives back the whole pages of in-use arena `a` whose cells are all free
  # after a major collection. CRuby's pages are smaller than its heap's
  # unit of growth, and its sweep frees each empty one; an arena here is
  # the unit, so a heap whose live cells are spread over many arenas kept
  # all their pages. A page goes back when it was free at the major before
  # this one too (`idle`), as an arena does, unless `now` (GC.start). A
  # page that went back (`gone`) comes back as zeros at its first touch:
  # no cell is read before an allocation writes it. The cursor clears its
  # bit when it takes cells on it again (zr_arena_pages_taken).
  #: (ptr, bool) -> void
  def zr_arena_pages_trim(a, now)
    first = Machine.word(zr_arena_first(a))
    shift = ArenaHead[a].shift
    base = zr_arena_page_base(a)
    stop = (first + (ARENA_CELLS << shift)) & (0 - RELEASE_PAGE)
    allocated = zr_arena_allocated(a)
    idle_low = 0
    idle_high = 0
    gone_low = ArenaHead[a].gone_low
    gone_high = ArenaHead[a].gone_high
    run = 0
    page = base
    p = 0
    while page < stop
      lo = (page - first) >> shift
      hi = (page + RELEASE_PAGE - 1 - first) >> shift
      free = true
      i = lo
      while free && i <= hi
        bits = Machine.load64(allocated + ((i >> 6) * 8), 0) >> (i & 63)
        span = 64 - (i & 63)
        if span > hi - i + 1
          span = hi - i + 1
        end
        mask = span == 64 ? ALL_MARKED : Machine.shl_wrap(1, span) - 1
        free = (bits & mask) == 0
        i += span
      end
      bit = zr_page_bit(p)
      high = p >= 64
      was_idle = ((high ? ArenaHead[a].idle_high : ArenaHead[a].idle_low) & bit) != 0
      gone = ((high ? gone_high : gone_low) & bit) != 0
      give = free && !gone && (now || was_idle)
      if free && !give && !gone
        if high
          idle_high |= bit
        else
          idle_low |= bit
        end
      end
      if give
        if high
          gone_high |= bit
        else
          gone_low |= bit
        end
        if run == 0
          run = page
        end
      elsif run != 0
        zr_os_release_pages(Machine.ptr(run), page - run)
        run = 0
      end
      page += RELEASE_PAGE
      p += 1
    end
    if run != 0
      zr_os_release_pages(Machine.ptr(run), page - run)
    end
    ArenaHead[a].idle_low = idle_low
    ArenaHead[a].idle_high = idle_high
    ArenaHead[a].gone_low = gone_low
    ArenaHead[a].gone_high = gone_high
  end

  # The cursor of arena `a` moves to allocated word `at`: the pages of its
  # 64 cells are in memory again.
  #: (ptr, ptr) -> void
  def zr_arena_pages_taken(a, at)
    if (ArenaHead[a].gone_low | ArenaHead[a].gone_high) == 0
      return
    end
    first = Machine.word(zr_arena_first(a))
    shift = ArenaHead[a].shift
    base = zr_arena_page_base(a)
    i = (at - zr_arena_allocated(a)) << 3
    from = first + (i << shift)
    to = first + ((i + 64) << shift) - 1
    if to < base
      return
    end
    p = from < base ? 0 : (from - base) / RELEASE_PAGE
    last = (to - base) / RELEASE_PAGE
    while p <= last && p < 128
      bit = zr_page_bit(p)
      if p >= 64
        ArenaHead[a].gone_high = ArenaHead[a].gone_high & (0 - 1 - bit)
      else
        ArenaHead[a].gone_low = ArenaHead[a].gone_low & (0 - 1 - bit)
      end
      p += 1
    end
  end

  # Gives back (`release`) or takes back the whole pages of reserved arena
  # `a`'s cells, and its generic ivar slots with them.
  #: (ptr, bool) -> void
  def zr_arena_pages(a, release)
    h = zr_heap()
    start = Machine.word(zr_arena_first(a))
    start = (start + RELEASE_PAGE - 1) & (0 - RELEASE_PAGE)
    stop = (Machine.word(a) + zr_arena_bytes(ArenaHead[a].index)) & (0 - RELEASE_PAGE)
    if release
      if ArenaHead[a].exivars != 0
        zr_xfree(ArenaHead[a].exivars)
        ArenaHead[a].exivars = 0
      end
      if stop > start
        zr_os_release_pages(Machine.ptr(start), stop - start)
      end
      ArenaHead[a].reserved = ARENA_RELEASED
      Heap[h].released = Heap[h].released + 1
      Heap[h].freed_pages = Heap[h].freed_pages + 1
    else
      if stop > start
        zr_os_reuse_pages(Machine.ptr(start), stop - start)
      end
      Heap[h].released = Heap[h].released - 1
    end
  end

  # GC.stat's page counts: the arenas that hold memory, and the arenas
  # whose memory went back to the system since the start.
  #: () -> value
  def zr_gc_pages
    h = zr_heap()
    out = zr_ary_new(2)
    zr_ary_push(out, zr_fix(Heap[h].arenas - Heap[h].released))
    zr_ary_push(out, zr_fix(Heap[h].freed_pages))
    out
  end

  # The frame list that the collector walks: a frame record is a Frame
  # followed by `nvalues` Values.
  # `entry` is the method entry that a method frame was called through; its
  # `mid` is the name used in the call (an alias's own name). It is 0 for a
  # frame that is not a method's. `defined` is the class or proxy where the
  # method was found, where `super` continues from (a module included two
  # times has two proxies). `serial` identifies a frame at an address
  # against the next frame at that address; it is 0 until something needs
  # it (`zr_frame_serial`). `svars` is nil until `$~` or `$_` is written
  # under the frame, then a two-element Array of them (`zr_svars`).
  class Frame < Layout
    attr_accessor :prev #: ptr
    attr_accessor :meta #: ptr
    attr_accessor :line #: word
    attr_accessor :self #: value
    attr_accessor :cref #: value
    attr_accessor :blk #: value
    attr_accessor :entry #: ptr
    attr_accessor :defined #: value
    attr_accessor :serial #: word
    attr_accessor :nvalues #: word
    attr_accessor :svars #: value
  end

  class Task < Layout
    attr_accessor :top #: ptr
    attr_accessor :serial #: word
    attr_accessor :pending #: value
    attr_accessor :errinfo #: value
    attr_accessor :pending_kind #: word
    attr_accessor :pending_home #: ptr
    attr_accessor :pending_site #: word
    attr_accessor :kw #: word
    attr_accessor :stack_limit #: ptr
    attr_accessor :guards #: value
    # `Thread.current[:__recursive_key__]` of the fiber (CRuby's
    # local_storage_recursive_hash): nil, or what the program set there,
    # which the guards read too.
    attr_accessor :recursive #: value
    attr_accessor :catches #: value
    attr_accessor :throw_tag #: value
    attr_accessor :missing #: word
    attr_accessor :found #: value
    attr_accessor :refine #: value
    attr_accessor :ractor #: word
    attr_accessor :eval_using #: word
    attr_accessor :pending_from #: ptr
    # The outermost Env of the block that the thread or fiber started
    # with, and the flip-flop states that the task keeps for that scope
    # (`zr_flip_flop_get`).
    attr_accessor :root_env #: value
    attr_accessor :flip_flops #: value
    # The innermost C frame record (`CFrame`) of the task: 0 while no C
    # function that zr called runs.
    attr_accessor :cframe #: ptr
    # The unwind that rb_protect stopped, which rb_jump_tag resumes: an
    # Array of the pending fields (capi/control.rb), or nil.
    attr_accessor :parked #: value
    # Whether the C method that runs got keywords (rb_keyword_given_p).
    attr_accessor :c_keywords #: word
    # The spread stack (zr_spread_take): an Array of Arrays, or nil, and
    # the index of the first one that no call holds.
    attr_accessor :spread #: value
    attr_accessor :spread_top #: word
    # The argument slot of a lent keyword Hash (KW_LENT).
    attr_accessor :kw_at #: ptr
  end

  # The runtime's own roots: the core classes and the main object.
  G_BASIC_OBJECT = 0
  G_OBJECT = 1
  G_MODULE = 2
  G_CLASS = 3
  G_KERNEL = 4
  G_INTEGER = 5
  G_STRING = 6
  G_SYMBOL = 7
  G_NIL = 8
  G_TRUE = 9
  G_FALSE = 10
  G_MAIN = 11
  G_NUMERIC = 13
  G_COUNT = 78

  #: () -> ptr
  def zr_globals
    Machine.static(:globals, G_COUNT * 8)
  end

  #: (word) -> value
  def zr_global(i)
    Machine.value(Machine.load64(zr_globals() + (i * 8), 0))
  end

  #: (word, value) -> void
  def zr_set_global(i, v)
    Machine.store64(zr_globals() + (i * 8), 0, Machine.word(v))
  end

  # One reserved arena for each size class at start, and a second of
  # 64-byte cells. The boot makes about ten thousand small Strings and
  # Arrays, and a program that does not collect on its own never collects.
  #: () -> void
  def zr_heap_init
    h = zr_heap()
    Heap[h].malloc_limit = MALLOC_LIMIT
    Heap[h].old_limit = OLD_LIMIT_MIN
    Heap[h].old_factor = OLD_LIMIT_FACTOR * 100
    Machine.store64(zr_full(), 0, ALL_MARKED)
    c = 0
    while c < SIZE_CLASSES
      SizeClass[zr_size_class(c)].cursor = zr_full()
      SizeClass[zr_size_class(c)].shift = 5 + c
      zr_arena_add(c)
      c += 1
    end
    zr_arena_add(1)
    zr_heap_env()
  end

  # The collector's switches that the environment turns on: ZR_GC_STRESS,
  # ZR_GC_VERIFY and ZR_GC_TRACE. The heap reads them as it starts. The
  # host reads them again for a program test that sets them
  # (test/support/host_program.rb), which is cheaper than a boot under
  # them.
  #: () -> void
  def zr_heap_env
    h = zr_heap()
    if Libc.getenv(Machine.bytes("ZR_GC_STRESS\0")) != 0
      Heap[h].stress = STRESS_MINOR
    end
    if Libc.getenv(Machine.bytes("ZR_GC_VERIFY\0")) != 0
      Heap[h].verify = 1
    end
    if Libc.getenv(Machine.bytes("ZR_GC_TRACE\0")) != 0
      Heap[h].trace = 1
    end
    zr_heap_slow_update()
  end

  # The object whose children are being marked, so that the abort below
  # can identify the object that pointed at a freed cell.
  #: () -> ptr
  def zr_marking
    Machine.static(:marking, 8)
  end

  # The cells that are marked but not yet traced. It is a growable stack,
  # so a long chain of objects uses no machine stack.
  class MarkStack < Layout
    attr_accessor :ptr #: ptr
    attr_accessor :len #: word
    attr_accessor :capa #: word
  end

  #: () -> ptr
  def zr_mark_stack
    Machine.static(:mark_stack, MarkStack.size)
  end

  # Marks `v` and queues it for tracing. Most references in a collection
  # are immediates or cells already marked, so the check for those is
  # inline where each reference is read. Only a cell to mark costs a call.
  # A Proc or an Env on the machine stack lives as long as its frame and
  # has no bit in any arena, so its flag excludes it here.
  #: (value) -> void
  def zr_mark(v)
    unless zr_special_p(v) || (RBasic[v].flags & FL_STACK) != 0 || zr_marked_p(v)
      zr_mark_cell(v)
    end
  end

  # Nonzero while ObjectSpace reads the references of one object. That
  # needs each cell that it marks on the queue.
  #: () -> ptr
  def zr_mark_every
    Machine.static(:mark_every, 8)
  end

  # A freed cell here is a missed root. The abort identifies the object
  # that pointed at it.
  #: (value) -> void
  def zr_mark_cell(v)
    flags = RBasic[v].flags
    if (flags & FL_ALLOCATED) == 0
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("a live object points at a freed cell: from a cell of type "), 58)
      parent = Machine.value(Machine.load64(zr_marking(), 0))
      if parent == QNIL
        zr_buf_push(b, Machine.bytes("root"), 4)
      elsif zr_fixnum_p(parent)
        zr_buf_push(b, Machine.bytes("root "), 5)
        zr_buf_long(b, zr_fix2long(parent))
      else
        zr_buf_long(b, RBasic[parent].flags & T_MASK)
      end
      zr_buf_push(b, Machine.bytes(" cell "), 6)
      zr_buf_long(b, Machine.word(v))
      zr_buf_push(b, Machine.bytes(" flags "), 7)
      zr_buf_long(b, flags)
      zr_buf_push(b, Machine.bytes(" index "), 7)
      zr_buf_long(b, zr_cell_index(v))
      zr_buf_push(b, Machine.bytes(" alloc "), 7)
      zr_buf_long(b, Machine.load64(zr_arena_allocated(zr_arena_of(v)) + ((zr_cell_index(v) >> 6) * 8), 0) & zr_marks_bit(zr_cell_index(v)))
      zr_buf_push(b, Machine.bytes(" mark "), 6)
      zr_buf_long(b, zr_marked_p(v) ? 1 : 0)
      zr_buf_push(b, Machine.bytes(" age "), 5)
      zr_buf_long(b, zr_aged_p(v) ? 1 : 0)
      zr_buf_push(b, Machine.bytes(" parent "), 8)
      zr_buf_long(b, Machine.word(parent))
      zr_buf_push(b, Machine.bytes(" collections "), 13)
      zr_buf_long(b, Heap[zr_heap()].collections)
      zr_buf_byte(b, 10)
      zr_bug(Buf[b].ptr, Buf[b].len)
    end
    if zr_marked_p(v)
      return
    end
    zr_mark_set(v)
    if Heap[zr_heap()].verifying != 0
      zr_verify_reached(v)
    end
    # A String or a Float contains no Value. In a collection, this marks
    # its class here, and the queue never gets it. ObjectSpace's walk of one
    # object's references reads them from the queue, so there each cell
    # goes on it.
    t = flags & T_MASK
    if (t == T_STRING || t == T_FLOAT) && (flags & FL_EXIVAR) == 0 && Machine.load64(zr_mark_every(), 0) == 0
      zr_mark(RBasic[v].klass)
      return
    end
    s = zr_mark_stack()
    n = MarkStack[s].len
    if n == MarkStack[s].capa
      capa = n == 0 ? 1024 : n * 2
      grown = zr_xmalloc(capa * 8)
      if n > 0
        zr_memcpy(grown, MarkStack[s].ptr, n * 8)
        zr_xfree(MarkStack[s].ptr)
      end
      MarkStack[s].ptr = grown
      MarkStack[s].capa = capa
    end
    Machine.store64(MarkStack[s].ptr + (n * 8), 0, Machine.word(v))
    MarkStack[s].len = n + 1
  end

  # Traces each queued cell: its class, its children, its exivars.
  #: () -> void
  def zr_mark_drain
    s = zr_mark_stack()
    while MarkStack[s].len > 0
      n = MarkStack[s].len - 1
      MarkStack[s].len = n
      v = Machine.value(Machine.load64(MarkStack[s].ptr + (n * 8), 0))
      Machine.store64(zr_marking(), 0, Machine.word(v))
      zr_mark(RBasic[v].klass)
      zr_mark_children(v)
      if (RBasic[v].flags & FL_EXIVAR) != 0
        zr_mark_ivtab(zr_exivar_tab(v))
      end
    end
  end

  # The ivar tables of objects whose kind has no table of its own. The
  # arena's slot array has one slot for each cell, which contains a table
  # or 0. The array can be missing, and then no cell of that arena has a
  # table; `zr_exivar_slot_for_write` makes it.
  #: (value) -> ptr
  def zr_exivar_slot(v)
    slots = zr_arena_exivars(zr_arena_of(v))
    slots == 0 ? Machine.ptr(0) : slots + (zr_cell_index(v) * 8)
  end

  #: (value) -> ptr
  def zr_exivar_slot_for_write(v)
    zr_arena_exivars_for_write(zr_arena_of(v)) + (zr_cell_index(v) * 8)
  end

  #: (value) -> ptr
  def zr_exivar_tab(v)
    at = zr_exivar_slot(v)
    at == 0 ? Machine.ptr(0) : Machine.ptr(Machine.load64(at, 0))
  end

  # The table for `v`, made on first use, and with it the slot array of
  # `v`'s arena. The slot is found after the malloc, not before, so that
  # no pointer into the array stays live across a call that can collect.
  #: (value) -> ptr
  def zr_exivar_tab_for_write(v)
    t = zr_exivar_tab(v)
    if t == 0
      t = zr_xmalloc(IvTab.size)
      zr_ivtab_init(t)
      Machine.store64(zr_exivar_slot_for_write(v), 0, Machine.word(t))
      RBasic[v].flags = RBasic[v].flags | FL_EXIVAR
    end
    t
  end

  # Only a cell with FL_EXIVAR set gets here. The table is made when that
  # flag is set, so the arena has its slots.
  #: (value) -> void
  def zr_exivar_free(v)
    t = zr_exivar_tab(v)
    zr_release_ivtab(t)
    zr_xfree(t)
    Machine.store64(zr_exivar_slot(v), 0, 0)
  end

  # Global variables: one table of (id, value) entries.
  #: () -> ptr
  def zr_gvars
    Machine.static(:gvars, IvTab.size)
  end

  # The entry of global `id` in zr_gvars, or 0. An entry never leaves the
  # table, so it keeps its index. A small static map from the id to that
  # index finds it with no walk of the other globals; the entry's id
  # checks the guess.
  GVAR_GUESSES = 64
  #: (word) -> ptr
  def zr_gvar_row(id)
    t = zr_gvars()
    guess = Machine.static(:gvar_guesses, GVAR_GUESSES * 8) + ((Machine.mul_wrap(id, 31) & (GVAR_GUESSES - 1)) * 8)
    i = Machine.load64(guess, 0)
    if i < IvTab[t].len && IvEntry[IvTab[t].rows + (i * IvEntry.size)].id == id
      return IvTab[t].rows + (i * IvEntry.size)
    end
    e = zr_ivtab_row(t, id)
    if e != 0
      Machine.store64(guess, 0, (e - IvTab[t].rows) / IvEntry.size)
    end
    e
  end

  # `alias $new $old`: the alias refers to the same entry. The table maps
  # an alias to its resolved target name.
  #: () -> ptr
  def zr_gvar_aliases
    Machine.static(:gvar_aliases, IvTab.size)
  end

  #: (word) -> word
  def zr_gvar_resolve(id)
    if IvTab[zr_gvar_aliases()].len == 0
      return id
    end
    target = zr_ivtab_get(zr_gvar_aliases(), id)
    target == QUNDEF ? id : zr_fix2long(target)
  end

  #: (word, word) -> void
  def zr_gvar_alias(new_id, old_id)
    zr_ivtab_set(zr_gvar_aliases(), new_id, zr_fix(zr_gvar_resolve(old_id)))
  end

  #: (word) -> value
  def zr_gvar_get(id)
    # `$?` is the current thread's own (core/process.rb, `status`).
    if zr_gvar_resolve(id) == Machine.id(:$?)
      return zr_send(zr_core_class(Machine.id(:Process)), Machine.id(:status), 0, 0)
    end
    # `$FILENAME` is ARGF's current file (argf_filename_getter).
    if id == Machine.id(:$FILENAME)
      return zr_send(zr_core_class(Machine.id(:ARGF)), Machine.id(:filename), 0, 0)
    end
    # `$-i` is ARGF's edit in place (opt_i_get).
    if id == Machine.id(:$-i)
      return zr_send(zr_core_class(Machine.id(:ARGF)), Machine.id(:inplace_mode), 0, 0)
    end
    b = zr_box_current()
    # Kernel's output in a box goes to the box's own $stdout and $stderr,
    # as rb_stdout and rb_stderr are per box in ruby.
    registered = zr_global(G_BOX)
    if b == QNIL && Machine.word(registered) != 0 && registered != QNIL
      target = zr_gvar_resolve(id)
      if target == Machine.id(:$stdout) || target == Machine.id(:$stderr) || target == Machine.id(:$stdin)
        b = zr_box_reach()
      end
    end
    if b != QNIL
      v = zr_hash_lookup(zr_box_gvars(b), zr_fix(zr_gvar_resolve(id)))
      return v == QUNDEF ? Machine.value(QNIL) : v
    end
    target = zr_gvar_resolve(id)
    word = zr_gvar_mirror_word(target)
    if word != 0
      return Machine.value(Machine.load64(word, 0))
    end
    e = zr_gvar_row(target)
    if e == 0
      return Machine.value(QNIL)
    end
    IvEntry[e].value
  end

  # A program's `$=` read: ruby's ignorecase_getter warns under the
  # deprecated category and gives false.
  #: () -> value
  def zr_gvar_ignorecase
    if zr_send(zr_global(G_KERNEL), Machine.id(:ignorecase_read), 0, 0) == QUNDEF
      return Machine.value(QUNDEF)
    end
    Machine.value(QFALSE)
  end

  # A program's `$name` read. Outside the main ractor it is refused, unless
  # CRuby keeps the global for each ractor.
  #: (word) -> value
  def zr_gvar_read(id)
    r = zr_ractor_gvar_check(id)
    return r if r == QUNDEF
    # An alias of `$<` (English's $DEFAULT_INPUT) is ARGF, as `$<` is.
    if zr_gvar_resolve(id) == Machine.id(:$<)
      return zr_core_class(Machine.id(:ARGF))
    end
    # rb_gvar_undef_getter: under $VERBOSE, a global that was never set warns.
    if zr_box_current() == QNIL && zr_gvar_row(zr_gvar_resolve(id)) == 0 && zr_gvar_get(Machine.id(:$VERBOSE)) == QTRUE
      b = Machine.slot(Buf.size)
      zr_buf_init(b)
      zr_buf_push(b, Machine.bytes("global variable '"), 17)
      zr_buf_sym(b, id)
      zr_buf_push(b, Machine.bytes("' not initialized"), 17)
      zr_warn_here(Buf[b].ptr, Buf[b].len)
      zr_buf_free(b)
    end
    zr_gvar_get(id)
  end

  #: (word) -> value
  def zr_ractor_gvar_check(id)
    if Task[zr_task()].ractor == 0 || zr_gvar_ractor_local_p(id)
      return Machine.value(QNIL)
    end
    args = Machine.slot(8)
    Machine.store64(args, 0, Machine.word(zr_sym(id)))
    zr_send(zr_core_class(Machine.id(:Ractor)), Machine.id(:gvar_isolation!), 1, args)
  end

  # The globals that CRuby keeps for each ractor (rb_gvar_ractor_local).
  # All others belong only to the main ractor.
  #: (word) -> bool
  def zr_gvar_ractor_local_p(id)
    id == Machine.id(:$stdout) || id == Machine.id(:$stderr) || id == Machine.id(:$stdin) || id == Machine.id(:$>) ||
      id == Machine.id(:$VERBOSE) || id == Machine.id(:$DEBUG) || id == Machine.id(:$/) || id == Machine.id(:$-0) ||
      id == Machine.id(:$@) || id == Machine.id(:$?) || id == Machine.id(:$$) || id == Machine.id(:$-v) ||
      id == Machine.id(:$-w) || id == Machine.id(:$-W) || id == Machine.id(:$-d) || id == Machine.id(:$-i) ||
      id == Machine.id(:$-p) || id == Machine.id(:$-l) || id == Machine.id(:$-a)
  end

  #: (word) -> value
  def zr_gvar_defined(id)
    b = zr_box_current()
    if b != QNIL
      return zr_bool(zr_hash_lookup(zr_box_gvars(b), zr_fix(zr_gvar_resolve(id))) != QUNDEF)
    end
    zr_bool(zr_gvar_row(zr_gvar_resolve(id)) != 0)
  end

  #: (word, value) -> value
  def zr_gvar_set(id, v)
    b = zr_box_current()
    if b != QNIL
      zr_hash_store(zr_box_gvars(b), zr_fix(zr_gvar_resolve(id)), v)
      return v
    end
    target = zr_gvar_resolve(id)
    e = zr_gvar_row(target)
    if e == 0
      zr_ivtab_set(zr_gvars(), target, v)
    else
      IvEntry[e].value = v
    end
    zr_gvar_mirror(target, v)
    v
  end

  # The globals that C reads and writes as words of its own (CRuby's
  # rb_stdout, rb_rs, and ruby_verbose through rb_ruby_verbose_ptr):
  # GVAR_MIRRORS pairs of a global's ID and the address of its word,
  # which the C API fills as it starts (capi/entry.rb); 0 before. Once
  # there, the word is the global's value, as in CRuby: an assignment
  # stores into it, and a read reads it.
  GVAR_MIRRORS = 10

  #: (word, value) -> void
  def zr_gvar_mirror(id, v)
    word = zr_gvar_mirror_word(id)
    if word != 0
      Machine.store64(word, 0, Machine.word(v))
    end
  end

  # The word of global `id` (resolved), or 0.
  #: (word) -> ptr
  def zr_gvar_mirror_word(id)
    rows = Machine.static(:gvar_mirrors, GVAR_MIRRORS * 16)
    i = 0
    while i < GVAR_MIRRORS && Machine.load64(rows + (i * 16), 0) != 0
      if Machine.load64(rows + (i * 16), 0) == id
        return Machine.ptr(Machine.load64(rows + (i * 16), 8))
      end
      i += 1
    end
    Machine.ptr(0)
  end

  # `$name = v` from Ruby code. A name that `alias` made is in place of a
  # global that ruby can hook, which checks the value.
  #: (word, value) -> value
  def zr_gvar_assign(id, v)
    target = zr_gvar_resolve(id)
    if target != id
      return zr_gvar_hooked(id, target, v)
    end
    zr_gvar_store(id, v)
  end

  # `$name = v` for a global that ruby hooks. Kernel's hook checks the
  # value, or refuses a read-only global under the name that the program
  # used, and returns the value to store.
  #: (word, word, value) -> value
  def zr_gvar_hooked(shown, id, v)
    argv = Machine.slot(24)
    Machine.store64(argv, 0, Machine.word(zr_sym(shown)))
    Machine.store64(argv, 8, Machine.word(zr_sym(id)))
    Machine.store64(argv, 16, Machine.word(v))
    stored = zr_send(zr_global(G_KERNEL), Machine.id(:hooked_global), 3, argv)
    return stored if stored == QUNDEF
    zr_gvar_store(id, stored)
    v
  end

  # Stores the value, then runs the trace_var commands of the global with
  # it. Returns QUNDEF if one raised.
  #: (word, value) -> value
  def zr_gvar_store(id, v)
    zr_gvar_set(id, v)
    if Machine.load64(Machine.static(:gvar_traced, 8), 0) == 0
      return v
    end
    argv = Machine.slot(16)
    Machine.store64(argv, 0, Machine.word(zr_sym(zr_gvar_resolve(id))))
    Machine.store64(argv, 8, Machine.word(v))
    if zr_send(zr_global(G_KERNEL), Machine.id(:traced_assign), 2, argv) == QUNDEF
      return Machine.value(QUNDEF)
    end
    v
  end

  # The first trace_var: from now on, an assignment looks for commands.
  #: () -> value
  def zr_gvar_traced
    Machine.store64(Machine.static(:gvar_traced, 8), 0, 1)
    Machine.value(QNIL)
  end

  # The name that `alias $new $old` resolves `name` to, or `name`.
  #: (value) -> value
  def zr_gvar_resolve_m(name)
    zr_sym(zr_gvar_resolve(zr_sym2id(name)))
  end

  # Whether the global `name` has an entry (it was assigned).
  #: (value) -> value
  def zr_gvar_defined_m(name)
    zr_gvar_defined(zr_sym2id(name))
  end

  # `$name` and `$name = v` for the tree-walking interpreter, which gives
  # a global by Symbol where compiled code gives it by id. A write uses the
  # hooked form, because the interpreter runs a string that the program
  # wrote: `$stdout = 1` must raise there as it does in other code.
  #: (value) -> value
  def zr_gvar_get_m(name)
    zr_gvar_get(zr_sym2id(name))
  end

  # `$name = v` with no hook, for eval support, which puts a program's
  # separators back after it compiles.
  #: (value, value) -> value
  def zr_gvar_set_m(name, v)
    zr_gvar_set(zr_sym2id(name), v)
  end

  #: (value, value, value) -> value
  def zr_gvar_hooked_m(shown, name, v)
    zr_gvar_hooked(zr_sym2id(shown), zr_sym2id(name), v)
  end

  #: (value, value) -> value
  def zr_gvar_alias_m(new_name, old_name)
    zr_gvar_alias(zr_sym2id(new_name), zr_sym2id(old_name))
    Machine.value(QNIL)
  end

  #: () -> void
  def zr_mark_roots
    i = 0
    while i < G_COUNT
      Machine.store64(zr_marking(), 0, Machine.word(zr_fix(1000 + i)))
      zr_mark(zr_global(i))
      i += 1
    end
    Machine.store64(zr_marking(), 0, Machine.word(zr_fix(2)))
    zr_mark_ivtab(zr_gvars())
    zr_mark(Machine.value(Machine.load64(Machine.static(:current_fiber, 8), 0)))
    zr_mark(Machine.value(Machine.load64(Machine.static(:root_fiber, 8), 0)))
    zr_mark_task(zr_task())
    Machine.store64(zr_marking(), 0, Machine.word(zr_fix(3)))
    zr_mark_kernel_roots()
    zr_mark_finalizer_queue()
    zr_mark_alloc_trace()
    zr_mark_c_roots()
  end

  # A task's roots: its slots and its frame list.
  #: (ptr) -> void
  def zr_mark_task(t)
    zr_mark(Task[t].pending)
    zr_mark(Task[t].errinfo)
    zr_mark(Task[t].guards)
    zr_mark(Task[t].recursive)
    zr_mark(Task[t].catches)
    zr_mark(Task[t].throw_tag)
    zr_mark(Task[t].found)
    zr_mark(Task[t].refine)
    zr_mark(Task[t].root_env)
    zr_mark(Task[t].flip_flops)
    zr_mark(Task[t].parked)
    zr_mark(Task[t].spread)
    # C's frames hold Values that no record lists: each C call's range of
    # the stack is read word by word.
    c = Task[t].cframe
    while c != 0
      Machine.store64(zr_marking(), 0, Machine.word(zr_fix(5)))
      zr_mark_range(CFrame[c].lo, CFrame[c].hi)
      c = CFrame[c].prev
    end
    rec = Task[t].top
    while rec != 0
      Machine.store64(zr_marking(), 0, Machine.word(zr_fix(4)))
      zr_mark(Frame[rec].self)
      zr_mark(Frame[rec].cref)
      zr_mark(Frame[rec].blk)
      zr_mark(Frame[rec].svars)
      zr_mark(Frame[rec].defined)
      n = Frame[rec].nvalues
      i = 0
      while i < n
        Machine.store64(zr_marking(), 0, Machine.word(zr_fix(100 + i)))
        zr_mark(Machine.value(Machine.load64(rec + Frame.size + (i * 8), 0)))
        i += 1
      end
      rec = Frame[rec].prev
    end
  end

  # Frees an unmarked cell of `bytes` that was live: releases what it owns,
  # and poisons it. `watched` tells whether allocation tracing, a FREEOBJ
  # hook or stress mode is on, which the sweep reads once for each arena.
  # A FREEOBJ hook hears the cell before it releases anything. A plain
  # object whose ivar entries are in its cell owns nothing outside it.
  #: (ptr, word, bool) -> void
  def zr_free_cell(cell, bytes, watched)
    if watched
      zr_trace_internal(TRACE_FREEOBJ, Machine.value(cell))
    end
    flags = Machine.load64(cell, 0)
    if (flags & FL_ALLOCATED) != 0 && ((flags & (T_MASK | FL_EXIVAR)) != T_OBJECT || !zr_ivtab_embedded_p(Machine.ptr(RObject[Machine.value(cell)].iv)))
      zr_release(Machine.value(cell))
      if (flags & FL_EXIVAR) != 0
        zr_exivar_free(Machine.value(cell))
      end
    end
    if watched
      zr_free_watched(cell, bytes)
    end
    Machine.store64(cell, 0, POISON)
  end
  # The sweep frees most cells with no call.
  inline :zr_free_cell

  #: (ptr, word) -> void
  def zr_free_watched(cell, bytes)
    if AllocTrace[zr_alloc_trace()].used != 0
      zr_alloc_trace_forget(cell)
    end
    # The mark phase checks the header's poison. The payload's poison only
    # makes a stale read fail clearly, which is the purpose of stress mode.
    if Heap[zr_heap()].stress != 0
      zr_poison_payload(cell, bytes)
    end
  end

  # Sets each payload word of a cell of `bytes` to 0xDEAD: a Value that is
  # not a fixnum, not nil and not a cell, so a read of it stops the program
  # immediately.
  #: (ptr, word) -> void
  def zr_poison_payload(cell, bytes)
    j = RBasic.size
    while j < bytes
      Machine.store64(cell + j, 0, 57005)
      j += 8
    end
  end

  # Sweeps one arena, one word of its maps at a time. Cells that are
  # allocated and not marked died in this collection, and each is freed by
  # its bit. The marks become the allocated map, and then go to zero. Thus
  # no cell is marked outside a collection, and ObjectSpace's walk of an
  # object's references (lib/zr/runtime/kernel/objspace.rb) can mark and
  # unmark. Each count moves on (zr_arena_count_low), and the old cells
  # whose count is not zero make the remembered set. A free cell is never
  # touched. Returns the live cell count; an arena with none becomes
  # reserved.
  #: (ptr) -> word
  def zr_sweep_arena(a)
    bytes = ArenaHead[a].cell
    first = zr_arena_first(a)
    marks = zr_arena_marks(a)
    ages = zr_arena_ages(a)
    remembered = zr_arena_remembered(a)
    allocated = zr_arena_allocated(a)
    low = zr_arena_count_low(a)
    high = zr_arena_count_high(a)
    stored = zr_arena_stored(a)
    watched = AllocTrace[zr_alloc_trace()].used != 0 || Heap[zr_heap()].stress != 0 || zr_trace_internal_armed(TRACE_FREEOBJ)
    live = 0
    remembers = 0
    w = 0
    while w < MARK_BYTES
      mark = Machine.load64(marks + w, 0)
      had = Machine.load64(allocated + w, 0)
      # A word with no cell, before and after, has all its maps at zero.
      if (mark | had) != 0
        dead = had & (0 - 1 - mark)
        while dead != 0
          i = Machine.ctz(dead)
          dead &= Machine.sub_wrap(dead, 1)
          zr_free_cell(first + (((w << 3) + i) * bytes), bytes, watched)
        end
        was_old = Machine.load64(ages + w, 0) & mark
        young = mark & (0 - 1 - was_old)
        was_low = Machine.load64(low + w, 0)
        was_high = Machine.load64(high + w, 0)
        # Young: 0 -> 1 -> 2 -> old. Old: 2 -> 1 -> 0, and back to 2 on a
        # promotion or a store.
        promoted = young & was_high
        old = was_old | promoted
        hit = (Machine.load64(stored + w, 0) | promoted) & old
        new_low = (young & (0 - 1 - (was_low | was_high))) | (was_old & was_high & (0 - 1 - hit))
        new_high = (young & was_low) | hit
        kept = (new_low | new_high) & old
        Machine.store64(allocated + w, 0, mark)
        Machine.store64(ages + w, 0, old)
        Machine.store64(marks + w, 0, 0)
        Machine.store64(remembered + w, 0, kept)
        Machine.store64(low + w, 0, new_low)
        Machine.store64(high + w, 0, new_high)
        Machine.store64(stored + w, 0, 0)
        remembers |= kept
        live += Machine.popcnt(mark)
      end
      w += 8
    end
    ArenaHead[a].remembered = remembers == 0 ? 0 : 1
    if live == 0
      zr_arena_reserve(a)
    end
    live
  end

  # Sweeps each arena, from the last to the first, so each size class's
  # list of arenas with room is in address order. A reserved arena is
  # already all free, and no sweep reads it. If a class's cursor arena
  # becomes reserved, the cursor is parked (`zr_full`), because no cell
  # can come from a reserved arena.
  #: () -> void
  def zr_sweep
    # @type var sc: ptr
    # @type var a: ptr
    n = Heap[zr_heap()].arenas
    c = 0
    while c < SIZE_CLASSES
      sc = zr_size_class(c)
      SizeClass[sc].freed = 0
      SizeClass[sc].room = 0
      c += 1
    end
    i = n - 1
    while i >= 0
      a = zr_arena_at(i)
      sc = zr_size_class(ArenaHead[a].index)
      if ArenaHead[a].reserved != 0
        SizeClass[sc].freed = SizeClass[sc].freed + ARENA_CELLS
      else
        live = zr_sweep_arena(a)
        SizeClass[sc].freed = SizeClass[sc].freed + (ARENA_CELLS - live)
        if live == 0
          if SizeClass[sc].cursor != zr_full() && zr_arena_of(Machine.value(SizeClass[sc].cursor)) == a
            SizeClass[sc].cursor = zr_full()
          end
        elsif live < ARENA_CELLS
          ArenaHead[a].next = SizeClass[sc].room
          SizeClass[sc].room = a
        end
      end
      i -= 1
    end
  end

  # Collects for an allocation in size class `wanting` (SIZE_CLASSES if
  # none asked). A major collection runs when the minors before it are
  # done, or when the heap is at its share of the machine and only a major
  # can free memory. All other collections are minor.
  #: (word) -> void
  def zr_collect(wanting)
    h = zr_heap()
    forced = Heap[h].stress == STRESS_FULL
    major = forced || zr_major_due()
    # A collection that an allocation starts sweeps lazily in CRuby.
    by = (Heap[h].malloced > Heap[h].malloc_limit ? GC_INFO_MALLOC : 0) | GC_INFO_LAZY
    zr_collect_kind(wanting, major)
    if forced
      Heap[h].last_info = by | GC_INFO_FORCE
    else
      Heap[h].last_info = major ? by | GC_INFO_OLDGEN : by
    end
    # If a minor left the class that ran out still short, the dead objects
    # were not young, and only a major collection can free them. CRuby
    # forces a major for the same reason (GPR_FLAG_MAJOR_BY_NOFREE). The
    # alternative is to grow the heap around objects dead for 16
    # collections. The exception is just after a major: then live objects
    # fill the class, and the room must come from growth.
    short = zr_heap_short(wanting)
    if !major && short && Heap[h].collections - Heap[h].last_major >= MAJOR_AGE
      zr_collect_kind(wanting, true)
      Heap[h].last_info = by | GC_INFO_NOFREE
      short = zr_heap_short(wanting)
    end
    zr_heap_grow(wanting, short)
    zr_malloc_limit_set()
    zr_heap_slow_update()
  end

  # Whether the next collection must be major: the old objects grew past
  # their limit, or the minors before a major are done.
  #: () -> bool
  def zr_major_due
    h = zr_heap()
    Heap[h].live > Heap[h].old_limit || Heap[h].minors >= zr_major_every()
  end

  # Whether the cells are at their share of the machine.
  #: () -> bool
  def zr_heap_pressed
    zr_heap_bytes() * 100 > zr_machine_bytes() * HEAP_SHARE
  end

  # The number of minors before a major. A pressed heap uses a smaller
  # number while its majors free enough.
  #: () -> word
  def zr_major_every
    h = zr_heap()
    if zr_heap_pressed() && Heap[h].reclaimed * MAJOR_YIELD >= Heap[h].live
      return MAJOR_EVERY_PRESSED
    end
    MAJOR_EVERY
  end

  # Whether the sweep left size class `c` below its floor of free cells.
  # SIZE_CLASSES is no class, which a collection with no request passes.
  #: (word) -> bool
  def zr_heap_short(c)
    if c >= SIZE_CLASSES
      return false
    end
    sc = zr_size_class(c)
    SizeClass[sc].freed * 100 < SizeClass[sc].arenas * ARENA_CELLS * FREE_FLOOR
  end

  # A collection of one kind, then the growth that the sweep asks for.
  #
  # A **major** collection marks from zero, so it gets to each live object
  # and the sweep frees all others.
  #
  # A **minor** collection starts its marks from the ages (the marks at the
  # end of the last collection). Thus the trace stops at each object that
  # survived, and gets only to objects allocated since then. The remembered
  # arenas supply the rest: an old object that now contains a young one is
  # traced again. The sweep is the same, and frees only the young dead.
  #
  # A minor accepts floating garbage (an old object that died after its
  # mark waits for the next major), and objects are never demoted. That is
  # the usual generational trade-off.
  #: (word, bool) -> void
  def zr_collect_kind(wanting, major)
    h = zr_heap()
    started = zr_fix2long(zr_clock_ns(zr_fix(CLOCK_MONOTONIC)))
    was = Heap[h].live
    why = 0
    if Heap[h].trace != 0 || GcProfile[zr_gc_profile()].on != 0
      why = zr_gc_why(wanting)
    end
    Heap[h].collections = Heap[h].collections + 1
    Heap[h].minors = major ? 0 : Heap[h].minors + 1
    # `minors` counts down to the next major, and a major resets it, so it
    # cannot give the number of minors. The majors are counted, and the
    # minors are `collections` minus the majors.
    if major
      Heap[h].majors = Heap[h].majors + 1
      Heap[h].last_major = Heap[h].collections
    end
    Machine.store64(zr_marking(), 0, QNIL)
    # C code runs in a collection (a T_DATA's mark and free functions), and
    # must not allocate: each allocation takes the slow path, which stops.
    Heap[h].collecting = 1
    Heap[h].slow = 1
    unless major
      zr_marks_from_ages()
    end
    zr_mark_roots()
    unless major
      zr_mark_remembered()
      zr_mark_unprotected()
    end
    zr_mark_drain()
    zr_mark_fibers()
    if !major && Heap[h].verify != 0
      zr_verify_minor()
    end
    zr_fiber_prune()
    zr_weak_prune()
    zr_unprotected_prune()
    # The trace time and the sweep time are kept separately, as CRuby
    # reports them next to the total. They measure different things: a
    # minor traces only objects allocated since the last collection, but the
    # sweep walks all arenas for both kinds. The prunes read the marks, so
    # their time counts as trace time.
    marked = zr_fix2long(zr_clock_ns(zr_fix(CLOCK_MONOTONIC)))
    measured = Heap[h].unmeasured == 0
    if measured
      Heap[h].marking = Heap[h].marking + (marked - started)
    end
    zr_sweep()
    if major
      zr_arenas_release(false)
    end
    swept = zr_fix2long(zr_clock_ns(zr_fix(CLOCK_MONOTONIC)))
    if measured
      Heap[h].sweeping = Heap[h].sweeping + (swept - marked)
    end
    Heap[h].collecting = 0
    zr_heap_slow_update()
    live = zr_live_bytes()
    Heap[h].live = live
    if major
      zr_old_limit_update(h, live)
      Heap[h].reclaimed = was > live ? was - live : 0
    end
    if measured
      Heap[h].nanoseconds = Heap[h].nanoseconds + (swept - started)
    end
    if Heap[h].trace != 0
      zr_gc_trace(why, major, was, marked - started, swept - marked)
    end
    if GcProfile[zr_gc_profile()].on != 0
      zr_gc_profile_push(started, swept - started, (major ? 1 : 0) | ((why & 16) != 0 ? 2 : 0), marked - started, swept - marked)
    end
  end

  #: () -> ptr
  def zr_gc_profile
    Machine.static(:gc_profile, GcProfile.size)
  end

  # Appends one row for the collection that just ended. The buffer is C
  # memory, so a collection can grow it. A full ring writes over its
  # oldest row.
  #: (word, word, word, word, word) -> void
  def zr_gc_profile_push(started, took, flags, mark, sweep)
    pr = zr_gc_profile()
    if GcProfile[pr].configured == 0
      GcProfile[pr].max = PROFILE_MAX_DEFAULT
      GcProfile[pr].configured = 1
    end
    max = GcProfile[pr].max
    at = GcProfile[pr].count
    if max != 0 && at == max
      at = GcProfile[pr].head
      GcProfile[pr].head = (at + 1) % max
    elsif GcProfile[pr].count == GcProfile[pr].capacity
      cap = GcProfile[pr].capacity == 0 ? 64 : GcProfile[pr].capacity * 2
      rows = Machine.ptr(Libc.malloc(cap * PROFILE_ROW * 8))
      if rows == 0
        return
      end
      if GcProfile[pr].rows != 0
        zr_memcpy(rows, GcProfile[pr].rows, GcProfile[pr].count * PROFILE_ROW * 8)
        Libc.free(GcProfile[pr].rows)
      end
      GcProfile[pr].rows = rows
      GcProfile[pr].capacity = cap
    end
    slots = 0
    c = 0
    while c < SIZE_CLASSES
      slots += SizeClass[zr_size_class(c)].arenas * ARENA_CELLS
      c += 1
    end
    row = GcProfile[pr].rows + (at * PROFILE_ROW * 8)
    Machine.store64(row, 0, started)
    Machine.store64(row, 8, took)
    Machine.store64(row, 16, Heap[zr_heap()].live)
    Machine.store64(row, 24, zr_heap_bytes())
    Machine.store64(row, 32, slots)
    Machine.store64(row, 40, flags)
    Machine.store64(row, 48, mark)
    Machine.store64(row, 56, sweep)
    Machine.store64(row, 64, GcProfile[pr].sequence)
    GcProfile[pr].sequence = GcProfile[pr].sequence + 1
    if at == GcProfile[pr].count
      GcProfile[pr].count = GcProfile[pr].count + 1
    end
  end

  # GC::Profiler's switch: true starts the rows, false stops them.
  #: (value) -> value
  def zr_gc_profile_set(flag)
    GcProfile[zr_gc_profile()].on = flag == QTRUE ? 1 : 0
    Machine.value(QNIL)
  end

  #: () -> value
  def zr_gc_profile_clear
    GcProfile[zr_gc_profile()].count = 0
    GcProfile[zr_gc_profile()].head = 0
    Machine.value(QNIL)
  end

  # GC::Profiler.configure: keeps at most `max` rows (nil for no bound),
  # and drops the rows so far.
  #: (value) -> value
  def zr_gc_profile_configure(max)
    pr = zr_gc_profile()
    GcProfile[pr].max = max == QNIL ? 0 : zr_fix2long(max)
    GcProfile[pr].configured = 1
    if GcProfile[pr].rows != 0
      Libc.free(GcProfile[pr].rows)
    end
    GcProfile[pr].rows = Machine.ptr(0)
    GcProfile[pr].capacity = 0
    zr_gc_profile_clear()
  end

  # The rows so far, oldest first, each an Array of PROFILE_ROW Integers.
  #: () -> value
  def zr_gc_profile_rows
    pr = zr_gc_profile()
    n = GcProfile[pr].count
    out = zr_ary_new(n)
    i = 0
    while i < n
      at = GcProfile[pr].max != 0 && n == GcProfile[pr].max ? (GcProfile[pr].head + i) % n : i
      row = GcProfile[pr].rows + (at * PROFILE_ROW * 8)
      fields = zr_ary_new(PROFILE_ROW)
      zr_ary_push(out, fields)
      j = 0
      while j < PROFILE_ROW
        zr_ary_push(fields, zr_fix(Machine.load64(row + (j * 8), 0)))
        j += 1
      end
      i += 1
    end
    out
  end

  # The reasons a collection is about to run, as bits: the payload is over
  # its limit (1), the live set is over the old limit (2), the minors
  # before a major are done (4), the heap is pressed (8), and no request
  # for room (16: GC.start, or stress).
  #: (word) -> word
  def zr_gc_why(wanting)
    h = zr_heap()
    why = 0
    if Heap[h].malloced > Heap[h].malloc_limit
      why = why | 1
    end
    if Heap[h].live > Heap[h].old_limit
      why = why | 2
    end
    if Heap[h].minors >= zr_major_every()
      why = why | 4
    end
    if zr_heap_pressed()
      why = why | 8
    end
    if wanting >= SIZE_CLASSES
      why = why | 16
    end
    why
  end

  # Under ZR_GC_TRACE, writes one line to stderr for each collection: its
  # number and kind, why it ran and why it was major, the heap's cells, the
  # live bytes before and after, the payload and its limit, and the trace
  # and sweep times. A major with no reason in `why` is the one that
  # zr_collect forces when a minor left the class short.
  #: (word, bool, word, word, word) -> void
  def zr_gc_trace(why, major, was, mark_ns, sweep_ns)
    h = zr_heap()
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("zr_gc "), 6)
    zr_buf_long(b, Heap[h].collections)
    if major
      zr_buf_push(b, Machine.bytes(" major"), 6)
      if (why & 2) != 0
        zr_buf_push(b, Machine.bytes(" old"), 4)
      end
      if (why & 4) != 0
        zr_buf_push(b, Machine.bytes(" every"), 6)
      end
      if (why & 22) == 0
        zr_buf_push(b, Machine.bytes(" short"), 6)
      end
    else
      zr_buf_push(b, Machine.bytes(" minor"), 6)
    end
    if (why & 16) != 0
      zr_buf_push(b, Machine.bytes(" asked"), 6)
    elsif (why & 1) != 0
      zr_buf_push(b, Machine.bytes(" malloc"), 7)
    else
      zr_buf_push(b, Machine.bytes(" room"), 5)
    end
    if (why & 8) != 0
      zr_buf_push(b, Machine.bytes(" pressed"), 8)
    end
    zr_buf_push(b, Machine.bytes(" heap "), 6)
    zr_buf_long(b, zr_heap_bytes() >> 20)
    zr_buf_push(b, Machine.bytes(" live "), 6)
    zr_buf_long(b, was >> 20)
    zr_buf_push(b, Machine.bytes(" -> "), 4)
    zr_buf_long(b, Heap[h].live >> 20)
    zr_buf_push(b, Machine.bytes(" malloced "), 10)
    zr_buf_long(b, Heap[h].malloced >> 20)
    zr_buf_push(b, Machine.bytes(" of "), 4)
    zr_buf_long(b, Heap[h].malloc_limit >> 20)
    zr_buf_push(b, Machine.bytes(" MB mark "), 9)
    zr_buf_long(b, mark_ns / 1000000)
    zr_buf_push(b, Machine.bytes(" sweep "), 7)
    zr_buf_long(b, sweep_ns / 1000000)
    zr_buf_push(b, Machine.bytes(" ms\n"), 4)
    Libc.write(2, Buf[b].ptr, Buf[b].len)
    zr_buf_free(b)
  end

  # Sets each arena's marks from its ages. Thus the trace of a minor
  # collection stops at the objects that the last collection kept.
  #: () -> void
  def zr_marks_from_ages
    n = Heap[zr_heap()].arenas
    i = 0
    while i < n
      a = zr_arena_at(i)
      zr_memcpy(zr_arena_marks(a), zr_arena_ages(a), MARK_BYTES)
      i += 1
    end
  end

  # Traces again the references of each remembered cell. It walks only the
  # arenas that the barrier flagged, and a map word with no bit set skips
  # 64 cells. CRuby's `rgengc_rememberset_mark` gets the same from its
  # `remembered_bits`.
  #: () -> void
  def zr_mark_remembered
    n = Heap[zr_heap()].arenas
    i = 0
    while i < n
      a = zr_arena_at(i)
      if ArenaHead[a].remembered != 0
        first = zr_arena_first(a)
        bytes = ArenaHead[a].cell
        map = zr_arena_remembered(a)
        j = 0
        while j < ARENA_CELLS
          word = Machine.load64(map + ((j >> 6) * 8), 0)
          if word == 0 && (j & 63) == 0
            j += 64
          else
            if (word & zr_marks_bit(j)) != 0
              v = Machine.value(first + (j * bytes))
              Machine.store64(zr_marking(), 0, Machine.word(v))
              zr_mark(RBasic[v].klass)
              zr_mark_children(v)
              if (RBasic[v].flags & FL_EXIVAR) != 0
                zr_mark_ivtab(zr_exivar_tab(v))
              end
            end
            j += 1
          end
        end
      end
      i += 1
    end
  end

  # Under ZR_GC_VERIFY, compares the marks of a minor collection with a
  # full trace. An object that the full trace gets to and the minor did not
  # is a young reference that the barrier did not remember. This reports it
  # at the time of the error, not as a freed cell some collections later.
  # CRuby uses a second collector (gc/wbcheck) for this. It is short here
  # because the compiler emits the barrier.
  #
  # The remembered map is the scratch: the minor has read it, and the sweep
  # clears it.
  #: () -> void
  def zr_verify_minor
    # @type var a: ptr
    n = Heap[zr_heap()].arenas
    i = 0
    while i < n
      a = zr_arena_at(i)
      zr_memcpy(zr_arena_remembered(a), zr_arena_marks(a), MARK_BYTES)
      Libc.memset(zr_arena_marks(a), Machine.i32(0), MARK_BYTES)
      i += 1
    end
    Machine.store64(zr_marking(), 0, QNIL)
    Heap[zr_heap()].verifying = 1
    zr_mark_roots()
    zr_mark_drain()
    zr_mark_fibers()
    Heap[zr_heap()].verifying = 0
    i = 0
    while i < n
      zr_verify_arena(zr_arena_at(i))
      i += 1
    end
    i = 0
    while i < n
      a = zr_arena_at(i)
      zr_memcpy(zr_arena_marks(a), zr_arena_remembered(a), MARK_BYTES)
      i += 1
    end
  end

  # A cell that the full trace just marked. If the minor collection did
  # not mark it, the barrier did not remember the reference to it, and
  # `zr_marking` identifies the object that contains that reference.
  #: (value) -> void
  def zr_verify_reached(v)
    a = zr_arena_of(v)
    i = zr_cell_index_in(a, v)
    if (Machine.load64(zr_remembered_word(a, i), 0) & zr_marks_bit(i)) != 0
      return
    end
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("the write barrier missed a store of a cell of type "), 51)
    zr_buf_long(b, RBasic[v].flags & T_MASK)
    zr_buf_push(b, Machine.bytes(" into "), 6)
    parent = Machine.value(Machine.load64(zr_marking(), 0))
    if zr_fixnum_p(parent)
      zr_buf_push(b, Machine.bytes("root "), 5)
      zr_buf_long(b, zr_fix2long(parent))
    elsif zr_special_p(parent)
      zr_buf_push(b, Machine.bytes("a root"), 6)
    else
      zr_buf_push(b, Machine.bytes("a cell of type "), 15)
      zr_buf_long(b, RBasic[parent].flags & T_MASK)
    end
    zr_buf_byte(b, 10)
    zr_bug(Buf[b].ptr, Buf[b].len)
  end

  # Each cell of `a` that the full trace marked and the minor did not.
  #: (ptr) -> void
  def zr_verify_arena(a)
    marks = zr_arena_marks(a)
    minor = zr_arena_remembered(a)
    first = zr_arena_first(a)
    bytes = ArenaHead[a].cell
    j = 0
    while j < ARENA_CELLS
      missed = Machine.load64(marks + ((j >> 6) * 8), 0) & (0 - 1 - Machine.load64(minor + ((j >> 6) * 8), 0))
      if missed == 0 && (j & 63) == 0
        j += 64
      else
        if (missed & zr_marks_bit(j)) != 0
          b = Machine.slot(Buf.size)
          zr_buf_init(b)
          zr_buf_push(b, Machine.bytes("a minor collection did not reach a live cell of type "), 53)
          zr_buf_long(b, Machine.load64(first + (j * bytes), 0) & T_MASK)
          zr_buf_push(b, Machine.bytes(": the write barrier missed a store into it\n"), 43)
          zr_bug(Buf[b].ptr, Buf[b].len)
        end
        j += 1
      end
    end
  end

  # A size class grows when the sweep left less than FREE_FLOOR hundredths
  # of its capacity free, and then grows to FREE_GOAL free. The sweep
  # counted the free cells, so each live set is known and the heap gets to
  # its size in one step, with no overshoot.
  #
  # `wanting` (the class whose empty free list started this collection)
  # grows so that the whole heap has free bytes equal to its live bytes. A
  # collection marks all live objects of all sizes, so its cost is shared
  # across all of them. The budget is the heap's, not each class's: with
  # free bytes equal to the live bytes in each class that ran out, an eval
  # loop with 8 MB live grew each of the four classes to 8 MB free, and
  # touched all of it. The unit is bytes, not cells: with cells, the
  # 256-byte class got eight times the room of the 32-byte class for the
  # same count.
  #
  # A class that the sweep already left with room does not grow. (Growth
  # of each class to two times its live set on each collection grew a tree
  # benchmark's class from 23 arenas to 36 with no new live cells.)
  #
  # Reserved arenas count as free, so a class that has one does not grow.
  # This is CRuby's tomb, which `gc_sweep_finish_heap` empties before it
  # asks the host for a page.
  #
  # `short` means that the class that ran out is still below its floor
  # after the collection, and the collector did not (or could not) run a
  # major for it. Live objects fill the class, so it gets the full growth,
  # pressed or not. Twenty percent free of a small class in a large heap is
  # a few megabytes, and a collection that sweeps the whole heap for them
  # runs again immediately.
  #: (word, bool) -> void
  def zr_heap_grow(wanting, short)
    # The machine limits the heap. When the cells are at their share of it,
    # each class grows only to the floor, with no share of the heap's live
    # bytes. The collector runs more frequently and asks the host for no
    # more memory, because a collection costs less than a page-in.
    pressed = zr_heap_pressed()
    goal = pressed ? FREE_FLOOR : FREE_GOAL
    live_bytes = zr_live_bytes()
    free_bytes = 0
    c = 0
    while c < SIZE_CLASSES
      if c != wanting
        free_bytes += SizeClass[zr_size_class(c)].freed * (CELL_MIN << c)
      end
      c += 1
    end
    budget = live_bytes > free_bytes ? live_bytes - free_bytes : 0
    c = 0
    while c < SIZE_CLASSES
      sc = zr_size_class(c)
      capacity = SizeClass[sc].arenas * ARENA_CELLS
      free = SizeClass[sc].freed
      live = capacity - free
      want = capacity
      most = (capacity * GROWTH) / 100
      if c == wanting && short
        want = most
      elsif c == wanting && !pressed
        want = live + (budget / (CELL_MIN << c))
      end
      if free * 100 < capacity * FREE_FLOOR
        floor = (live * 100) / (100 - goal)
        want = want > floor ? want : floor
      end
      cells = want < most ? want : most
      while SizeClass[sc].arenas * ARENA_CELLS < cells
        zr_arena_add(c)
      end
      c += 1
    end
  end

  # Sets the payload limit for the next collection: the current payload
  # plus a bounded increase.
  #: () -> void
  def zr_malloc_limit_set
    h = zr_heap()
    malloced = Heap[h].malloced
    grown = (malloced * (MALLOC_GROWTH - 100)) / 100
    step = grown < MALLOC_LIMIT ? MALLOC_LIMIT : grown
    Heap[h].malloc_limit = malloced + (step > MALLOC_LIMIT_MAX ? MALLOC_LIMIT_MAX : step)
  end

  # The payload bytes and the limit that starts the collector, for
  # GC.stat.
  #: () -> value
  def zr_gc_malloced
    zr_fix(Heap[zr_heap()].malloced)
  end

  #: () -> value
  def zr_gc_malloc_limit
    zr_fix(Heap[zr_heap()].malloc_limit)
  end

  # The total nanoseconds of all collections.
  #: () -> value
  def zr_gc_nanoseconds
    zr_fix(Heap[zr_heap()].nanoseconds)
  end

  # The major collection count, and the nanoseconds of traces and of
  # sweeps: the numbers for `major_gc_count`, `minor_gc_count`,
  # `marking_time` and `sweeping_time`.
  #: () -> value
  def zr_gc_phases
    h = zr_heap()
    out = zr_ary_new(3)
    zr_ary_push(out, zr_fix(Heap[h].majors))
    zr_ary_push(out, zr_fix(Heap[h].marking))
    zr_ary_push(out, zr_fix(Heap[h].sweeping))
    out
  end

  # The GC module's view of the heap. `disable` and `enable` return
  # whether collection was disabled before. While it is disabled, the heap
  # grows when the cells run out, as CRuby's does.
  #: () -> value
  def zr_gc_start
    zr_gc_start_m(Machine.value(QTRUE), Machine.value(QTRUE))
  end

  # GC.start: a major collection, or with `full_mark` false a minor one,
  # unless a major is due anyway. Every sweep here is immediate, so
  # `immediate_sweep` only shows in GC.latest_gc_info.
  #: (value, value) -> value
  def zr_gc_start_m(full_mark, immediate_sweep)
    h = zr_heap()
    full = full_mark != QFALSE && full_mark != QNIL
    due = zr_major_due()
    zr_collect_kind(SIZE_CLASSES, full || due)
    if full || due
      zr_arenas_release(true)
    end
    info = GC_INFO_METHOD
    if full
      info = info | GC_INFO_FORCE
    elsif due
      info = info | GC_INFO_OLDGEN
    end
    if immediate_sweep == QFALSE || immediate_sweep == QNIL
      info = info | GC_INFO_LAZY
    end
    Heap[h].last_info = info
    zr_heap_grow(SIZE_CLASSES, false)
    zr_malloc_limit_set()
    zr_heap_slow_update()
    zr_data_frees_run()
    zr_finalizers_run()
  end

  # GC.measure_total_time=: while it is off, collections add nothing to
  # the times that GC.stat reports.
  #: (value) -> value
  def zr_gc_measure_set(flag)
    Heap[zr_heap()].unmeasured = flag == QFALSE || flag == QNIL ? 1 : 0
    flag
  end

  # GC.latest_gc_info's numbers: the last collection's GC_INFO_* bits,
  # whether the next must be major, and the weak references that its
  # prune saw.
  #: () -> value
  def zr_gc_info
    h = zr_heap()
    out = zr_ary_new(4)
    zr_ary_push(out, zr_fix(Heap[h].last_info))
    zr_ary_push(out, zr_bool(zr_major_due()))
    zr_ary_push(out, zr_fix(Heap[h].weak_refs))
    out
  end

  # The bytes that the runtime has allocated and freed since it started,
  # as GC.stat's total_malloc_bytes and total_free_bytes count them.
  #: () -> value
  def zr_gc_malloc_totals
    h = zr_heap()
    out = zr_ary_new(2)
    zr_ary_push(out, zr_fix(Heap[h].malloc_total))
    zr_ary_push(out, zr_fix(Heap[h].free_total))
    out
  end

  #: () -> value
  def zr_gc_count
    zr_fix(Heap[zr_heap()].collections)
  end

  # The number of objects that each size class allocated.
  #: () -> value
  def zr_gc_allocated
    n = 0
    c = 0
    while c < SIZE_CLASSES
      n += SizeClass[zr_size_class(c)].allocated
      c += 1
    end
    zr_fix(n)
  end

  # Size class `c` for GC.stat_heap: its cell size, live cells, free
  # cells, arenas in use (not reserved, zr_heap_cells) and allocated
  # object count. A pool after the fourth has only its size.
  #: (value) -> value
  def zr_gc_pool(c)
    i = zr_fix2long(c)
    bytes = CELL_MIN << i
    live = 0
    arenas = 0
    allocated = 0
    if i < SIZE_CLASSES
      sc = zr_size_class(i)
      allocated = SizeClass[sc].allocated
      a = 0
      while a < Heap[zr_heap()].arenas
        base = zr_arena_at(a)
        if ArenaHead[base].index == i && ArenaHead[base].reserved == 0
          live += zr_arena_live(base)
          arenas += 1
        end
        a += 1
      end
    end
    out = zr_ary_new(5)
    zr_ary_push(out, zr_fix(bytes))
    zr_ary_push(out, zr_fix(live))
    zr_ary_push(out, zr_fix((arenas * ARENA_CELLS) - live))
    zr_ary_push(out, zr_fix(arenas))
    zr_ary_push(out, zr_fix(allocated))
    out
  end

  # The cell count of the arenas in use, of all sizes. A reserved arena is
  # all free and gives cells only when the others are full, as a page that
  # CRuby has freed to its pool: GC.stat and ObjectSpace.count_objects do
  # not count it.
  #: () -> word
  def zr_heap_cells
    h = zr_heap()
    n = 0
    a = 0
    while a < Heap[h].arenas
      if ArenaHead[zr_arena_at(a)].reserved == 0
        n += 1
      end
      a += 1
    end
    n * ARENA_CELLS
  end

  #: (value) -> value
  def zr_gc_set_disabled(flag)
    h = zr_heap()
    was = zr_bool(Heap[h].disabled != 0)
    Heap[h].disabled = flag == QTRUE ? 1 : 0
    was
  end

  #: (value) -> value
  def zr_gc_set_stress(flag)
    h = zr_heap()
    if flag == QNIL || flag == QFALSE
      Heap[h].stress = 0
    elsif zr_fixnum_p(flag) && (zr_fix2long(flag) & 1) != 0
      Heap[h].stress = STRESS_MINOR
    else
      Heap[h].stress = STRESS_FULL
    end
    zr_heap_slow_update()
    flag
  end

  #: () -> value
  def zr_gc_stress
    zr_bool(Heap[zr_heap()].stress != 0)
  end

  # Allocates a cell of `type` with class `klass`, from the smallest size
  # class that fits `bytes`. The payload is as the last owner left it: the
  # constructor writes each field before anything can collect or read the
  # cell. Under stress the payload is poison, so a field that the
  # constructor did not write reads as 0xDEAD, not as empty. The caller
  # stores the result to its frame record before any other allocation.
  #
  # Inline at each allocation: it uses a clear bit in the cursor's word if
  # there is one and `Heap.slow` is clear, else `zr_alloc_slow`.
  #: (word, value, word) -> value
  def zr_alloc(type, klass, bytes)
    sc = zr_size_class(zr_size_class_for(bytes))
    bits = Machine.load64(SizeClass[sc].cursor, 0)
    if bits == ALL_MARKED || Heap[zr_heap()].slow != 0
      zr_alloc_slow(type, klass, bytes)
    else
      zr_cell_take(sc, bits, type, klass)
    end
  end

  inline :zr_alloc

  # The cell of the first clear bit of `bits`, the word at size class
  # `sc`'s cursor. It sets the bit and writes the header. The word's
  # address and the bit give the cell's address from the class's origin,
  # by its shift. It is small enough that the IR inliner copies it into
  # each constructor (Passes::Inline::LIMIT).
  #: (ptr, word, word, value) -> value
  def zr_cell_take(sc, bits, type, klass)
    at = SizeClass[sc].cursor
    i = Machine.ctz(0 - 1 - bits)
    Machine.store64(at, 0, bits | Machine.shl_wrap(1, i))
    SizeClass[sc].allocated = SizeClass[sc].allocated + 1
    cell = Machine.uadd_wrap(SizeClass[sc].origin, ((Machine.word(at) << 3) + i) << SizeClass[sc].shift)
    Machine.store64(cell, 0, type | FL_ALLOCATED)
    Machine.store64(cell, 8, Machine.word(klass))
    Machine.value(cell)
  end

  # Whether an allocation must use `zr_alloc_slow`: under stress, while
  # allocations are traced or a C hook hears NEWOBJ, or when the payload
  # is over its limit. Each change to one of these calls this again.
  #: () -> void
  def zr_heap_slow_update
    h = zr_heap()
    slow = Heap[h].stress != 0 || AllocTrace[zr_alloc_trace()].on != 0 || Heap[h].malloced > Heap[h].malloc_limit ||
           zr_trace_internal_armed(TRACE_NEWOBJ)
    Heap[h].slow = slow ? 1 : 0
  end

  # An allocation that `zr_alloc` cannot do inline: it moves the cursor to
  # a word with room, collects if there is none, or when the payload is
  # over its limit or stress asks. It also writes the stress poison and
  # the allocation trace's record.
  #: (word, value, word) -> value
  def zr_alloc_slow(type, klass, bytes)
    h = zr_heap()
    if Heap[h].collecting != 0
      zr_bug(Machine.bytes("[BUG] object allocation during garbage collection phase\n"), 56)
    end
    c = zr_size_class_for(bytes)
    sc = zr_size_class(c)
    # A stress collection runs at each allocation, whatever the room, so
    # it asks only for the normal growth. More room only makes the next
    # sweep longer.
    if Heap[h].stress != 0 && Heap[h].disabled == 0
      zr_collect(SIZE_CLASSES)
    end
    # The cursor takes a reserved arena before a collection: the reserve is
    # room that the last collection already paid for.
    room = zr_cursor_advance(sc)
    if (!room || Heap[h].malloced > Heap[h].malloc_limit) && Heap[h].disabled == 0
      zr_collect(c)
      room = zr_cursor_advance(sc)
    end
    if !room
      zr_arena_add(c)
      zr_cursor_advance(sc)
    end
    v = zr_cell_take(sc, Machine.load64(SizeClass[sc].cursor, 0), type, klass)
    cell = Machine.ptr(v)
    if Heap[h].stress != 0
      zr_poison_payload(cell, CELL_MIN << c)
    end
    if AllocTrace[zr_alloc_trace()].on != 0
      zr_alloc_trace_record(cell)
    end
    zr_trace_internal(TRACE_NEWOBJ, v)
    zr_heap_slow_update()
    v
  end

  # Each kernel function that can run the collector keeps its Values in a
  # root frame (`prev, n, values...`) that the compiler links from here.
  collects :zr_collect
  collects :zr_collect_kind

  #: () -> ptr
  def zr_kroots
    Machine.static(:kroots, 8)
  end

  #: () -> void
  def zr_mark_kernel_roots
    zr_mark_kernel_roots_from(Machine.ptr(Machine.load64(zr_kroots(), 0)))
  end

  #: (ptr) -> void
  def zr_mark_kernel_roots_from(frame)
    while frame != 0
      n = Machine.load64(frame, 8)
      i = 0
      while i < n
        zr_mark(Machine.value(Machine.load64(frame + 16 + (i * 8), 0)))
        i += 1
      end
      frame = Machine.ptr(Machine.load64(frame, 0))
    end
  end

  # `global_variables`: each name with an entry, and each alias of one.
  #: () -> value
  def zr_global_variables
    out = zr_ary_new(16)
    zr_ivtab_names(zr_gvars(), out, 36)
    zr_ivtab_names(zr_gvar_aliases(), out, 36)
    out
  end
end
