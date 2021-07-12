NAME=sidplay
DEPS=
UNAME := $(shell uname -s)

.PHONY: clean

$(NAME).dsk: $(NAME).asm $(DEPS)
	pyz80.py -I samdos2 --mapfile=$(NAME).map $(NAME).asm

run: $(NAME).dsk
ifeq ($(UNAME),Darwin)
	open $(NAME).dsk
else
	xdg-open $(NAME).dsk
endif

net: $(NAME).dsk
	samdisk $(NAME).dsk sam:

rc2014: sidplay-rc2014.c sidplay-z88dk.asm $(DEPS)
	zcc +rc2014 -subtype=basic -SO2 --max-allocs-per-node100000 sidplay-rc2014.c sidplay-z88dk.asm -o sidplay-rc2014 -create-app

rc2014_concept: sidplay-concept.asm $(DEPS)
#	z88dk-z80asm -v -b -m sidplay-concept.asm
	zcc +embedded -v -m --list -subtype=none --no-crt sidplay-concept-map.asm sidplay-concept.asm -o rc2014-concept -create-app  -Cz"+glue --ihex --clean --pad"

clean:
	rm -f *.dsk *.map *.bin *.ihx *.lis
