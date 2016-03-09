Webcam Viewer
=============

This is a simple tool for viewing multiple HTTP Webcam streams
simultaneously. Licensed under the MIT license.

Compiling
---------

You need OCaml 4.01.0 and the following OCaml libraries, all easily acquired with opam:

* batteries
* cairo2
* curl
* lablgtk2
* pcre
* toml

In addition you need libturbojpeg development headers (and library)
installed. Tested with Debian Unstable's libturbojpeg1-dev
1.3...

WebcamViewer now uses FFmpeg for saving video streams while the
TurboJPEG-code hasn't been removed yet, so you will need
libavcodec-dev libavformat-dev libswscale-dev libavutil-dev as well.

	apt-get install libturbojpeg1-dev libavcodec-dev libavformat-dev libswscale-dev libavutil-dev

The following command should bring the OCaml dependencies if you have opam installed:

	opam install lablgtk ocurl pcre-ocaml batteries cairo2 toml

Then compiling is done by:

	ocamlbuild webcamViewer.native

And install:

	install webcamViewer.native ~/bin/webcamviewer

Setting up
----------

The configuration is written to ~/.webcamviewer in the traditional Windows format:

	[general]
	output="/mnt/data/cameras"
	
	[cam1]
	url="http://admin:admin@foscam1/videostream.cgi"
	
	[cam2]
	url="http://admin:admin@foscam2/videostream.cgi"
