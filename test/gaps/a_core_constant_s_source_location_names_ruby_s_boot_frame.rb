# CRuby gives a source location to the core constants that its boot set
# while a frame ran: thread_sync.rb's aliases at their lines, and others
# at "<main>" or "ruby" line 0. The "previous definition" line of a class
# reopened as a module names it. zr gives no location to a core constant,
# as CRuby does for String.
p Object.const_source_location(:Monitor)
p Object.const_source_location(:Queue)
p Object.const_source_location(:Set)
p Object.const_source_location(:RUBY_VERSION)
p Object.const_source_location(:String)
