Webcam Viewer
=============

This is a simple tool for viewing multiple HTTP Webcam streams
simultaneously. Licensed under the MIT license.

Compiling
---------

You need OCaml 4.01.0 and the following OCaml libraries:

* batteries
* cairo2
* curl
* lablgtk2
* pcre

In addition you need libjpeg development headers (and library)
installed. Tested with Debian Unstable's libjpeg8-dev.

The following command should bring the OCaml dependencies if you have opam installed:

	opam install lablgtk ocurl pcre-ocaml batteries cairo2

Then compiling is done by:

	ocamlbuild -use-ocamlfind webcamViewer.native

And install:

	install webcamViewer.native ~/bin/webcamviewer

Setting up
----------

Put the urls to ~/.webcamviewer. One line per url. For example:

	http://admin:admin@foscam1/videostream.cgi
