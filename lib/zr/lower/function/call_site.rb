# frozen_string_literal: true

module Zr
  class Lower
    class Function
      # The values that the in-place paths of one send site share: the
      # call `node`, the site's cache cell `cc`, the receiver `recv`, the
      # cell's `entry`, the staged arguments `argv`, and the `merge` block
      # that takes the result. A path that has no cell (`opt_send`) or no
      # entry (an inline copy) leaves `cc` or `entry` nil.
      CallSite = Data.define(:node, :cc, :recv, :entry, :argv, :merge)

      # The default of `cc` and `entry` is in a reopened class, not in the
      # block of `Data.define`, so that the type check
      # (sig/zr/lower/function/call_site.rbs) sees it in the class that it
      # belongs to.
      class CallSite
        def initialize(node:, recv:, argv:, merge:, cc: nil, entry: nil) = super
      end
    end
  end
end
