# rfutil: RF parameter utilities

Standalone two-port RF parameter calculations for Tcl, with optional RBC complex-vector input and output.
Extracted from [tcl_tools](https://github.com/georgtree/tcl_tools); existing list calls remain compatible.

```tcl
package require rfutil 0.2
set s {11 {{0.1 0.2}} 12 {{0.02 0.01}} 21 {{0.8 -0.1}} 22 {{0.2 0.1}}}
set z [rfutil::s2z $s]
set zv [rfutil::s2z $s -output vector -namespace ::network::z]
set recovered [rfutil::z2s $zv -input vector]
rbc::vector destroy {*}[dict values $zv]
```

All runtime implementation is in `rfutil.tcl`. `-input list|vector`, `-output list|vector`, `-namespace`, `-names`, and
`-ifexists error|replace` follow the tclinterp conventions. `mag` and `angle` additionally accept `-name`. Package-wide
defaults are controlled by `rfutil::configure`; defaults remain list/list/error. The Tcl-only RBC package is loaded only
when needed.

## Requirements and installation

- Tcl 8.6 or 9 for lists; Tcl 9 for vectors.
- Tcllib and argparse 0.58 or later.
- Optional: current RBC 0.8.5 or later with complex vectors and `vector expr -name`.
- Documentation: Ruff, Sphinx and sphinx_rtd_theme.

```sh
./configure --with-tcl=/path/to/tcl/lib --prefix=/your/prefix
make
make test
make test-vector                   # requires actual RBC; no display needed
make doc                          # optional
make install
```

On Windows, run configure/make in MSYS2 with your Tcl installation. The package itself is pure Tcl.
You can also add the unpacked directory directly to `auto_path`, without configuring or installing it.
Use `TCLLIBPATH` for dependencies and `TESTFLAGS` for test selection.

`make uninstall`, `make clean`, `make distclean`, `make dist` (source tar.gz) and `make dist-zip` are provided.
Installation honours `DESTDIR`, `--libdir`, `--datadir` and `--mandir`. A generated configure script is included;
Autoconf is only needed after editing configure.ac.

The namespace preamble in `rfutil.tcl` documents representation, naming, ownership and numerical conventions.
Run `make doc` to produce the RTD HTML manual and nroff man page from Ruff sources.

