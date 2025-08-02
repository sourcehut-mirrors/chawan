<!-- MANON
% MANCHA 1
MANOFF -->

# NAME

mancha - view manual pages via cha(1)

# SYNOPSIS

**mancha** \[**-M ***path*\] \[*section*\] *name*\
**mancha** \[**-M ***path*\] \[*section*\] -k *keyword*\
**mancha** -l *file*

# DESCRIPTION

**mancha** enables viewing man pages using the Chawan browser.  It is
analogous to the **w3mman**(1) utility.

**mancha** will call **cha**(1) with the appropriate *man:*, *man-k:* or
*man-l:* URLs.  The protocol adapter then opens the man page and injects
markup into it, e.g. man page references are converted into *man:*
links.

# OPTIONS

Command line options are:

**-M ***path*

: Set *path* as the MANPATH environment variable.  See **man**(1) for
  details of how this is interpreted.

**-k ***keyword*

: Use *keyword* for keyword-based man page search.

**-l ***file*

: Open the specified local *file* as a man page.

# ENVIRONMENT

Following environment variables are used:

**MANCHA_CHA**

: If set, the contents of the variable are used instead of *cha*.
  (Note that the *cha* command is called through **system**(3), so you
  do not have to override it so long as *cha* is found in your
  **PATH**.)

**MANCHA_MAN**

: If set, the contents of the variable are used instead of
  */usr/bin/man*.

**MANCHA_APROPOS**

: If set, the contents of the variable are used instead of
  */usr/bin/man*.

  (This is not a typo; normally (except on FreeBSD), **mancha** assumes
  that **man**(1) is compatible with **apropos**(1) and accepts the *-s*
  parameter.  Overriding **MANCHA_MAN** therefore also overrides the
  command used for **man-k**, so long as **MANCHA_APROPOS** is not set.)

# SEE ALSO

**man**(1), **cha**(1), **cha-localcgi**(5), **w3mman**(1)
