# `defined?` and its `const_defined?` / `constants.include?` spellings ask
# whether a name is bound YET. A definition further down the program has not
# run, so at the guard the answer is no -- which is exactly what the
# define-it-if-nobody-else-did idiom is written for.

# guard-compat's shape: create the namespace, then fill it in later.
unless Object.const_defined?('Guard')
  module Guard
  end
end
module Guard
  module Compat
    class Plugin
      def tag = "p"
    end
  end
end
p Guard::Compat::Plugin.new.tag
p Guard.instance_of?(Module)

