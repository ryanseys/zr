# frozen_string_literal: true

# A pilot of the type check, on a few files. `bin/steep check` runs it.
# A file with methods carries inline RBS annotations (`#:` and `# @rbs`).
# A file that assigns a Struct or a Data record to a constant has its
# types in sig/pilot, because the inline form cannot type such a record.
# The rest of lib/ stays unchecked. sig/zr_kern.rbs is generated for the
# kernel and is not part of this check.
target :pilot do
  # Inline.
  check "lib/zr/bytes.rb", inline: true
  check "lib/zr/target.rb", inline: true
  check "lib/zr/ir/inst.rb", inline: true
  check "lib/zr/ir/types.rb", inline: true

  # Records: sig/pilot/obj_model.rbs and sig/pilot/records.rbs.
  check "lib/zr/obj/model.rb"
  check "lib/zr/load_tables.rb"
  check "lib/zr/lower/function/loop.rb"
  check "lib/zr/lower/function/call_site.rb"

  # The records, and the classes that the checked files use and that no
  # checked file defines (sig/pilot/collaborators.rbs).
  signature "sig/pilot"
end
