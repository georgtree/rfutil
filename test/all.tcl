package require tcltest 2
set root [file dirname [file dirname [file normalize [info script]]]]
lappend auto_path $root

if {![info exists ::env(TCLLIBPATH)]} {
    set ::env(TCLLIBPATH) {}
}
lappend ::env(TCLLIBPATH) $root

::tcltest::configure -load [list lappend auto_path $root] -testdir [file join $root test] {*}$argv
exit [expr {[::tcltest::runAllTests] ? 1 : 0}]
