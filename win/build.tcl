# Implementation of the native Windows Nmake targets. Uses only core Tcl.
namespace eval ::rfutilBuild {
    variable root [file dirname [file dirname [file normalize [info script]]]]
    variable version 0.2
    variable runtimeFiles {rfutil.tcl pkgIndex.tcl LICENSE}
    variable docFiles {index.html rfutil.html rfutil-rfutil.html genindex.html search.html
        objects.inv searchindex.js .buildinfo .nojekyll rfutil.n rfutil-rfutil.n}
    variable sourceFiles {README.md LICENSE configure configure.ac
        aclocal.m4 Makefile.in pkgIndex.tcl rfutil.tcl test examples tclconfig}
}

proc ::rfutilBuild::Children {directory} {
    set result {}
    foreach path [glob -nocomplain -directory $directory * .*] {
        if {[file tail $path] ni {. ..}} {lappend result $path}
    }
    return $result
}

proc ::rfutilBuild::Copy {source destination} {
    file mkdir [file dirname $destination]
    puts "Installing $source -> $destination"
    if {[file isdirectory $source]} {
        file mkdir $destination
        foreach path [Children $source] {
            Copy $path [file join $destination [file tail $path]]
        }
    } else {
        file copy -force -- $source $destination
    }
}

proc ::rfutilBuild::Staged {stage destination} {
    if {$stage eq {}} {return $destination}
    # Strip an absolute path's root/drive before prefixing a staging directory.
    set parts [file split $destination]
    if {[file pathtype $destination] ne {relative}} {set parts [lrange $parts 1 end]}
    return [file join $stage {*}$parts]
}

proc ::rfutilBuild::CopyDocs {source destination} {
    variable docFiles
    foreach name $docFiles {
        if {[file isfile [file join $source $name]]} {
            Copy [file join $source $name] [file join $destination $name]
        }
    }
    foreach name {_static _sources} {
        set from [file join $source $name]
        if {[file isdirectory $from]} {
            # Copy contents, rather than nesting a second directory on repeated installs.
            file mkdir [file join $destination $name]
            foreach item [glob -nocomplain -directory $from *] {
                Copy $item [file join $destination $name [file tail $item]]
            }
        }
    }
}

proc ::rfutilBuild::RemoveEmpty {path} {
    if {[file isdirectory $path] &&
        [Children $path] eq {}} {
        file delete $path
    }
}

proc ::rfutilBuild::Main {target args} {
    variable root
    variable version
    variable runtimeFiles
    variable sourceFiles
    variable docFiles
    set options [dict create -out [file join $root win build] -docs [file join $root docs]\
        -python python -dist [file join $root win build dist] -name rfutil-$version\
        -lib C:/Tcl91/lib -docinstall C:/Tcl91/share/rfutil$version/doc\
        -man C:/Tcl91/share/man -stage {}]
    set extra {}
    while {[llength $args]} {
        set key [lindex $args 0]
        if {$key eq {--}} {set extra [lrange $args 1 end]; break}
        if {![dict exists $options $key] || [llength $args] < 2} {error "invalid build option: $key"}
        dict set options $key [lindex $args 1]
        set args [lrange $args 2 end]
    }
    set out [file normalize [dict get $options -out]]
    set docs [file normalize [dict get $options -docs]]
    set dist [file normalize [dict get $options -dist]]
    set distName [dict get $options -name]
    if {$distName in {{} . ..} || [regexp {[/\\:]} $distName]} {error {DIST_NAME must be a single directory name}}
    set stage [file join $dist $distName]
    set library [Staged [dict get $options -stage] [file join [dict get $options -lib] rfutil$version]]
    set docinstall [Staged [dict get $options -stage] [dict get $options -docinstall]]
    set man [Staged [dict get $options -stage] [file join [dict get $options -man] mann]]
    switch -- $target {
        all {
            file mkdir $out
            foreach name $runtimeFiles {Copy [file join $root $name] [file join $out $name]}
        }
        test - test-vector {
            if {$target eq {test-vector}} {set ::env(RFUTIL_REQUIRE_RBC) 1}
            if {![info exists ::env(TCLLIBPATH)]} {set ::env(TCLLIBPATH) {}}
            lappend ::env(TCLLIBPATH) $out
            exec [info nameofexecutable] [file join $root test all.tcl] {*}$extra >@stdout 2>@stderr
        }
        doc {
            set ::env(RFUTIL_DOC_DIR) $docs
            set ::env(DOC_PYTHON) [dict get $options -python]
            exec [info nameofexecutable] [file join $root docs doc_gen.tcl] {*}$extra >@stdout 2>@stderr
        }
        install-libraries {
            foreach name $runtimeFiles {Copy [file join $root $name] [file join $library $name]}
        }
        install-doc {
            if {![file isfile [file join $docs index.html]]} {
                puts {Documentation not generated; run nmake /f makefile.vc doc to install the manual.}
                return
            }
            CopyDocs $docs $docinstall
            foreach name {rfutil.n rfutil-rfutil.n} {Copy [file join $docs $name] [file join $man $name]}
        }
        uninstall-libraries {
            foreach name $runtimeFiles {file delete -force [file join $library $name]}
            RemoveEmpty $library
        }
        uninstall-doc {
            foreach name $docFiles {file delete -force [file join $docinstall $name]}
            foreach name {_static _sources} {file delete -force [file join $docinstall $name]}
            foreach name {rfutil.n rfutil-rfutil.n} {file delete -force [file join $man $name]}
            RemoveEmpty $docinstall
        }
        dist - dist-zip {
            file delete -force $stage
            file mkdir $stage
            foreach name $sourceFiles {Copy [file join $root $name] [file join $stage $name]}
            foreach name {makefile.vc build.tcl} {
                Copy [file join $root win $name] [file join $stage win $name]
            }
            foreach name {doc_gen.tcl startPage.ruff _static/manual.css} {
                Copy [file join $root docs $name] [file join $stage docs $name]
            }
            CopyDocs $docs [file join $stage docs]
            set tar tar
            if {$::tcl_platform(platform) eq {windows}} {
                set tar [file join $::env(SystemRoot) System32 tar.exe]
            }
            if {$target eq {dist}} {
                exec $tar -czf $stage.tar.gz -C $dist $distName >@stdout 2>@stderr
            } elseif {$::tcl_platform(platform) eq {windows}} {
                # MSYS2 tar on PATH does not implement ZIP creation; use Windows bsdtar.
                exec $tar -a -cf $stage.zip -C $dist $distName >@stdout 2>@stderr
            } else {
                set old [pwd]
                try {
                    cd $dist
                    file delete -force $stage.zip
                    exec zip -qr $stage.zip $distName >@stdout 2>@stderr
                } finally {cd $old}
            }
        }
        dist-clean {
            file delete -force $stage $stage.tar.gz $stage.zip
        }
        clean {
            # Remove only generated outputs, retaining sources and manual.css.
            foreach name $runtimeFiles {file delete -force [file join $out $name]}
            foreach name {sphinx _sources .doctrees} {file delete -force [file join $docs $name]}
            foreach name $docFiles {file delete -force [file join $docs $name]}
            foreach path [glob -nocomplain -directory [file join $docs _static] *] {
                if {[file tail $path] ne {manual.css}} {file delete -force $path}
            }
            RemoveEmpty $out
        }
        default {error "unknown build target: $target"}
    }
}

if {[file normalize [info script]] eq [file normalize $::argv0]} {
    if {[catch {::rfutilBuild::Main {*}$::argv} message options]} {
        puts stderr $message
        exit 1
    }
}
