#!/bin/bash -norc
dnl	This file is an input file used by the GNU "autoconf" program to
dnl	generate the file "configure", which is run during Tcl installation
dnl	to configure the system for the local environment.

AC_INIT([rfutil],[0.2])
TEA_INIT()
AC_CONFIG_AUX_DIR(tclconfig)
TEA_PATH_TCLCONFIG
TEA_LOAD_TCLCONFIG
dnl Honour an explicit --prefix for this architecture-independent package.
TEA_PREFIX
AS_IF([test "x$exec_prefix_default" = xyes], [exec_prefix='${prefix}'])
TEA_ADD_SOURCES([])
TEA_ADD_HEADERS([])
TEA_ADD_INCLUDES([])
TEA_ADD_LIBS([])
TEA_ADD_CFLAGS([])
TEA_ADD_STUB_SOURCES([])
TEA_ADD_TCL_SOURCES([rfutil.tcl])
TEA_PROG_TCLSH
AC_SUBST(TCLLIBPATH)
AC_CONFIG_FILES([Makefile])
AC_OUTPUT
