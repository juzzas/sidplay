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

rc2014: $(NAME)-rc2014.asm $(DEPS)
	zcc +rc2014 -subtype=basic $(NAME)-rc2014.asm 

clean:
	rm -f $(NAME).dsk $(NAME).map
