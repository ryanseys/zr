# frozen_string_literal: true

# `debug/debug.so`: the C half of the debug gem, over the frames the
# kernel lets a debugger read (zr_debug_frames). The Ruby half is the
# gem's own.
module DEBUGGER__
  SO_VERSION = "1.11.1"

  # Every frame outward from the caller, as a FrameInfo, but for the ones
  # whose file starts with `skip_path_prefix`: the debugger's own.
  def self.capture_frames(skip_path_prefix)
    frames = Primitive.zr_debug_frames
    depth = frames.size
    frames.each_with_index.filter_map do |(row, node, receiver, bound, meta, klass), i|
      location = Thread::Backtrace::Location.new(row, node)
      iseq = meta.zero? ? nil : RubyVM::InstructionSequence.send(:of_frame, meta)
      path = iseq ? iseq.absolute_path || iseq.path : location.path
      next if path && skip_path_prefix && path.start_with?(skip_path_prefix)

      FrameInfo.new(location, receiver, bound, iseq, klass, depth - i)
    end
  end

  def self.frame_depth = Primitive.zr_debug_frames.size
end

class RubyVM
  class InstructionSequence
    def type
      meta = Primitive.zr_hidden_get(self, :__meta__)
      meta.nil? || meta.zero? ? :top : Primitive.zr_iseq_meta_info(meta)[2]
    end

    # The names of the parameters, but for the anonymous `*`, `**` and `&`.
    def parameters_symbols
      meta = Primitive.zr_hidden_get(self, :__meta__)
      return [] if meta.nil? || meta.zero?

      Primitive.zr_iseq_meta_parameters(meta).filter_map { |row| row[1] if row.size == 2 && !%i[* ** &].include?(row[1]) }
    end

    def first_line = first_lineno
    def last_line = first_lineno
  end
end

module ObjectSpace
  # The instruction sequences alive in the process: the code this
  # runtime compiled is not objects, so there are none to walk.
  def self.each_iseq
    return to_enum(:each_iseq) unless block_given?

    0
  end

  def self.count_iseq = 0
end
