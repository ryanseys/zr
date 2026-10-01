# frozen_string_literal: true

module Zr
  module Native
    # One typed-Ruby kernel file that `zr machine` compiled
    # (`Machine.compile`): its functions, its data, and the names of the
    # raw functions that it calls. It has no runtime, so its build is one
    # unit for everything.
    #
    # It answers the messages of a `Zr::Program` that `zr` sends to build
    # an output, so `zr machine` and `zr build` share one path. Each writes
    # the output to `out` and returns nil, or the message of the step that
    # refused (`Native::Build`, which the caller loads).
    UnitProgram = Data.define(:functions, :data, :raw, :target) do
      def write_object(out)
        Build.object(functions, data, out, raw: raw, export: true, target: target)
      end

      def write_wasm(out) = Build.wasm(functions, data, out, raw: raw)

      def write_binary(out, work:, link:)
        Build.binary(functions, data, out, work: work, raw: raw, target: target, link: link)
      end
    end
  end
end
