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
    locations = Thread.send(:frame_locations, frames)
    frames.each_with_index.filter_map do |(_row, _node, receiver, bound, meta, klass), i|
      location = locations[i]
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

    # The line of the code's `end`, when the code has one (a method, a
    # block, a class body), else its first line.
    def last_line = last_of_meta || first_lineno

    private

    def last_of_meta
      meta = Primitive.zr_hidden_get(self, :__meta__)
      last = Primitive.zr_iseq_meta_info(meta)[3] if meta&.nonzero?
      last if last&.positive?
    end
  end
end

module ObjectSpace
  # The instruction sequences of the program's code: in a traced build
  # (a program that loads the debugger is one), the main file's and each
  # loaded file's, and the code in them, as CRuby's iseq list has them.
  # Another build keeps none.
  def self.each_iseq(&block)
    return to_enum(:each_iseq) unless block_given?

    iseqs.each(&block).size
  end

  def self.count_iseq = iseqs.size

  class << self
    private

    # A file's code is there once the file has loaded, as CRuby compiles
    # it then.
    def iseqs
      found = []
      loaded = $LOADED_FEATURES.to_set
      pending = Primitive.zr_iseq_metas.filter_map do |meta|
        iseq = RubyVM::InstructionSequence.send(:of_frame, meta)
        iseq if iseq.send(:code_type) == :main || loaded.include?(iseq.absolute_path)
      end
      while (iseq = pending.shift)
        found << iseq
        iseq.each_child { |child| pending << child }
      end
      found
    end
  end
end
