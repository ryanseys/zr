# frozen_string_literal: true

# `autoload :C, "feature"` names a file that PROVIDES `C`. zr has no
# lazy units, so the file is spliced in and the constant is there before
# anything asks for it -- zr's own stated divergence from CRuby: the
# file runs at the `autoload` statement rather than at first constant
# access, and even if the constant is never referenced.
#
# A feature no load path carries is one the runtime already holds, and
# the declaration opens its gate where it stands.

autoload :JSON, "json"

p JSON.name
p JSON.instance_of?(Module)

# The declaration itself answers nil.
p(autoload(:JSON, "json"))
