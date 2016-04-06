Webcam Viewer
=============

This is a simple tool for viewing multiple HTTP Webcam streams
simultaneously. Licensed under the MIT license.

![screenshot](https://cloud.githubusercontent.com/assets/1159374/14331146/a2935a3a-fc4c-11e5-9996-1b119b80815d.png)

Compiling
---------

You need OCaml 4.01.0 and the following OCaml libraries, all easily acquired with opam:

* batteries
* cairo2
* curl
* lablgtk2
* pcre
* toml
* ctypes

In addition you need libturbojpeg and FFmpeg development headers and
libraries installed. Tested with Debian Unstable's libturbojpeg1-dev
1.3 and FFmpeg 2.8.6.

	apt-get install libturbojpeg1-dev libavcodec-dev libavformat-dev libswscale-dev libavutil-dev

The following command should bring the OCaml dependencies if you have opam installed:

	opam install lablgtk ocurl pcre-ocaml batteries cairo2 toml ctypes

Then compiling is done by:

	ocamlbuild webcamViewer.native

And install it:

	install webcamViewer.native ~/bin/webcamviewer

You can also run tests (for the FFmpeg bindings):

	ocamlbuild ffmpegTests.native && ./ffmpegTests.native

Setting up
----------

The configuration is written to ~/.webcamviewer in the traditional Windows format:

	[general]
	output="/mnt/data/cameras"
	
	[cam1]
	url="http://admin:admin@foscam1/videostream.cgi"
	
	[cam2]
	url="http://admin:admin@foscam2/videostream.cgi"
