package require ruff
set docSource [file dirname [file normalize [info script]]]
set root [file dirname $docSource]
lappend auto_path $root
package require rfutil 0.2
source [file join $docSource startPage.ruff]
set out $docSource
if {[info exists ::env(RFUTIL_DOC_DIR)]} {
    set out [file normalize $::env(RFUTIL_DOC_DIR)]
}

file mkdir [file join $out _static]
set css [file join $docSource _static manual.css]
if {$out ne $docSource} {
    file copy -force $css [file join $out _static manual.css]
}
set common [list -title {RF network parameter utilities} -preamble $startPage -product rfutil\
                    -version [package provide rfutil] -copyright {George Yashin} -pagesplit namespace\
                    -recurse false -includeprivate false -excludeprocs {^(?:[A-Z]|compLen$)}\
                    -includesource false -autopunctuate true {*}$argv]

ruff::document ::rfutil -format sphinx -outdir [file join $out sphinx] -outfile rfutil.rst {*}$common
ruff::document ::rfutil -format nroff -outdir $out -outfile rfutil.n {*}$common

set f [open [file join $out sphinx conf.py] a]
puts $f {
extensions = list(dict.fromkeys(globals().get("extensions", []) + ["sphinx_rtd_theme", "sphinx.ext.githubpages", "sphinx.ext.mathjax"]))
html_theme = "sphinx_rtd_theme"
html_theme_options = {"collapse_navigation": False, "navigation_depth": 4}
html_static_path = []
html_css_files = list(globals().get("html_css_files", [])) + ["manual.css"]
}
close $f

set python python
if {[info exists ::env(DOC_PYTHON)]} {
    set python $::env(DOC_PYTHON)
}
exec -- $python -m sphinx -E -a -b html [file join $out sphinx] $out >@stdout 2>@stderr
