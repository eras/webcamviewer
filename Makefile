TARGET=webcamViewer.otarget
OCAMLBUILD=ocamlbuild -use-ocamlfind

.PHONY: $(TARGET)

$(TARGET):
	$(OCAMLBUILD) $(TARGET)

clean:
	$(OCAMLBUILD) -clean
