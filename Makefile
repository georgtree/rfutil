# Standalone Tcl package; no compiled package components or Tk dependency.
SHELL = /bin/sh
CYGPATH = cygpath -m
native = $(shell $(CYGPATH) "$(1)")
srcdir = .
prefix = /c/tcltk/9.1-ucrt64
exec_prefix = ${prefix}
libdir = ${exec_prefix}/lib
datarootdir = ${prefix}/share
datadir = ${datarootdir}
mandir = ${datarootdir}/man
PACKAGE_NAME = rfutil
PACKAGE_VERSION = 0.2
TCLSH_PROG = /c/tcltk/9.1-ucrt64/bin/tclsh91.exe
TCLLIBPATH ?= C:/msys64/ucrt64/local/lib C:/msys64/ucrt64/lib
TCLSH = TCLLIBPATH="$(TCLLIBPATH)" "$(TCLSH_PROG)"
INSTALL = $(SHELL) $(srcdir)/tclconfig/install-sh -c
INSTALL_DATA = ${INSTALL} -m 644
INSTALL_DATA_DIR = ${INSTALL} -d -m 755
DESTDIR =
pkglibdir = $(libdir)/$(PACKAGE_NAME)$(PACKAGE_VERSION)
pkgdocdir = $(datadir)/$(PACKAGE_NAME)$(PACKAGE_VERSION)/doc
DOC_DIR = $(CURDIR)/docs
DOC_PYTHON = python
DIST_ROOT = $(CURDIR)/dist
DIST_NAME = $(PACKAGE_NAME)-$(PACKAGE_VERSION)
DIST_DIR = $(DIST_ROOT)/$(DIST_NAME)
PKG_FILES = rfutil.tcl pkgIndex.tcl LICENSE
DOC_FILES = index.html rfutil.html rfutil-rfutil.html genindex.html search.html \
    objects.inv searchindex.js .buildinfo .nojekyll rfutil.n rfutil-rfutil.n
DIST_FILES = README.md CHANGELOG.md VALIDATION.md LICENSE configure configure.ac \
    aclocal.m4 Makefile.in pkgIndex.tcl rfutil.tcl test examples tclconfig

all:
	@echo "rfutil is a pure Tcl package; ready to use."

test:
	$(TCLSH) "$(call native,$(srcdir)/test/all.tcl)" $(TESTFLAGS)

test-vector:
	RFUTIL_REQUIRE_RBC=1 $(TCLSH) "$(call native,$(srcdir)/test/all.tcl)" $(TESTFLAGS)

doc:
	RFUTIL_DOC_DIR="$(call native,$(DOC_DIR))" DOC_PYTHON="$(DOC_PYTHON)" $(TCLSH) "$(call native,$(srcdir)/docs/doc_gen.tcl)" $(DOCFLAGS)

install: install-libraries install-doc
install-libraries:
	@echo "Installing library files in $(DESTDIR)$(pkglibdir)"
	@$(INSTALL_DATA_DIR) "$(DESTDIR)$(pkglibdir)"
	@set -e; for file in $(PKG_FILES); do \
	    echo "Installing $(srcdir)/$$file"; \
	    $(INSTALL_DATA) "$(srcdir)/$$file" "$(DESTDIR)$(pkglibdir)/$$file"; \
	done

install-doc:
	@if test -f "$(DOC_DIR)/index.html"; then \
	    set -e; $(INSTALL_DATA_DIR) "$(DESTDIR)$(pkgdocdir)" "$(DESTDIR)$(mandir)/mann"; \
	    echo "Installing html documentation in $(DESTDIR)$(pkgdocdir)"; \
	    for file in $(DOC_FILES); do \
	        if test -f "$(DOC_DIR)/$$file"; then \
	            echo "Installing $(DOC_DIR)/$$file"; \
	            $(INSTALL_DATA) "$(DOC_DIR)/$$file" "$(DESTDIR)$(pkgdocdir)/$$file"; \
	        fi; \
	    done; \
	    for dir in _static _sources; do \
	        if test -d "$(DOC_DIR)/$$dir"; then \
	            $(INSTALL_DATA_DIR) "$(DESTDIR)$(pkgdocdir)/$$dir"; \
	            echo "Installing $(DOC_DIR)/$$dir"; \
	            cp -R "$(DOC_DIR)/$$dir/." "$(DESTDIR)$(pkgdocdir)/$$dir/"; \
	        fi; \
	    done; \
	    echo "Installing manual pages in $(DESTDIR)$(mandir)/mann"; \
	    for file in rfutil.n rfutil-rfutil.n; do \
	        echo "Installing $(DOC_DIR)/$$file"; \
	        $(INSTALL_DATA) "$(DOC_DIR)/$$file" "$(DESTDIR)$(mandir)/mann/$$file"; \
	    done; \
	else \
	    echo "Documentation not generated; run make doc to install the manual."; \
	fi

uninstall: uninstall-libraries uninstall-doc
uninstall-libraries:
	@set -e; for file in $(PKG_FILES); do rm -f "$(DESTDIR)$(pkglibdir)/$$file"; done
	-rmdir "$(DESTDIR)$(pkglibdir)" 2>/dev/null
uninstall-doc:
	@set -e; for file in $(DOC_FILES); do rm -f "$(DESTDIR)$(pkgdocdir)/$$file"; done
	rm -rf "$(DESTDIR)$(pkgdocdir)/_static" "$(DESTDIR)$(pkgdocdir)/_sources"
	rm -f "$(DESTDIR)$(mandir)/mann/rfutil.n" "$(DESTDIR)$(mandir)/mann/rfutil-rfutil.n"
	-rmdir "$(DESTDIR)$(pkgdocdir)" 2>/dev/null

# One staging target is shared by tar and zip, including parallel invocations.
dist-stage:
	rm -rf "$(DIST_DIR)"
	mkdir -p "$(DIST_DIR)/docs/_static"
	@set -e; for file in $(DIST_FILES); do cp -pR "$(srcdir)/$$file" "$(DIST_DIR)/"; done
	cp -p "$(srcdir)/docs/doc_gen.tcl" "$(srcdir)/docs/startPage.ruff" "$(DIST_DIR)/docs/"
	cp -p "$(srcdir)/docs/_static/manual.css" "$(DIST_DIR)/docs/_static/"
	@set -e; for file in $(DOC_FILES); do \
	    test ! -f "$(DOC_DIR)/$$file" || cp -p "$(DOC_DIR)/$$file" "$(DIST_DIR)/docs/"; \
	done; \
	for dir in _static _sources; do \
	    if test -d "$(DOC_DIR)/$$dir"; then \
	        mkdir -p "$(DIST_DIR)/docs/$$dir"; \
	        cp -pR "$(DOC_DIR)/$$dir/." "$(DIST_DIR)/docs/$$dir/"; \
	    fi; \
	done

dist: dist-stage
	cd "$(DIST_ROOT)" && tar -czf "$(DIST_NAME).tar.gz" "$(DIST_NAME)"
dist-zip: dist-stage
	rm -f "$(DIST_ROOT)/$(DIST_NAME).zip"
	cd "$(DIST_ROOT)" && zip -qr "$(DIST_NAME).zip" "$(DIST_NAME)"

clean:
	rm -rf "$(DOC_DIR)/sphinx" "$(DOC_DIR)/_sources" "$(DOC_DIR)/.doctrees"
	@set -e; for file in $(DOC_FILES); do rm -f "$(DOC_DIR)/$$file"; done
	@set -e; for file in "$(DOC_DIR)/_static/"*; do \
	    test "$$file" = "$(DOC_DIR)/_static/manual.css" || rm -rf "$$file"; \
	done

dist-clean:
	rm -rf "$(DIST_DIR)" "$(DIST_ROOT)/$(DIST_NAME).tar.gz" "$(DIST_ROOT)/$(DIST_NAME).zip"
distclean: clean
	rm -f Makefile config.log config.status config.cache

.PHONY: all test test-vector doc install install-libraries install-doc uninstall \
    uninstall-libraries uninstall-doc dist-stage dist dist-zip clean distclean dist-clean
