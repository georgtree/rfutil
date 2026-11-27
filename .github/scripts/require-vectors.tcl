package require Tcl 9.1
package require argparse 0.70
package require rfutil 0.2
package require rbc::vector 0.8.5
set input [rbc::vector create #auto -type complex -variable {}]
try {
    $input set {{3 4} {5 12}}
    set output [::rfutil::mag $input -input vector -output vector]
    try {
        if {[$output range 0 end] ne {5.0 13.0}} {error {Unexpected vector magnitude result}}
    } finally {rbc::vector destroy $output}
} finally {rbc::vector destroy $input}
puts {PASS: rfutil complex vector input and real vector output}
