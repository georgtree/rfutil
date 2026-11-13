package require rfutil 0.2

set s {11 {{0.1 0.2} {0.15 0.1}} 12 {{0.02 0.01} {0.03 0.01}} 21 {{0.8 -0.1} {0.7 -0.2}} 22 {{0.2 0.1} {0.3 0.1}}}
set z [rfutil::s2z $s -output vector -namespace ::example::z -names {11 z11 12 z12 21 z21 22 z22}]
try {
    puts [rfutil::z2s $z -input vector -output list]
    puts [rfutil::mag [dict get $z 11] -input vector]
} finally {
    rbc::vector destroy {*}[dict values $z]
}
