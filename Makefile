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

sidplayer-driver.bin: sidplay-driver.asm $(DEPS)
	zcc +embedded -v -m --list -subtype=none --no-crt sidplay-driver-map.asm sidplay-driver.asm -o sidplayer-driver -create-app  -Cz"+glue --clean --pad"

rc2014: sidplayer-driver.bin sidplay-rc2014.c sidplay-z88dk.asm $(DEPS)
	zcc +rc2014 -subtype=basic -v -m --list -SO2 --max-allocs-per-node100000 sidplay-rc2014.c sidplay-rc2014.asm -o sidplay-rc2014 -create-app
	#zcc +test -v -m --list -SO2 sidplay-rc2014.c sidplay-rc2014.asm -o sidplay-rc2014 -create-app

clean:
	rm -f *.dsk *.map *.bin *.ihx *.lis
