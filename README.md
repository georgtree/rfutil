# rfutil: RF parameter utilities

[![Tests: Linux, Windows UCRT64 and MSVC](https://img.shields.io/github/actions/workflow/status/georgtree/rfutil/tests.yml?branch=main&label=Tests%3A%20Linux%2C%20Windows%20UCRT64%20and%20MSVC)](https://github.com/georgtree/rfutil/actions/workflows/tests.yml)

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
- Tcllib and argparse 0.70 or later.
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

## Continuous integration and rolling packages

Pushes run the complete list and RBC vector test suite on Linux GCC, Windows UCRT64 and Windows MSVC (x64),
using Tcl 9.1.0 and Tcllib 2.0. Vector support is required: missing RBC or skipped tests fail the jobs.

Each workflow resolves the `latest` releases of [RBC](https://github.com/georgtree/rbc-tk9/releases/tag/latest)
and [argparse](https://github.com/georgtree/argparse/releases/tag/latest) once for all three jobs. Downloads are
verified against their SHA-256 digests. Dependency caches include the release tag target, asset ID and digest;
Tcl runtime caches include the Tcl commit, compiler/toolchain, runner image, installation path and build recipe.
The test and release workflows share these caches. Only the separately selected argparse package is exposed to
Tcl, rather than the argparse copy bundled with RBC.

Run **Actions → Build packages → Run workflow** to test all three platforms and publish their archives and
`SHA256SUMS.txt` to the [rolling release](https://github.com/georgtree/rfutil/releases/tag/latest). Publication
starts only after all three jobs pass. Subsequent successful manual builds replace the `latest` tag and assets.

rfutil itself is pure Tcl: the archive suffix records the toolchain used for testing, not a package binary ABI.
Archives retain the existing source-distribution layout (`rfutil-0.2/`), including tests, GNU/Nmake build files
and the checked-in manual. Tcl, Tcllib, argparse and RBC are installed separately. After extraction, install
using the supplied build files or add the package directory to `auto_path`.

## Native Windows / MSVC

No MSYS2 shell, Autoconf, C compiler invocation or Tcl source tree is needed to build rfutil itself. From an
**x64 Native Tools Command Prompt for Visual Studio 2022**, use a matching MSVC Tcl installation and matching
MSVC dependency archives:

```bat
cd win
set "INSTALLDIR=C:\Tcl91"
set "PATH=%INSTALLDIR%\bin;%PATH%"
set "TCLLIBPATH={C:/deps/argparse/lib/argparse0.70} {C:/deps/rbc/lib/rbc0.8.5} {C:/deps/tcllib/modules}"
nmake /f makefile.vc
nmake /f makefile.vc test
nmake /f makefile.vc test-vector
nmake /f makefile.vc install
nmake /f makefile.vc dist-zip
```

`all` copies the runtime files into `win/build`. `test` permits absent RBC; `test-vector` requires it. Both run
the actual Tcltest runner and propagate failures. Use `TESTFLAGS="-match pattern"` to select tests locally.
`dist` creates a source tar.gz; `dist-zip` creates a ZIP using Windows' own `tar.exe`, regardless of MSYS2 on PATH.
Both include native build support. `dist-clean` removes staging and archives.

Override `TCLDIR` to use a different Tcl installation, or `TCLSH` to select its executable (default:
`$(TCLDIR)\bin\tclsh91.exe`). `INSTALLDIR` controls the install prefix. `LIBDIR`, `DOCDIR` and `MANDIR` override
library, HTML and manpage destinations; `OUT_DIR`, `DOC_DIR`, `DIST_ROOT` and `DIST_NAME` control build output,
documentation and archives. `DESTDIR` stages installation beneath another directory; an absolute destination's
root/drive is removed before prefixing the staging path. Use the same overrides for installation and removal.

`nmake /f makefile.vc uninstall` removes package-owned files. `clean` (also `distclean`) removes generated runtime
copies and documentation, preserving `manual.css`. To regenerate the manual, install Ruff on `TCLLIBPATH` and
Sphinx plus sphinx_rtd_theme for the selected Python interpreter, then run:

```bat
nmake /f makefile.vc doc DOC_PYTHON=python
```

The native targets are implemented in `win/build.tcl`, so no external Nmake rules need to be copied from Tcl.
