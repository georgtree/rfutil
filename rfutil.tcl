###Abstract
# This file implements functions for work with 2-port S-parameters data.
# Version: 0.2

package require math::complexnumbers
package require math::constants
package require argparse 0.65

package provide rfutil 0.2

namespace eval ::rfutil {
    variable _ruff_preamble {
        # RF network parameter utilities
        `rfutil` calculates two-port S, Z, Y and scattering-transfer parameters, equivalent T/pi circuit elements,
        matrix products and inverses, and fixture de-embedding. It also calculates complex magnitude and phase.

        ## Requirements
        List operation requires Tcl 8.6 or Tcl 9, Tcllib (`math::complexnumbers`, `math::constants`), and argparse 0.58
        or later. Vector operation additionally requires Tcl 9 and `rbc::vector` 0.8.5 or later. Use a current RBC build
        including complex vectors and `vector expr -name`. No Tk initialization, display or Cairo is required.

        ## Representations and defaults
        A matrix is a dictionary with keys `11`, `12`, `21` and `22`. Each component contains a frequency sweep, not a
        single matrix element. In list mode, each value is a list of complex `{real imag}` pairs. In vector mode, each
        value is an RBC vector name. Complex and real parameter vectors are accepted; matrix outputs are complex.
        Frequency vectors must be real. Equivalent capacitance/inductance, magnitude and phase outputs are real.

        Every numeric input of a call follows `-input`, including its frequency argument. The optional `z0` remains
        a single `{real imag}` scalar in both modes. Mixed list/vector components within one call are not supported.
        This explicit convention matches `tclinterp` and avoids guessing whether a one-element list is a vector name.

        ```tcl
        package require rfutil 0.2
        set s [dict create 11 {{0.1 0.2}} 12 {{0.02 0.01}} 21 {{0.8 -0.1}} 22 {{0.2 0.1}}]
        set z [rfutil::s2z $s]

        # Convert the result into named complex vectors.
        set zv [rfutil::s2z $s -output vector -namespace ::network::z -names {11 z11 12 z12 21 z21 22 z22}]
        # Calculate a whole sweep using RBC expressions, returning lists.
        set sAgain [rfutil::z2s $zv -input vector -output list]
        ```

        The options are independent: list/list uses the Tcllib backend; vector/list and vector/vector use whole-sweep
        RBC expressions; list/vector uses the scalar backend and converts its final results. Keep data in vectors
        across successive transformations to avoid repeated list conversion.

        `rfutil::configure` supports all-settings queries, single-option queries, and atomic updates:

        ```tcl
        set saved [rfutil::configure]
        rfutil::configure -input vector -output vector -ifexists replace
        rfutil::configure -output
        rfutil::configure {*}$saved
        ```

        Defaults are `-input list`, `-output list` and `-ifexists error`. Per-call options override them. Selecting
        vector defaults checks that RBC can be loaded. Ordinary list calls and list-default queries do not load RBC.

        ## Naming and ownership
        Input names resolve in the caller's namespace, then through Tcl command resolution. Literal vector names with
        parentheses are supported. Inputs are borrowed, never destroyed or modified by calculations unless explicitly
        chosen as replacement destinations. Read-only inputs and nonzero index offsets are accepted.

        For vector output:

        - `-namespace` selects the output namespace, relative to the caller, creating missing parents. An empty name is
          an error.
        - `-names` maps result fields to exact vector names. Matrix fields are `11`, `12`, `21`, `22`;
          equivalent-circuit fields are `z1/z2/z3`, `y1/y2/y3`, `c1/c2/c3` or `l1/l2/l3`.
        - `mag` and `angle` accept `-name` for their sole output, or the `result` field of `-names`, but not both.
        - Omitted destinations use RBC's `#auto` mechanism. A final `#auto` component is also supported explicitly.
        - Fully-qualified destinations override `-namespace`; their parent namespace must already exist.
        - `-ifexists error` rejects existing commands. `replace` reuses writable RBC vectors of the required numeric
          type, preserving their identity. It never replaces arbitrary Tcl commands.

        Unknown fields, duplicate destinations, read-only outputs and type mismatches are rejected before output writes.
        Calculations complete before publishing, so destinations may alias inputs. Internal vectors are cleaned up on
        success and error; returned vectors belong to the caller and must be destroyed when no longer needed.
        Callbacks triggered by replacing vectors can have their own side effects; multiple destination updates are not
        a transaction against arbitrary user callbacks. Namespaces created for output are not removed on failure.

        ```tcl
        set magnitude [rfutil::mag [dict get $zv 11] -input vector -output vector -name ::network::magnitude]
        rbc::vector destroy {*}[dict values $zv] $magnitude
        ```

        ## Numerical scope
        All input components and participating matrices must have equal lengths, including any frequency input. The
        caller must ensure that sample frequencies correspond; the package does not interpolate or store a frequency
        grid. Empty sweeps return empty components. The vector backend rejects exactly zero conversion denominators,
        determinants and required frequency/reactance divisors before publishing results. Nearly singular data can
        still amplify numerical errors; no automatic regularisation is performed.

        The conversion formulas and transfer-matrix convention are retained from the original package. In particular,
        S-to-T divides by S21 and T-to-S divides by T22. This is a scattering-transfer matrix, not an ABCD matrix.
        The scalar reference impedance is common to both ports. The default reference impedance is `{50.0 0.0}`.

        ## Build, test and documentation

        ```sh
        ./configure --with-tcl=/path/to/tcl/lib --prefix=/your/prefix
        make
        make test
        make test-vector
        make doc
        make install
        ```

        `make test` runs the original tests and extensions, skipping RBC-specific tests if RBC is unavailable.
        `make test-vector` requires RBC and fails if it cannot load it. `TESTFLAGS` is forwarded to tcltest, for example
        `make test TESTFLAGS='-match vector.s2z.*'`. A failing test or test-file error causes a nonzero exit status.
        Use `TCLLIBPATH` to supply dependencies not installed in the selected interpreter's search path.

        Documentation is generated from these Ruff sources and public procedure comments, first to Sphinx/RTD HTML and
        also to nroff. Install Ruff, Tcllib and Python packages `sphinx` and `sphinx_rtd_theme`; select Python with
        `make doc DOC_PYTHON=/path/to/python`. Generated HTML is in `docs/index.html`; the manual page is
        `docs/rfutil.n`. Out-of-source builds put generated documentation in their own `docs` directory.

        `make install` supports `DESTDIR`; documentation is installed if already generated. `make uninstall` removes the
        installed package files and generated manual. `make clean` removes generated docs while retaining Ruff sources
        and the maintained stylesheet. `make dist` and `make dist-zip` produce complete source archives, including the
        pre-generated configure script, tests and documentation sources. Neither archive bundles external dependencies.
    }

    namespace import ::math::complexnumbers::*
    namespace export s2z s2t t2s s2y z2s y2s z2y y2z zTEq cxxTEq lxxTEq yPEq cxxPEq lxxPEq inv2x2 matMul2x2 deemb mag\
            angle 
    ::math::constants::constants radtodeg degtorad pi
    variable defaults {-input list -output list -ifexists error}
    variable serial 0

    # Static metadata shared by argument parsing and both calculation backends.
    variable operations {
        s2z {
            signature   {sxx z0}
            fields      {11 21 12 22}
            description {Converts 2-port s-parameters to z-parameters.}
        }
        s2t {
            signature   {sxx}
            fields      {11 21 12 22}
            description {Converts 2-port s-parameters to transfer parameters.}
        }
        t2s {
            signature   {txx}
            fields      {11 21 12 22}
            description {Converts 2-port transfer parameters to s-parameters.}
        }
        s2y {
            signature   {sxx z0}
            fields      {11 21 12 22}
            description {Converts 2-port s-parameters to y-parameters.}
        }
        z2s {
            signature   {zxx z0}
            fields      {11 21 12 22}
            description {Converts 2-port z-parameters to s-parameters.}
        }
        y2s {
            signature   {yxx z0}
            fields      {11 21 12 22}
            description {Converts 2-port y-parameters to s-parameters.}
        }
        z2y {
            signature   {zxx}
            fields      {11 21 12 22}
            description {Converts 2-port z-parameters to y-parameters.}
        }
        y2z {
            signature   {yxx}
            fields      {11 21 12 22}
            description {Converts 2-port y-parameters to z-parameters.}
        }
        zTEq {
            signature   {zxx}
            fields      {z1 z2 z3}
            description {Calculates equivalent T circuit elements values.}
        }
        cxxTEq {
            signature   {freq zxx}
            fields      {c1 c2 c3}
            description {Calculates capacitive part equivalent T circuit elements values.}
        }
        lxxTEq {
            signature   {freq zxx}
            fields      {l1 l2 l3}
            description {Calculates inductive part equivalent T circuit elements values.}
        }
        yPEq {
            signature   {yxx}
            fields      {y1 y2 y3}
            description {Calculates equivalent P circuit elements values.}
        }
        cxxPEq {
            signature   {freq yxx}
            fields      {c1 c2 c3}
            description {Calculates capacitive part equivalent P circuit elements values.}
        }
        lxxPEq {
            signature   {freq yxx}
            fields      {l1 l2 l3}
            description {Calculates inductive part equivalent P circuit elements values.}
        }
        inv2x2 {
            signature   {mat}
            fields      {11 21 12 22}
            description {Calculates inverse matrix of input matrix with size 2x2.}
        }
        matMul2x2 {
            signature   {mat1 mat2}
            fields      {11 21 12 22}
            description {Calculates multiply matrices with 2x2 size.}
        }
        deemb {
            signature   {sMeas sFixtL sFixtR}
            fields      {11 21 12 22}
            description {Procedure for deembedding of DUT from test fixture.}
        }
        mag {
            signature   {data}
            fields      {result}
            description {Calculates magnitude of complex number.}
        }
        angle {
            signature   {data}
            fields      {result}
            description {Calculates angle (phase) of complex number.}
        }
    }
}

### Public commands
proc ::rfutil::configure {args} {
    # Queries or changes interpreter-local defaults atomically.
    #  -input mode - list or vector; initially list.
    #  -output mode - list or vector; initially list.
    #  -ifexists policy - error or replace; initially error.
    # Returns: all defaults, or the value of a single queried option.
    # Synopsis: ?option?
    # Synopsis: ?-input list|vector? ?-output list|vector? ?-ifexists error|replace?
    variable defaults
    set arguments [argparse -inline -help {Query or change interpreter-local defaults atomically. With no arguments,\
                                                   returns all settings. With one bare option, returns its value.} {
        {-input? -enum {list vector} -help {Default input representation: list or vector}}
        {-output? -enum {list vector} -help {Default output representation: list or vector}}
        {-ifexists? -enum {error replace} -help {Default collision policy: error or replace}}
    }]
    if {[dict size $arguments] == 0} {
        return $defaults
    }
    set next $defaults
    dict for {key value} $arguments {
        if {$value eq {}} {
            if {[llength $args] != 1} {
                return -code error "-$key requires an argument"
            }
            return [dict get $defaults -$key]
        }
        dict set next -$key [lindex $value 1]
    }
    if {([dict get $next -input] eq {vector}) || ([dict get $next -output] eq {vector})} {
        RequireRbc
    }
    set defaults $next
}

proc ::rfutil::s2z {args} {
    # Converts 2-port s-parameters to z-parameters.
    #  sxx - Dictionary that contains 2-port matrix of s-parameters,
    #   each matrix element is the list of values at different
    #   frequencies (or other parameter) in form of `{real imag}`.
    #   The form of dictionary is: `{11 list 12 list 21 list 22 list}`
    #  z0 - Reference impedance in form of `{real imag}`, default is `{50 0}`, optional
    #  -input list|vector - Input format; defaults to `::rfutil::configure -input`.
    #  -output list|vector - Output format; defaults to `::rfutil::configure -output`.
    #  -namespace name - Output namespace, created if missing; relative to the caller.
    #  -names dictionary - Result field to destination name mapping. Missing fields use `#auto`.
    #  -ifexists error|replace - Collision policy. Replacement requires a writable vector of the same type.
    #
    # Vector names resolve in the caller's namespace. Vector options require Tcl 9 and rbc::vector.
    # Inputs are borrowed; output vectors are owned by the caller. See the package guide for naming and ownership.
    #
    # Synopsis: sxx ?z0? ?-input list|vector? ?-output list|vector? ?-ifexists error|replace? ?-namespace name?
    # ?-names dictionary?
    # Returns: dictionary of the same form as input dictionary with z-parameters. With vector output, dictionary values
    # are RBC vector names instead of lists.
    return [Dispatch s2z [uplevel 1 {namespace current}] [Parse s2z $args]]
}

proc ::rfutil::s2t {args} {
    # Converts 2-port s-parameters to transfer parameters.
    #  sxx - Dictionary that contains 2-port matrix of s-parameters,
    #   each matrix element is the list of values at different
    #   frequencies (or other parameter) in form of `{real imag}`.
    #   The form of dictionary is: `{11 list 12 list 21 list 22 list}`
    #  -input list|vector - Input format; defaults to `::rfutil::configure -input`.
    #  -output list|vector - Output format; defaults to `::rfutil::configure -output`.
    #  -namespace name - Output namespace, created if missing; relative to the caller.
    #  -names dictionary - Result field to destination name mapping. Missing fields use `#auto`.
    #  -ifexists error|replace - Collision policy. Replacement requires a writable vector of the same type.
    #
    # Vector names resolve in the caller's namespace. Vector options require Tcl 9 and rbc::vector.
    # Inputs are borrowed; output vectors are owned by the caller. See the package guide for naming and ownership.
    #
    # Synopsis: sxx ?-input list|vector? ?-output list|vector? ?-ifexists error|replace? ?-namespace name?
    # ?-names dictionary?
    # Returns: dictionary of the same form as input dictionary with transfer parameters. With vector output, dictionary
    # values are RBC vector names instead of lists.
    return [Dispatch s2t [uplevel 1 {namespace current}] [Parse s2t $args]]
}

proc ::rfutil::t2s {args} {
    # Converts 2-port transfer parameters to s-parameters.
    #  txx - Dictionary that contains 2-port matrix of transfer parameters,
    #   each matrix element is the list of values at different
    #   frequencies (or other parameter) in form of `{real imag}`.
    #   The form of dictionary is: `{11 list 12 list 21 list 22 list}`
    #  -input list|vector - Input format; defaults to `::rfutil::configure -input`.
    #  -output list|vector - Output format; defaults to `::rfutil::configure -output`.
    #  -namespace name - Output namespace, created if missing; relative to the caller.
    #  -names dictionary - Result field to destination name mapping. Missing fields use `#auto`.
    #  -ifexists error|replace - Collision policy. Replacement requires a writable vector of the same type.
    #
    # Vector names resolve in the caller's namespace. Vector options require Tcl 9 and rbc::vector.
    # Inputs are borrowed; output vectors are owned by the caller. See the package guide for naming and ownership.
    #
    # Synopsis: txx ?-input list|vector? ?-output list|vector? ?-ifexists error|replace? ?-namespace name?
    # ?-names dictionary?
    # Returns: dictionary of the same form as input dictionary with s-parameters. With vector output, dictionary values
    # are RBC vector names instead of lists.
    return [Dispatch t2s [uplevel 1 {namespace current}] [Parse t2s $args]]
}

proc ::rfutil::s2y {args} {
    # Converts 2-port s-parameters to y-parameters.
    #  sxx - Dictionary that contains 2-port matrix of s-parameters,
    #   each matrix element is the list of values at different
    #   frequencies (or other parameter) in form of `{real imag}`.
    #   The form of dictionary is: `{11 list 12 list 21 list 22 list}`
    #  z0 - Reference impedance in form of `{real imag}`, default is `{50 0}`, optional
    #  -input list|vector - Input format; defaults to `::rfutil::configure -input`.
    #  -output list|vector - Output format; defaults to `::rfutil::configure -output`.
    #  -namespace name - Output namespace, created if missing; relative to the caller.
    #  -names dictionary - Result field to destination name mapping. Missing fields use `#auto`.
    #  -ifexists error|replace - Collision policy. Replacement requires a writable vector of the same type.
    #
    # Vector names resolve in the caller's namespace. Vector options require Tcl 9 and rbc::vector.
    # Inputs are borrowed; output vectors are owned by the caller. See the package guide for naming and ownership.
    #
    # Synopsis: sxx ?z0? ?-input list|vector? ?-output list|vector? ?-ifexists error|replace? ?-namespace name?
    # ?-names dictionary?
    # Returns: dictionary of the same form as input dictionary with y-parameters. With vector output, dictionary values
    # are RBC vector names instead of lists.
    return [Dispatch s2y [uplevel 1 {namespace current}] [Parse s2y $args]]
}

proc ::rfutil::z2s {args} {
    # Converts 2-port z-parameters to s-parameters.
    #  zxx - Dictionary that contains 2-port matrix of z-parameters,
    #   each matrix element is the list of values at different
    #   frequencies (or other parameter) in form of `{real imag}`.
    #   The form of dictionary is: `{11 list 12 list 21 list 22 list}`
    #  z0 - Reference impedance in form of `{real imag}`, default is `{50 0}`, optional
    #  -input list|vector - Input format; defaults to `::rfutil::configure -input`.
    #  -output list|vector - Output format; defaults to `::rfutil::configure -output`.
    #  -namespace name - Output namespace, created if missing; relative to the caller.
    #  -names dictionary - Result field to destination name mapping. Missing fields use `#auto`.
    #  -ifexists error|replace - Collision policy. Replacement requires a writable vector of the same type.
    #
    # Vector names resolve in the caller's namespace. Vector options require Tcl 9 and rbc::vector.
    # Inputs are borrowed; output vectors are owned by the caller. See the package guide for naming and ownership.
    #
    # Synopsis: zxx ?z0? ?-input list|vector? ?-output list|vector? ?-ifexists error|replace? ?-namespace name?
    # ?-names dictionary?
    # Returns: dictionary of the same form as input dictionary with s-parameters. With vector output, dictionary values
    # are RBC vector names instead of lists.
    return [Dispatch z2s [uplevel 1 {namespace current}] [Parse z2s $args]]
}

proc ::rfutil::y2s {args} {
    # Converts 2-port y-parameters to s-parameters.
    #  yxx - Dictionary that contains 2-port matrix of y-parameters,
    #   each matrix element is the list of values at different
    #   frequencies (or other parameter) in form of `{real imag}`.
    #   The form of dictionary is: `{11 list 12 list 21 list 22 list}`
    #  z0 - Reference impedance in form of `{real imag}`, default is `{50 0}`, optional
    #  -input list|vector - Input format; defaults to `::rfutil::configure -input`.
    #  -output list|vector - Output format; defaults to `::rfutil::configure -output`.
    #  -namespace name - Output namespace, created if missing; relative to the caller.
    #  -names dictionary - Result field to destination name mapping. Missing fields use `#auto`.
    #  -ifexists error|replace - Collision policy. Replacement requires a writable vector of the same type.
    #
    # Vector names resolve in the caller's namespace. Vector options require Tcl 9 and rbc::vector.
    # Inputs are borrowed; output vectors are owned by the caller. See the package guide for naming and ownership.
    #
    # Synopsis: yxx ?z0? ?-input list|vector? ?-output list|vector? ?-ifexists error|replace? ?-namespace name?
    # ?-names dictionary?
    # Returns: dictionary of the same form as input dictionary with s-parameters. With vector output, dictionary values
    # are RBC vector names instead of lists.
    return [Dispatch y2s [uplevel 1 {namespace current}] [Parse y2s $args]]
}

proc ::rfutil::z2y {args} {
    # Converts 2-port z-parameters to y-parameters.
    #  zxx - Dictionary that contains 2-port matrix of z-parameters,
    #   each matrix element is the list of values at different
    #   frequencies (or other parameter) in form of `{real imag}`.
    #   The form of dictionary is: `{11 list 12 list 21 list 22 list}`
    #  -input list|vector - Input format; defaults to `::rfutil::configure -input`.
    #  -output list|vector - Output format; defaults to `::rfutil::configure -output`.
    #  -namespace name - Output namespace, created if missing; relative to the caller.
    #  -names dictionary - Result field to destination name mapping. Missing fields use `#auto`.
    #  -ifexists error|replace - Collision policy. Replacement requires a writable vector of the same type.
    #
    # Vector names resolve in the caller's namespace. Vector options require Tcl 9 and rbc::vector.
    # Inputs are borrowed; output vectors are owned by the caller. See the package guide for naming and ownership.
    #
    # Synopsis: zxx ?-input list|vector? ?-output list|vector? ?-ifexists error|replace? ?-namespace name?
    # ?-names dictionary?
    # Returns: dictionary of the same form as input dictionary with y-parameters. With vector output, dictionary values
    # are RBC vector names instead of lists.
    return [Dispatch z2y [uplevel 1 {namespace current}] [Parse z2y $args]]
}

proc ::rfutil::y2z {args} {
    # Converts 2-port y-parameters to z-parameters.
    #  yxx - Dictionary that contains 2-port matrix of y-parameters,
    #   each matrix element is the list of values at different
    #   frequencies (or other parameter) in form of `{real imag}`.
    #   The form of dictionary is: `{11 list 12 list 21 list 22 list}`
    #  -input list|vector - Input format; defaults to `::rfutil::configure -input`.
    #  -output list|vector - Output format; defaults to `::rfutil::configure -output`.
    #  -namespace name - Output namespace, created if missing; relative to the caller.
    #  -names dictionary - Result field to destination name mapping. Missing fields use `#auto`.
    #  -ifexists error|replace - Collision policy. Replacement requires a writable vector of the same type.
    #
    # Vector names resolve in the caller's namespace. Vector options require Tcl 9 and rbc::vector.
    # Inputs are borrowed; output vectors are owned by the caller. See the package guide for naming and ownership.
    #
    # Synopsis: yxx ?-input list|vector? ?-output list|vector? ?-ifexists error|replace? ?-namespace name?
    # ?-names dictionary?
    # Returns: dictionary of the same form as input dictionary with z-parameters. With vector output, dictionary values
    # are RBC vector names instead of lists.
    return [Dispatch y2z [uplevel 1 {namespace current}] [Parse y2z $args]]
}

proc ::rfutil::zTEq {args} {
    # Calculates equivalent T circuit elements values.
    #  zxx - Dictionary that contains 2-port matrix of z-parameters,
    #   each matrix element is the list of values at different
    #   frequencies (or other parameter) in form of `{real imag}`.
    #   The form of dictionary is: `{11 list 12 list 21 list 22 list}`
    #  -input list|vector - Input format; defaults to `::rfutil::configure -input`.
    #  -output list|vector - Output format; defaults to `::rfutil::configure -output`.
    #  -namespace name - Output namespace, created if missing; relative to the caller.
    #  -names dictionary - Result field to destination name mapping. Missing fields use `#auto`.
    #  -ifexists error|replace - Collision policy. Replacement requires a writable vector of the same type.
    #
    #               Z1            Z2                                         
    #              ___           ___                                        
    #         o---|___|----o----|___|---o                                   
    #         .            |            .                                   
    #         .           .-.           .                                   
    #      P1 .           | |           . P2                                
    #         .         Z3| |           .                                   
    #         .           '-'           .                                  
    #        \./           |           \./                                  
    #         o----------- o -----------o   
    #
    # Vector names resolve in the caller's namespace. Vector options require Tcl 9 and rbc::vector.
    # Inputs are borrowed; output vectors are owned by the caller. See the package guide for naming and ownership.
    #
    # Synopsis: zxx ?-input list|vector? ?-output list|vector? ?-ifexists error|replace? ?-namespace name?
    # ?-names dictionary?
    # Returns: dictionary of the form `{z1 list z2 list z3 list}` with impedances of equivalent elements. With vector
    # output, dictionary values are RBC vector names instead of lists.
    return [Dispatch zTEq [uplevel 1 {namespace current}] [Parse zTEq $args]]
}

proc ::rfutil::cxxTEq {args} {
    # Calculates capacitive part equivalent T circuit elements values.
    #  freq - Frequency values list
    #  zxx - Dictionary that contains 2-port matrix of z-parameters,
    #   each matrix element is the list of values at different
    #   frequencies (or other parameter) in form of `{real imag}`.
    #   The form of dictionary is: `{11 list 12 list 21 list 22 list}`
    #  -input list|vector - Input format; defaults to `::rfutil::configure -input`.
    #  -output list|vector - Output format; defaults to `::rfutil::configure -output`.
    #  -namespace name - Output namespace, created if missing; relative to the caller.
    #  -names dictionary - Result field to destination name mapping. Missing fields use `#auto`.
    #  -ifexists error|replace - Collision policy. Replacement requires a writable vector of the same type.
    #
    #             C1           C2            
    #              | |           | |         
    #         o----| |-----o-----| |----o    
    #         .    | |     |     | |    .    
    #         .            |            .    
    #      P1 .         C3---           . P2 
    #         .           ---           .    
    #        \./           |           \./   
    #         .            |            .    
    #         o----------- o -----------o 
    #
    # Vector names resolve in the caller's namespace. Vector options require Tcl 9 and rbc::vector.
    # Inputs are borrowed; output vectors are owned by the caller. See the package guide for naming and ownership.
    #
    # Synopsis: freq zxx ?-input list|vector? ?-output list|vector? ?-ifexists error|replace? ?-namespace name?
    # ?-names dictionary?
    # Returns: dictionary of the form `{c1 list c2 list c3 list}` with capacitive part of equivalent elements impedance.
    # With vector output, dictionary values are RBC vector names instead of lists.
    return [Dispatch cxxTEq [uplevel 1 {namespace current}] [Parse cxxTEq $args]]
}

proc ::rfutil::lxxTEq {args} {
    # Calculates inductive part equivalent T circuit elements values.
    #  freq - Frequency values list
    #  zxx - Dictionary that contains 2-port matrix of z-parameters,
    #   each matrix element is the list of values at different
    #   frequencies (or other parameter) in form of `{real imag}`.
    #   The form of dictionary is: `{11 list 12 list 21 list 22 list}`
    #  -input list|vector - Input format; defaults to `::rfutil::configure -input`.
    #  -output list|vector - Output format; defaults to `::rfutil::configure -output`.
    #  -namespace name - Output namespace, created if missing; relative to the caller.
    #  -names dictionary - Result field to destination name mapping. Missing fields use `#auto`.
    #  -ifexists error|replace - Collision policy. Replacement requires a writable vector of the same type.
    #
    #             L1            L2          
    #              ___           ___        
    #         o----UUU-----o-----UUU----o   
    #         .            |            .   
    #         .         L3 C|           .   
    #      P1 .            C|           . P2
    #         .            C|           .   
    #        \./           |           \./  
    #         .            |            .   
    #         o----------- o -----------o   
    #
    # Vector names resolve in the caller's namespace. Vector options require Tcl 9 and rbc::vector.
    # Inputs are borrowed; output vectors are owned by the caller. See the package guide for naming and ownership.
    #
    # Synopsis: freq zxx ?-input list|vector? ?-output list|vector? ?-ifexists error|replace? ?-namespace name?
    # ?-names dictionary?
    # Returns: dictionary of the form `{l1 list l2 list l3 list}` with inductive part of equivalent elements impedance.
    # With vector output, dictionary values are RBC vector names instead of lists.
    return [Dispatch lxxTEq [uplevel 1 {namespace current}] [Parse lxxTEq $args]]
}

proc ::rfutil::yPEq {args} {
    # Calculates equivalent P circuit elements values.
    #  yxx - Dictionary that contains 2-port matrix of y-parameters,
    #   each matrix element is the list of values at different
    #   frequencies (or other parameter) in form of `{real imag}`.
    #   The form of dictionary is: `{11 list 12 list 21 list 22 list}`
    #  -input list|vector - Input format; defaults to `::rfutil::configure -input`.
    #  -output list|vector - Output format; defaults to `::rfutil::configure -output`.
    #  -namespace name - Output namespace, created if missing; relative to the caller.
    #  -names dictionary - Result field to destination name mapping. Missing fields use `#auto`.
    #  -ifexists error|replace - Collision policy. Replacement requires a writable vector of the same type.
    #
    #                      Y3
    #                      ___                                               
    #          o-----o----|___|----o-----o                                   
    #          .     |             |     .                                   
    #          .    .-.           .-.    .                                   
    #       P1 .    | |           | |    . P2                                
    #          .  Y1| |         Y2| |    .                                   
    #          .    '-'           '-'    .                                  
    #         \./    |             |    \./                                   
    #          o-----o-------------o-----o       
    #
    # Vector names resolve in the caller's namespace. Vector options require Tcl 9 and rbc::vector.
    # Inputs are borrowed; output vectors are owned by the caller. See the package guide for naming and ownership.
    #
    # Synopsis: yxx ?-input list|vector? ?-output list|vector? ?-ifexists error|replace? ?-namespace name?
    # ?-names dictionary?
    # Returns: dictionary of the form `{y1 list y2 list y3 list}` with impedances of equivalent elements. With vector
    # output, dictionary values are RBC vector names instead of lists.
    return [Dispatch yPEq [uplevel 1 {namespace current}] [Parse yPEq $args]]
}

proc ::rfutil::cxxPEq {args} {
    # Calculates capacitive part equivalent P circuit elements values.
    #  freq - Frequency values list
    #  yxx - Dictionary that contains 2-port matrix of y-parameters,
    #   each matrix element is the list of values at different
    #   frequencies (or other parameter) in form of `{real imag}`.
    #   The form of dictionary is: `{11 list 12 list 21 list 22 list}`
    #  -input list|vector - Input format; defaults to `::rfutil::configure -input`.
    #  -output list|vector - Output format; defaults to `::rfutil::configure -output`.
    #  -namespace name - Output namespace, created if missing; relative to the caller.
    #  -names dictionary - Result field to destination name mapping. Missing fields use `#auto`.
    #  -ifexists error|replace - Collision policy. Replacement requires a writable vector of the same type.
    #
    #                     C3                  
    #                      | |                
    #          o-----o-----| |-----o-----o    
    #          .     |     | |     |     .    
    #          .     |             |     .    
    #       P1 .  C1---         C2---    . P2 
    #          .    ---           ---    .    
    #         \./    |             |    \./   
    #          .     |             |     .    
    #          o-----o-------------o-----o    
    #
    # Vector names resolve in the caller's namespace. Vector options require Tcl 9 and rbc::vector.
    # Inputs are borrowed; output vectors are owned by the caller. See the package guide for naming and ownership.
    #
    # Synopsis: freq yxx ?-input list|vector? ?-output list|vector? ?-ifexists error|replace? ?-namespace name?
    # ?-names dictionary?
    # Returns: dictionary of the form `{c1 list c2 list c3 list}` with capacitive part of equivalent elements
    # admittance. With vector output, dictionary values are RBC vector names instead of lists.
    return [Dispatch cxxPEq [uplevel 1 {namespace current}] [Parse cxxPEq $args]]
}

proc ::rfutil::lxxPEq {args} {
    # Calculates inductive part equivalent P circuit elements values.
    #  freq - Frequency values list
    #  yxx - Dictionary that contains 2-port matrix of y-parameters,
    #   each matrix element is the list of values at different
    #   frequencies (or other parameter) in form of `{real imag}`.
    #   The form of dictionary is: `{11 list 12 list 21 list 22 list}`
    #  -input list|vector - Input format; defaults to `::rfutil::configure -input`.
    #  -output list|vector - Output format; defaults to `::rfutil::configure -output`.
    #  -namespace name - Output namespace, created if missing; relative to the caller.
    #  -names dictionary - Result field to destination name mapping. Missing fields use `#auto`.
    #  -ifexists error|replace - Collision policy. Replacement requires a writable vector of the same type.
    #
    #                       L3                 
    #                       ___                
    #           o-----o-----UUU-----o-----o    
    #           .     |             |     .    
    #           .  L1 C|         L2 C|    .    
    #        P1 .     C|            C|    . P2 
    #           .     C|            C|    .    
    #          \./    |             |    \./   
    #           .     |             |     .    
    #           o-----o-------------o-----o      
    #
    # Vector names resolve in the caller's namespace. Vector options require Tcl 9 and rbc::vector.
    # Inputs are borrowed; output vectors are owned by the caller. See the package guide for naming and ownership.
    #
    # Synopsis: freq yxx ?-input list|vector? ?-output list|vector? ?-ifexists error|replace? ?-namespace name?
    # ?-names dictionary?
    # Returns: dictionary of the form `{l1 list l2 list l3 list}` with inductive part of equivalent elements impedance.
    # With vector output, dictionary values are RBC vector names instead of lists.
    return [Dispatch lxxPEq [uplevel 1 {namespace current}] [Parse lxxPEq $args]]
}

proc ::rfutil::inv2x2 {args} {
    # Calculates inverse matrix of input matrix with size 2x2.
    #  mat - Dictionary that contains 2-port matrix,
    #   each matrix element is the list of values at different
    #   frequencies (or other parameter) in form of `{real imag}`.
    #   The form of dictionary is: `{11 list 12 list 21 list 22 list}`
    #  -input list|vector - Input format; defaults to `::rfutil::configure -input`.
    #  -output list|vector - Output format; defaults to `::rfutil::configure -output`.
    #  -namespace name - Output namespace, created if missing; relative to the caller.
    #  -names dictionary - Result field to destination name mapping. Missing fields use `#auto`.
    #  -ifexists error|replace - Collision policy. Replacement requires a writable vector of the same type.
    #
    # Vector names resolve in the caller's namespace. Vector options require Tcl 9 and rbc::vector.
    # Inputs are borrowed; output vectors are owned by the caller. See the package guide for naming and ownership.
    #
    # Synopsis: mat ?-input list|vector? ?-output list|vector? ?-ifexists error|replace? ?-namespace name?
    # ?-names dictionary?
    # Returns: dictionary of the same form as input dictionary with resulted matrix. With vector output, dictionary
    # values are RBC vector names instead of lists.
    return [Dispatch inv2x2 [uplevel 1 {namespace current}] [Parse inv2x2 $args]]
}

proc ::rfutil::matMul2x2 {args} {
    # Calculates multiply matrices with 2x2 size.
    #  mat1 - First matrix in dictionary form {11 list 12 list 21 list 22 list}
    #  mat2 - Second matrix in dictionary form {11 list 12 list 21 list 22 list}
    #  -input list|vector - Input format; defaults to `::rfutil::configure -input`.
    #  -output list|vector - Output format; defaults to `::rfutil::configure -output`.
    #  -namespace name - Output namespace, created if missing; relative to the caller.
    #  -names dictionary - Result field to destination name mapping. Missing fields use `#auto`.
    #  -ifexists error|replace - Collision policy. Replacement requires a writable vector of the same type.
    #
    # Vector names resolve in the caller's namespace. Vector options require Tcl 9 and rbc::vector.
    # Inputs are borrowed; output vectors are owned by the caller. See the package guide for naming and ownership.
    #
    # Synopsis: mat1 mat2 ?-input list|vector? ?-output list|vector? ?-ifexists error|replace? ?-namespace name?
    # ?-names dictionary?
    # Returns: dictionary of the same form as input dictionaries with resulted matrix. With vector output, dictionary
    # values are RBC vector names instead of lists.
    return [Dispatch matMul2x2 [uplevel 1 {namespace current}] [Parse matMul2x2 $args]]
}

proc ::rfutil::deemb {args} {
    # Procedure for deembedding of DUT from test fixture.
    #  sMeas - Measured s-parameters matrix in dictionary form `{11 list 12 list 21 list 22 list}`
    #  sFixtL - s-parameters matrix of left fixture in dictionary form `{11 list 12 list 21 list 22 list}`
    #  sFixtR - s-parameters matrix of right fixture in dictionary form `{11 list 12 list 21 list 22 list}`
    #  -input list|vector - Input format; defaults to `::rfutil::configure -input`.
    #  -output list|vector - Output format; defaults to `::rfutil::configure -output`.
    #  -namespace name - Output namespace, created if missing; relative to the caller.
    #  -names dictionary - Result field to destination name mapping. Missing fields use `#auto`.
    #  -ifexists error|replace - Collision policy. Replacement requires a writable vector of the same type.
    #
    #```
    #    ┌      ┐   ┌        ┐-1   ┌       ┐     ┌        ┐-1
    #    │ Tdut │ = │ Tfixtl │  x  │ Tmeas │  x  │ Tfixtr │
    #    └      ┘   └        ┘     └       ┘     └        ┘
    #```
    #
    # Vector names resolve in the caller's namespace. Vector options require Tcl 9 and rbc::vector.
    # Inputs are borrowed; output vectors are owned by the caller. See the package guide for naming and ownership.
    #
    # Synopsis: sMeas sFixtL sFixtR ?-input list|vector? ?-output list|vector? ?-ifexists error|replace? ?-namespace
    # name? ?-names dictionary?
    # Returns: dictionary of the same form as input dictionaries with deembedded DUT s-matrix. With vector output,
    # dictionary values are RBC vector names instead of lists.
    return [Dispatch deemb [uplevel 1 {namespace current}] [Parse deemb $args]]
}

proc ::rfutil::mag {args} {
    # Calculates magnitude of complex number.
    # data - List with complex data in form `{real imag}`
    # -db - Option to select output magnitude in db scale
    # -input list|vector - Input format; defaults to `::rfutil::configure -input`.
    # -output list|vector - Output format; defaults to `::rfutil::configure -output`.
    # -namespace name - Output namespace, created if missing; relative to the caller.
    # -names dictionary - Result field to destination name mapping. Missing fields use `#auto`.
    # -name name - Single destination; conflicts with the result entry of `-names`.
    # -ifexists error|replace - Collision policy. Replacement requires a writable vector of the same type.
    #
    # Vector names resolve in the caller's namespace. Vector options require Tcl 9 and rbc::vector.
    # Inputs are borrowed; output vectors are owned by the caller. See the package guide for naming and ownership.
    #
    # Synopsis: data ?-db? ?-input list|vector? ?-output list|vector? ?-ifexists error|replace? ?-namespace name?
    # ?-name name?
    # Synopsis: data ?-db? ?-input list|vector? ?-output list|vector? ?-ifexists error|replace? ?-namespace name?
    # ?-names dictionary?
    # Returns: list of magnitudes. With vector output, returns a real RBC vector name.
    return [Dispatch mag [uplevel 1 {namespace current}] [Parse mag $args]]
}

proc ::rfutil::angle {args} {
    # Calculates angle (phase) of complex number.
    # data - List with complex data in form `{real imag}`
    # -deg - Option to select angle in degrees units
    # -input list|vector - Input format; defaults to `::rfutil::configure -input`.
    # -output list|vector - Output format; defaults to `::rfutil::configure -output`.
    # -namespace name - Output namespace, created if missing; relative to the caller.
    # -names dictionary - Result field to destination name mapping. Missing fields use `#auto`.
    # -name name - Single destination; conflicts with the result entry of `-names`.
    # -ifexists error|replace - Collision policy. Replacement requires a writable vector of the same type.
    #
    # Vector names resolve in the caller's namespace. Vector options require Tcl 9 and rbc::vector.
    # Inputs are borrowed; output vectors are owned by the caller. See the package guide for naming and ownership.
    #
    # Synopsis: data ?-deg? ?-input list|vector? ?-output list|vector? ?-ifexists error|replace? ?-namespace name?
    # ?-name name?
    # Synopsis: data ?-deg? ?-input list|vector? ?-output list|vector? ?-ifexists error|replace? ?-namespace name?
    # ?-names dictionary?
    # Returns: list of angles. With vector output, returns a real RBC vector name.
    return [Dispatch angle [uplevel 1 {namespace current}] [Parse angle $args]]
}

### Common argument and output handling
proc ::rfutil::Parse {op arguments} {
    # Parses a public calculation's positional arguments and shared options.
    # op - Public calculation name registered in the operations dictionary.
    # arguments - Raw Tcl argument list supplied to the public command.
    #
    # Builds the operation-specific positional and boolean definitions together with the common representation and
    # destination options. Omitted representation and collision defaults are applied later by Dispatch.
    # The helper must be called directly by the public wrapper: -help prints argparse help and returns through
    # three levels, leaving argparse, this helper and the wrapper without performing a calculation.
    #
    # Returns: Dictionary of parsed argument names and values, without leading option hyphens.
    variable operations
    set args $arguments
    set spec [list]
    foreach name [dict get $operations $op signature] {
        switch -- $name {
            z0 {
                lappend spec {z0 -optional -default {50.0 0.0} -help {Common reference impedance as {real imag}}}
            }
            freq {
                lappend spec {freq -help {Frequency list or real RBC vector, as selected by -input}}
            }
            data {
                lappend spec {data -help {Complex-pair list or RBC vector, as selected by -input}}
            }
            default {
                lappend spec [list $name -help {Two-port dictionary with keys 11, 12, 21 and 22; component lists or RBC\
                                                        vector names as selected by -input}]
            }
        }
    }
    if {$op eq {mag}} {
        lappend spec {-db -boolean -help {Return magnitude in decibels}}
    }
    if {$op eq {angle}} {
        lappend spec {-deg -boolean -help {Return phase in degrees}}
    }
    lappend spec {-input= -enum {list vector} -help {Input representation; uses the package default}}\
            {-output= -enum {list vector} -help {Output representation; uses the package default}}\
            {-namespace= -help {Output namespace, relative to the caller; requires vector output}}\
            {-name= -help {Destination for mag or angle; omit or use #auto for automatic naming}}\
            {-names= -type dict -help {Dictionary of result fields and destination vector names}}\
            {-ifexists= -enum {error replace} -help {Existing destination policy; uses the package default}}
    return [argparse -inline -mixed -helplevel 3 -help [dict get $operations $op description] $spec]
}

proc ::rfutil::RequireRbc {} {
    # Loads the optional Tcl-only RBC vector dependency.
    #
    # Requires Tcl 9 and rbc::vector 0.8.5 or later. Package initialization runs when needed; subsequent calls reuse
    # the loaded package. This helper does not request Tk or create vectors.
    #
    # Returns: Version string supplied by package require rbc::vector.
    package require Tcl 9.0-
    package require rbc::vector 0.8.5
}

proc ::rfutil::Qualify {ns name} {
    # Combines a namespace and a relative command name.
    # ns - Fully-qualified base namespace, including :: for the global namespace.
    # name - Relative or fully-qualified name, possibly ending in #auto.
    #
    # Fully-qualified names are returned unchanged. This is a string operation: it does not resolve commands,
    # normalise namespace separators, create namespaces or check whether the result exists.
    #
    # Returns: Fully-qualified name formed from the supplied strings.
    if {[string match ::* $name]} {
        return $name
    }
    if {$ns eq {::}} {
        return ::$name
    }
    return ${ns}::$name
}

proc ::rfutil::ResolveVector {caller name} {
    # Resolves an input command name and verifies that it names a registered RBC vector.
    # caller - Existing namespace of the public command's caller.
    # name - Input vector name, relative to caller or fully qualified.
    #
    # Uses Tcl command resolution in caller, then checks the resolved name against RBC's vector registry.
    # The returned vector is borrowed; its values, protection state and lifetime are unchanged.
    # RBC must already be loaded.
    #
    # Returns: Fully-qualified registered vector command name.
    set command [namespace eval $caller [list namespace which -command $name]]
    if {($command eq {}) || ($command ni [::rbc::vector names])} {
        return -code error "not an RBC vector: $name"
    }
    return $command
}

proc ::rfutil::Dispatch {op caller options} {
    # Validates a parsed request, runs its backend and publishes the requested representation.
    # op - Public calculation name.
    # caller - Fully-qualified namespace of the original caller, captured by the public wrapper.
    # options - Parsed argument dictionary from Parse; representation defaults may be absent.
    #
    # Applies interpreter-local defaults, checks destination option combinations and validates lengths across all
    # inputs. Vector inputs are resolved in caller; frequency vectors must be real. List input selects ListCalculate,
    # while vector input selects VectorCalculate. List results can subsequently be published as vectors.
    #
    # Creates a private work namespace and removes its temporary vectors and namespace in a finally block.
    # Inputs are borrowed. Output vectors belong to the caller and may intentionally replace input vectors under
    # -ifexists replace. Output namespace creation and callback side effects are not rolled back.
    #
    # Returns: Result dictionary, or the single list/vector result for mag and angle.
    variable operations
    variable defaults
    variable serial
    foreach {key value} $defaults {
        set key [string range $key 1 end]
        if {![dict exists $options $key]} {
            dict set options $key $value
        }
    }
    set input [dict get $options input]
    set output [dict get $options output]
    set fields [dict get $operations $op fields]
    if {$output eq {list}} {
        foreach key {namespace name names} {
            if {[dict exists $options $key]} {
                return -code error "-$key requires -output vector"
            }
        }
    }
    if {[dict exists $options name] && ($op ni {mag angle})} {
        return -code error {-name is only valid for mag and angle; use -names for dictionary results}
    }
    if {[dict exists $options names]} {
        dict for {key name} [dict get $options names] {
            if {$key ni $fields} {
                return -code error "unknown output field: $key"
            }
        }
    }
    if {[dict exists $options name] && [dict exists $options names result]} {
        return -code error {do not combine -name with the result entry of -names}
    }
    if {($input eq {vector}) || ($output eq {vector})} {
        RequireRbc
    }
    # Validate all input lengths together, including between separate matrices.
    set count -1
    foreach arg [dict get $operations $op signature] {
        if {$arg eq {z0}} {
            continue
        }
        set value [dict get $options $arg]
        if {$arg in {freq data}} {
            set components [dict create $arg $value]
        } else {
            if {$input eq {list}} {
                if {[dict exists $options freq]} {
                    compLen [dict merge [dict create freq [dict get $options freq]] $value]
                } else {
                    compLen $value
                }
            }
            set components {}
            foreach key {11 21 12 22} {
                dict set components $key [dict get $value $key]
            }
        }
        dict for {key values} $components {
            if {$input eq {vector}} {
                set values [ResolveVector $caller $values]
                if {($arg eq {freq}) && ([$values type] ne {real})} {
                    return -code error {frequency vector must be real}
                }
                set length [$values length]
            } else {
                set length [llength $values]
            }
            if {($count >= 0) && ($count != $length)} {
                return -code error "input lengths differ at $arg/$key"
            }
            set count $length
            dict set components $key $values
        }
        if {$arg in {freq data}} {
            dict set options $arg [dict get $components $arg]
        } else {
            dict set options $arg $components
        }
    }
    # Private safe names also support public vector names containing parentheses.
    set work ::rfutil::work[incr serial]
    namespace eval $work {}
    try {
        if {$input eq {vector}} {
            set result [VectorCalculate $op $options $work]
        } else {
            set result [ListCalculate $op $options]
        }
        if {$output eq {vector}} {
            set result [Publish $result $input $caller $options $work]
        } elseif {$input eq {vector}} {
            dict for {key vector} $result {dict set result $key [$vector range 0 end]}
        }
        if {$op in {mag angle}} {
            return [dict get $result result]
        }
        return $result
    } finally {
        if {[llength [info commands ::rbc::vector]]} {
            foreach v [::rbc::vector names ${work}::*] {
                ::rbc::vector destroy $v
            }
        }
        namespace delete $work
    }
}

proc ::rfutil::Publish {result input caller options work} {
    # Copies completed calculation results into caller-owned RBC vectors.
    # result - Dictionary mapping result fields to lists or private result vectors.
    # input - Backend representation of result values: list or vector.
    # caller - Fully-qualified namespace used for relative output names by default.
    # options - Validated options containing ifexists and any namespace, name or names settings.
    # work - Existing private namespace for temporary list-to-vector conversions.
    #
    # RBC must be loaded. List components become complex vectors for matrix and impedance/admittance fields,
    # and real vectors for other fields. Vector components retain their numeric type. Missing destination names
    # use #auto. An explicit output namespace is created; other destination parents must already exist.
    #
    # Prepares all values and checks collisions, duplicate destinations, types and read-only state before writing
    # outputs. Replacement uses dup to preserve existing vector identity. Newly created output vectors are destroyed
    # if publication fails; already replaced vectors and arbitrary callback side effects are not rolled back.
    # Temporary vectors in work are cleaned up by Dispatch, not by this helper.
    #
    # Returns: Dictionary mapping every result field to its fully-qualified output vector name.
    set ns $caller
    if {[dict exists $options namespace]} {
        set ns [dict get $options namespace]
        if {$ns eq {}} {
            return -code error {empty output namespace}
        }
        set ns [Qualify $caller $ns]
        namespace eval $ns {}
    }
    set targets {}
    set used {}
    set prepared {}
    set created {}
    # Prepare all values and check every destination before modifying any destination.
    dict for {key value} $result {
        if {$input eq {list}} {
            set type [expr {$key in {11 12 21 22 z1 z2 z3 y1 y2 y3} ? {complex} : {real}}]
            set vector [::rbc::vector create ${work}::out$key -type $type -variable {}]
            $vector set $value
        } else {
            set vector $value
            set type [$vector type]
        }
        dict set prepared $key $vector
        set name #auto
        if {[dict exists $options names $key]} {
            set name [dict get $options names $key]
        }
        if {$key eq {result} && [dict exists $options name]} {
            set name [dict get $options name]
        }
        if {$name eq {}} {
            return -code error {empty output vector name}
        }
        set name [Qualify $ns $name]
        set parent [namespace qualifiers $name]
        if {$parent eq {}} {
            set parent ::
        }
        if {![namespace exists $parent]} {
            return -code error "output parent namespace does not exist: $parent"
        }
        # Canonicalise redundant namespace separators before duplicate checks.
        set parent [namespace eval $parent {namespace current}]
        set name [Qualify $parent [namespace tail $name]]
        if {[namespace tail $name] ne {#auto}} {
            if {$name in $used} {
                return -code error "duplicate destination: $name"
            }
            lappend used $name
            set command [namespace which -command $name]
            if {$command ne {}} {
                if {$command ni [::rbc::vector names]} {
                    return -code error "destination is not an RBC vector: $name"
                }
                if {[dict get $options ifexists] eq {error}} {
                    return -code error "destination already exists: $name"
                }
                if {[$command readonly]} {
                    return -code error "destination is read-only: $name"
                }
                if {[$command type] ne $type} {
                    return -code error "destination type mismatch: $name"
                }
            }
        }
        dict set targets $key $name
    }
    try {
        dict for {key name} $targets {
            set source [dict get $prepared $key]
            if {([namespace tail $name] eq {#auto}) || ([namespace which -command $name] eq {})} {
                set name [::rbc::vector create $name -type [$source type] -variable {}]
                lappend created $name
            }
            $source dup $name
            dict set targets $key $name
        }
    } on error {message details} {
        foreach v $created {
            catch {::rbc::vector destroy $v}
        }
        return -options $details $message
    }
    return $targets
}

### List calculations
proc ::rfutil::compLen {dict} {
    # Checks that all list-valued entries in a dictionary have equal lengths.
    # dict - Dictionary of component lists; entries are compared in dictionary iteration order.
    #
    # Empty and single-entry dictionaries pass. Values are inspected only as lists; numeric contents and required
    # matrix keys are not checked. The helper does not modify the dictionary.
    #
    # Returns: Empty string when lengths agree.
    set keys [dict keys $dict]
    set values [dict values $dict]
    set size [dict size $dict]
    for {set i 0} {$i<$size-1} {incr i} {
        set keyA [lindex $keys $i]
        set keyB [lindex $keys [expr {$i+1}]]
        set lenA [llength [lindex $values $i]]
        set lenB [llength [lindex $values [expr {$i+1}]]]
        if {$lenA!=$lenB} {
            return -code error "Length of $keyA '$lenA' is not equal to length of $keyB '$lenB'"
        }
    }
    return
}



proc ::rfutil::ListCalculate {op options} {
    # Calculates an entire RF sweep using Tcllib complex arithmetic.
    # op - Supported public calculation name, already validated by the dispatch layer.
    # options - Parsed inputs with aligned component lists, scalar z0 when needed, and db/deg flags when applicable.
    #
    # Dispatch validates input lengths. Unpacks component lists once, evaluates each sample through the operation
    # switch and collects the result fields. Inputs are unchanged and RBC is not required. De-embedding recursively
    # composes transfer conversion, inversion and multiplication, following the vector backend's routing.
    #
    # Preserves the scalar formulas and their arithmetic order, including the explicit singular-matrix error for
    # inv2x2. Tcllib arithmetic errors propagate to the caller. Publish handles any requested vector output.
    #
    # Returns: Dictionary of result fields and lists; mag and angle use the field result. Empty sweeps retain all
    # fields.
    variable operations
    variable pi
    variable radtodeg
    if {$op eq {deemb}} {
        foreach {field label} {sMeas m sFixtL l sFixtR r} {
            set t [ListCalculate s2t [dict create sxx [dict get $options $field]]]
            if {$label ne {m}} {
                set t [ListCalculate inv2x2 [dict create mat $t]]
            }
            set $label $t
        }
        set lm [ListCalculate matMul2x2 [dict create mat1 $l mat2 $m]]
        set lmr [ListCalculate matMul2x2 [dict create mat1 $lm mat2 $r]]
        return [ListCalculate t2s [dict create txx $lmr]]
    }
    set samples {}
    set number 0
    foreach input [dict get $operations $op signature] {
        set value [dict get $options $input]
        if {$input eq {z0}} {
            set z0 $value
        } elseif {$input in {freq data}} {
            dict set samples $input $value
        } else {
            set letters [expr {$number == 0 ? {a c b d} : {e g f h}}]
            foreach key {11 21 12 22} letter $letters {
                dict set samples $letter [dict get $value $key]
            }
            incr number
        }
    }
    set 1c [complex 1 0]
    set 2c [complex 2 0]
    set m1c [complex -1 0]
    set m2c [complex -2 0]
    if {$op in {s2y y2s}} {
        set y0 [pow $z0 $m1c]
    }
    set fields [dict get $operations $op fields]
    set result {}
    foreach key $fields {
        dict set result $key {}
    }
    set count [llength [lindex [dict values $samples] 0]]
    for {set i 0} {$i < $count} {incr i} {
        dict for {name values} $samples {
            set $name [lindex $values $i]
        }
        switch -- $op {
            s2z {
                dict set point 11 [* $z0 [/ [+ [* [+ $1c $a] [- $1c $d]] [* $b $c]]\
                                                  [- [* [- $1c $a] [- $1c $d]] [* $b $c]]]]
                dict set point 12 [* $z0 [/ [* $2c $b] [- [* [- $1c $a] [- $1c $d]] [* $b $c] ]]]
                dict set point 21 [* $z0 [/ [* $2c $c] [- [* [- $1c $a] [- $1c $d]] [* $b $c] ]]]
                dict set point 22 [* $z0 [/ [+ [* [- $1c $a] [+ $1c $d]] [* $b $c]]\
                                                  [- [* [- $1c $a] [- $1c $d]] [* $b $c]]]]
            }
            s2t {
                dict set point 11 [- $b [/ [* $a $d] $c]]
                dict set point 12 [/ $a $c]
                dict set point 21 [* $m1c [/ $d $c]]
                dict set point 22 [/ $1c $c]
            }
            t2s {
                dict set point 11 [/ $b $d]
                dict set point 12 [- $a [/ [* $b $c] $d]]
                dict set point 21 [/ $1c $d]
                dict set point 22 [* $m1c [/ $c $d]]
            }
            s2y {
                dict set point 11 [* $y0 [/ [+ [* [- $1c $a] [+ $1c $d]] [* $b $c]] [- [* [+ $1c $a] [+ $1c $d]]\
                                                                                             [* $b $c]]]]
                dict set point 12 [* $y0 [/ [* $m2c $b] [- [* [+ $1c $a] [+ $1c $d]] [* $b $c] ]]]
                dict set point 21 [* $y0 [/ [* $m2c $c] [- [* [+ $1c $a] [+ $1c $d]] [* $b $c] ]]]
                dict set point 22 [* $y0 [/ [+ [* [+ $1c $a] [- $1c $d]] [* $b $c]] [- [* [+ $1c $a] [+ $1c $d]]\
                                                                                             [* $b $c]]]]
            }
            z2s {
                dict set point 11 [/ [- [* [- $a $z0] [+ $d $z0]] [* $b $c]] [- [* [+ $a $z0] [+ $d $z0]] [* $b $c]]]
                dict set point 12 [/ [* [* $2c $b] $z0] [- [* [+ $a $z0] [+ $d $z0]] [* $b $c]]]
                dict set point 21 [/ [* [* $2c $c] $z0] [- [* [+ $a $z0] [+ $d $z0]] [* $b $c]]]
                dict set point 22 [/ [- [* [+ $a $z0] [- $d $z0]] [* $b $c]] [- [* [+ $a $z0] [+ $d $z0]] [* $b $c]]]
            }
            y2s {
                dict set point 11 [/ [+ [* [- $y0 $a ] [+ $y0 $d]] [* $b $c]] [- [* [+ $y0 $a] [+ $y0 $d]] [* $b $c]]]
                dict set point 12 [/ [* [* $m2c $b] $y0] [- [* [+ $y0 $a] [+ $y0 $d]] [* $b $c]]]
                dict set point 21 [/ [* [* $m2c $c] $y0] [- [* [+ $y0 $a] [+ $y0 $d]] [* $b $c]]]
                dict set point 22 [/ [+ [* [+ $y0 $a ] [- $y0 $d]] [* $b $c]] [- [* [+ $y0 $a] [+ $y0 $d]] [* $b $c]]]
            }
            z2y - y2z {
                dict set point 11 [/ $d [- [* $a $d] [* $b $c]]]
                dict set point 12 [/ [* $b $m1c] [- [* $a $d] [* $b $c]]]
                dict set point 21 [/ [* $c $m1c] [- [* $a $d] [* $b $c]]]
                dict set point 22 [/ $a [- [* $a $d] [* $b $c]]]
            }
            inv2x2 {
                set det [- [* $a $d] [* $b $c]]
                if {([real $det]==0.0) && ([imag $det]==0.0)} {
                    return -code error {Matrix can't be inverted}
                }
                set rec [/ $1c $det]
                dict set point 11 [* $rec $d]
                dict set point 12 [* $rec [* $m1c $b]]
                dict set point 21 [* $rec [* $m1c $c]]
                dict set point 22 [* $rec $a]
            }
            matMul2x2 {
                dict set point 11 [+ [* $a $e] [* $b $g]]
                dict set point 12 [+ [* $a $f] [* $b $h]]
                dict set point 21 [+ [* $c $e] [* $d $g]]
                dict set point 22 [+ [* $c $f] [* $d $h]]
            }
            zTEq -
            yPEq -
            cxxTEq -
            lxxTEq -
            cxxPEq -
            lxxPEq {
                if {[string match *TEq $op]} {
                    set eq [list [- $a $c] [- $d $c] $c]
                } else {
                    set eq [list [+ $a $c] [+ $d $c] [* $m1c $c]]
                }
                foreach value $eq key $fields {
                    if {$op in {cxxTEq lxxPEq}} {
                        set value [expr {-1/(2*$pi*$freq*[imag $value])}]
                    } elseif {$op in {lxxTEq cxxPEq}} {
                        set value [expr {[imag $value]/(2*$pi*$freq)}]
                    }
                    dict set point $key $value
                }
            }
            mag {
                set value [mod $data]
                if {[dict get $options db]} {
                    set value [expr {20*log10($value)}]
                }
                dict set point result $value
            }
            angle {
                set value [arg $data]
                if {[dict get $options deg]} {
                    set value [expr {$radtodeg*$value}]
                }
                dict set point result $value
            }
        }
        foreach key $fields {dict lappend result $key [dict get $point $key]}
    }
    return $result
}

### Vector calculations
# Whole-sweep complex arithmetic. Inputs are copied to private, expression-safe
# names once, so literal public names never become expression syntax.
proc ::rfutil::Eval {work expression} {
    # Evaluates an internal vector expression into a newly allocated temporary vector.
    # work - Existing private namespace in which to create an automatic vector name.
    # expression - Trusted expression template referring to variables in this helper's immediate caller.
    #
    # Substitutes caller variables with subst, disabling its command and backslash substitutions, then delegates
    # the resulting expression to RBC. Templates and substituted names must be suitable for RBC expression syntax.
    # The new vector takes its type from the expression result and is owned by the enclosing work operation.
    # Dispatch ultimately destroys it; this helper does not publish it to the user.
    #
    # Returns: Fully-qualified name of the new temporary vector.
    set expression [uplevel 1 [list subst -nocommands -nobackslashes $expression]]
    return [::rbc::vector expr -name ${work}::#auto $expression]
}

proc ::rfutil::Nonzero {vector what} {
    # Rejects a divisor vector containing an exactly zero sample.
    # vector - Existing real or complex vector with a name safe for internal RBC expressions.
    # what - Description of the divisor used in the diagnostic.
    #
    # An empty vector passes. Complex equality tests both components. This is an exact-zero check, not a
    # near-singularity, finiteness or condition-number test. The vector is borrowed and is not modified.
    #
    # Returns: Empty string when no zero sample is found.
    if {[$vector length] && ([::rbc::vector expr "sum($vector == 0)"] != 0)} {
        return -code error "$what is zero at one or more sample points"
    }
}

proc ::rfutil::VectorCalculate {op options work} {
    # Calculates an entire RF sweep using RBC vector expressions.
    # op - Supported public calculation name, already validated by the dispatch layer.
    # options - Operation inputs with fully-qualified vector names, scalar z0 when needed, and db/deg flags when
    #  applicable.
    # work - Existing private namespace that owns all intermediate and result vectors.
    #
    # RBC must be loaded and inputs must have matching lengths. Copies inputs to private expression-safe names,
    # normalises their offsets and promotes real parameter vectors to complex storage. Frequency vectors remain
    # real. Inputs are borrowed and unchanged, including read-only inputs and vectors with literal parentheses in names.
    #
    # Matrix and impedance/admittance results are complex; capacitance, inductance, magnitude and phase results are
    # real. De-embedding recursively composes transfer conversion, inversion and multiplication in the same workspace.
    # Exact-zero divisors are checked where required. This helper does not choose public output names or destroy
    # its temporaries, even on failure; Dispatch owns workspace cleanup and Publish handles persistent outputs.
    #
    # Returns: Dictionary of result fields and private vector names; mag and angle use the field result.
    variable operations
    if {$op eq {deemb}} {
        foreach {field label} {sMeas m sFixtL l sFixtR r} {
            set t [VectorCalculate s2t [dict create sxx [dict get $options $field]] $work]
            if {$label ne {m}} {
                set t [VectorCalculate inv2x2 [dict create mat $t] $work]
            }
            set $label $t
        }
        set lm [VectorCalculate matMul2x2 [dict create mat1 $l mat2 $m] $work]
        set lmr [VectorCalculate matMul2x2 [dict create mat1 $lm mat2 $r] $work]
        return [VectorCalculate t2s [dict create txx $lmr] $work]
    }
    set number 0
    foreach input [dict get $operations $op signature] {
        set value [dict get $options $input]
        if {$input eq {z0}} {
            set z [::rbc::vector create ${work}::#auto -type complex -variable {}]
            $z set [list $value]
        } elseif {$input in {freq data}} {
            set dest [::rbc::vector create ${work}::#auto -type [$value type] -variable {}]
            $value dup $dest
            $dest offset 0
            set $input $dest
        } else {
            set letters [expr {$number == 0 ? {a c b d} : {e g f h}}]
            foreach key {11 21 12 22} letter $letters {
                set source [dict get $value $key]
                # Parameter matrices use complex output even for real vector input.
                set dest [::rbc::vector create ${work}::#auto -type complex -variable {}]
                if {[$source type] eq {complex}} {
                    $source dup $dest
                } else {
                    set tmp [::rbc::vector create ${work}::#auto -variable {}]
                    $source dup $tmp
                    $tmp offset 0
                    $dest expr $tmp
                }
                $dest offset 0
                set $letter $dest
            }
            incr number
        }
    }
    set result {}
    switch -- $op {
        s2z {
            set den [Eval $work {(1-$a)*(1-$d)-$b*$c}]
            Nonzero $den {S to Z denominator}
            dict set result 11 [Eval $work {$z*((1+$a)*(1-$d)+$b*$c)/$den}]
            dict set result 21 [Eval $work {2*$z*$c/$den}]
            dict set result 12 [Eval $work {2*$z*$b/$den}]
            dict set result 22 [Eval $work {$z*((1-$a)*(1+$d)+$b*$c)/$den}]
        }
        s2y {
            Nonzero $z {reference impedance}
            set den [Eval $work {(1+$a)*(1+$d)-$b*$c}]
            Nonzero $den {S to Y denominator}
            dict set result 11 [Eval $work {((1-$a)*(1+$d)+$b*$c)/($z*$den)}]
            dict set result 21 [Eval $work {-2*$c/($z*$den)}]
            dict set result 12 [Eval $work {-2*$b/($z*$den)}]
            dict set result 22 [Eval $work {((1+$a)*(1-$d)+$b*$c)/($z*$den)}]
        }
        z2s -
        y2s {
            if {$op eq {y2s}} {
                Nonzero $z {reference impedance}
                set z [Eval $work {1/$z}]
            }
            set den [Eval $work {($a+$z)*($d+$z)-$b*$c}]
            Nonzero $den {conversion denominator}
            set sign [expr {$op eq {z2s} ? 1 : -1}]
            dict set result 11 [Eval $work {$sign*(($a-$z)*($d+$z)-$b*$c)/$den}]
            dict set result 21 [Eval $work {$sign*2*$z*$c/$den}]
            dict set result 12 [Eval $work {$sign*2*$z*$b/$den}]
            dict set result 22 [Eval $work {$sign*(($a+$z)*($d-$z)-$b*$c)/$den}]
        }
        s2t {
            Nonzero $c S21
            dict set result 11 [Eval $work {$b-$a*$d/$c}]
            dict set result 21 [Eval $work {-$d/$c}]
            dict set result 12 [Eval $work {$a/$c}]
            dict set result 22 [Eval $work {1/$c}]
        }
        t2s {
            Nonzero $d T22
            dict set result 11 [Eval $work {$b/$d}]
            dict set result 21 [Eval $work {1/$d}]
            dict set result 12 [Eval $work {$a-$b*$c/$d}]
            dict set result 22 [Eval $work {-$c/$d}]
        }
        inv2x2 - z2y - y2z {
            set den [Eval $work {$a*$d-$b*$c}]
            Nonzero $den determinant
            dict set result 11 [Eval $work {$d/$den}]
            dict set result 21 [Eval $work {-$c/$den}]
            dict set result 12 [Eval $work {-$b/$den}]
            dict set result 22 [Eval $work {$a/$den}]
        }
        matMul2x2 {
            dict set result 11 [Eval $work {$a*$e+$b*$g}]
            dict set result 21 [Eval $work {$c*$e+$d*$g}]
            dict set result 12 [Eval $work {$a*$f+$b*$h}]
            dict set result 22 [Eval $work {$c*$f+$d*$h}]
        }
        zTEq -
        yPEq -
        cxxTEq -
        lxxTEq -
        cxxPEq -
        lxxPEq {
            if {[string match *TEq $op]} {
                set eq [list [Eval $work {$a-$c}] [Eval $work {$d-$c}] $c]
                set prefix z
            } else {
                set eq [list [Eval $work {$a+$c}] [Eval $work {$d+$c}] [Eval $work {-$c}]]
                set prefix y
            }
            if {$op in {zTEq yPEq}} {
                foreach v $eq key [dict get $operations $op fields] {dict set result $key $v}
            } else {
                Nonzero $freq frequency
                set w [Eval $work {6.2831853071795864769*$freq}]
                foreach v $eq key [dict get $operations $op fields] {
                    if {$op in {cxxTEq lxxPEq}} {
                        set im [Eval $work {imag($v)}]
                        Nonzero $im {imaginary component}
                        dict set result $key [Eval $work {-1/($w*$im)}]
                    } else {
                        dict set result $key [Eval $work {imag($v)/$w}]
                    }
                }
            }
        }
        mag {
            set v [Eval $work {abs($data)}]
            if {[dict get $options db]} {
                set v [Eval $work {20*log10($v)}]
            }
            dict set result result $v
        }
        angle {
            set v [Eval $work {arg($data)}]
            if {[dict get $options deg]} {
                set v [Eval $work {57.295779513082320877*$v}]
            }
            dict set result result $v
        }
    }
    return $result
}
