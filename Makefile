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

sidplayer-standalone.hex: sidplay-driver.asm $(DEPS)
	zcc +embedded -v -m --list -subtype=none --no-crt sidplay-driver-map.asm sidplay-driver.asm sidplay-standalone-sid.asm -o sidplayer-driver-standalone -create-app  -Cz"+glue --clean --pad --ihex"
	cp -v sidplayer-driver-standalone__.ihx sidplayer-standalone.hex

rc2014-cpm: sidplayer-driver.bin sidplay-rc2014.c $(DEPS)
	zcc +cpm -compiler=sdcc -v -m --list -SO2  --max-allocs-per-node100000 sidplay-rc2014.c sidplay-rc2014.asm -o sidplay -create-app

rc2014-ticks: sidplayer-driver.bin sidplay-rc2014.c bubtb.asm $(DEPS)
	zcc +test -compiler=sdcc -v -m --list -SO2  --max-allocs-per-node100000 sidplay-rc2014.c sidplay-rc2014.asm bubtb.asm -o sidplay-rc2014 -create-app

rc2014-oled: sidplayer-driver.bin sidplay-demo.asm sidplay-driver-ldr.asm sidplay-standalone-sid.asm $(DEPS)
	zcc +rc2014 -subtype=hbios -v -m --list -SO2 --max-allocs-per-node100000 sidplay-demo.asm @oled/liboled.lst sidplay-driver-ldr.asm sidplay-standalone-sid.asm -o sidplay-oled -create-app

sidint: sidint.asm
	zcc +rc2014 -subtype=hbios -v -m --list -SO2 --max-allocs-per-node100000 sidint.asm -o sidint -create-app

clean:
	rm -f *.dsk *.map *.bin *.ihx *.lis
