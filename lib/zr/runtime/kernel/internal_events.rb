module Zr::Kern
  # The internal events of ruby/debug.h that C TracePoints hear:
  # RUBY_INTERNAL_EVENT_NEWOBJ when an object is allocated, after its
  # header and its class are set, and RUBY_INTERNAL_EVENT_FREEOBJ when the
  # sweep frees one, before it releases what the object owns. Ruby code
  # cannot run there, so the hooks are C functions that this file calls
  # directly, not through TracePoint.fire. A hook runs with the collector
  # off and hears no internal event of its own, as ruby's hooks do.
  # TracePoint.rearm gives the hooks of the enabled C points
  # (zr_trace_internal_set); the enabled list keeps those points.

  TRACE_NEWOBJ = 0x100000
  TRACE_FREEOBJ = 0x200000

  # A hook: the C function, data and form (HOOK_POINT or HOOK_RAW,
  # trace.rb) of a point, the point, and the internal events that it
  # hears.
  class InternalHook < Layout
    attr_accessor :func #: ptr
    attr_accessor :data #: ptr
    attr_accessor :form #: word
    attr_accessor :point #: value
    attr_accessor :events #: word
  end

  # The trace arg of the internal event that the hooks handle: the point
  # whose hook runs, the event (0 when none runs) and the object.
  class InternalArg < Layout
    attr_accessor :point #: value
    attr_accessor :event #: word
    attr_accessor :object #: value
  end

  #: () -> ptr
  def zr_internal_arg
    Machine.static(:internal_arg, InternalArg.size)
  end

  # Whether a hook hears the internal event `event`.
  #: (word) -> bool
  def zr_trace_internal_armed(event)
    (Machine.load64(Machine.static(:internal_events, 8), 0) & event) != 0
  end

  # The hooks of the C points that hear internal events, from `rows`:
  # `[hook, point, events]` for each point, where `hook` holds the words
  # of its C function, its data and its form (TracePoint.c_point). The
  # list that a hook runs from is not freed under it.
  #: (value) -> value
  def zr_trace_internal_set(rows)
    hooks = Machine.static(:internal_hooks, 16)
    old = Machine.ptr(Machine.load64(hooks, 0))
    if old != 0 && Machine.load64(Machine.static(:internal_running, 8), 0) == 0
      zr_xfree(old)
    end
    n = RArray[rows].len
    list = Machine.ptr(0)
    if n > 0
      list = zr_xmalloc(n * InternalHook.size)
    end
    events = 0
    i = 0
    while i < n
      row = zr_ary_at(rows, i)
      words = RString[zr_ary_at(row, 0)].ptr
      hook = list + (i * InternalHook.size)
      InternalHook[hook].func = Machine.ptr(Machine.load64(words, 0))
      InternalHook[hook].data = Machine.ptr(Machine.load64(words, 8))
      InternalHook[hook].form = Machine.load64(words, 16)
      InternalHook[hook].point = zr_ary_at(row, 1)
      InternalHook[hook].events = zr_fix2long(zr_ary_at(row, 2))
      events |= InternalHook[hook].events
      i += 1
    end
    Machine.store64(hooks, 0, Machine.word(list))
    Machine.store64(hooks, 8, n)
    Machine.store64(Machine.static(:internal_events, 8), 0, events & (TRACE_NEWOBJ | TRACE_FREEOBJ))
    # Every allocation takes the slow path while a hook hears NEWOBJ.
    zr_heap_slow_update()
    Machine.value(QNIL)
  end

  # Calls each hook that hears `event` about `obj`, unless a hook runs
  # already or an event is quiet (zr_trace_row_new): the objects of an
  # event's own row are the runtime's. A cell that the runtime keeps for
  # itself has no class, and is no object of the program's, so it is no
  # event. A hook of the
  # event-hook form (`func(event, data, self, mid, klass)`) hears none:
  # a call from the sweep passes two words.
  #: (word, value) -> void
  def zr_trace_internal(event, obj)
    running = Machine.static(:internal_running, 8)
    if !zr_trace_internal_armed(event) || Machine.load64(running, 0) != 0 || Machine.load64(zr_trace_quiet(), 0) != 0 ||
       zr_special_p(Machine.value(Machine.load64(Machine.ptr(obj), 8)))
      return
    end
    Machine.store64(running, 0, 1)
    h = zr_heap()
    disabled = Heap[h].disabled
    Heap[h].disabled = 1
    arg = zr_internal_arg()
    InternalArg[arg].event = event
    InternalArg[arg].object = obj
    hooks = Machine.static(:internal_hooks, 16)
    list = Machine.ptr(Machine.load64(hooks, 0))
    n = Machine.load64(hooks, 8)
    i = 0
    while i < n
      hook = list + (i * InternalHook.size)
      if (InternalHook[hook].events & event) != 0
        InternalArg[arg].point = InternalHook[hook].point
        if InternalHook[hook].form == HOOK_RAW
          zr_call_c_in_gc(InternalHook[hook].func, InternalHook[hook].data, arg)
        elsif InternalHook[hook].form == HOOK_POINT
          zr_call_c_in_gc(InternalHook[hook].func, Machine.ptr(InternalHook[hook].point), InternalHook[hook].data)
        end
      end
      i += 1
    end
    InternalArg[arg].event = 0
    InternalArg[arg].object = Machine.value(QNIL)
    InternalArg[arg].point = Machine.value(QNIL)
    Heap[h].disabled = disabled
    Machine.store64(running, 0, 0)
  end
end
