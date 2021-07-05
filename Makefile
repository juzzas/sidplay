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
	zcc +rc2014 -subtype=basic -SO3 --max-allocs-per-node=200000 $(NAME)-rc2014.asm -o $(NAME)-rc2014 -create-app

clean:
	rm -f $(NAME).dsk $(NAME).map $(NAME)-rc2014*.bin $(NAME)-rc2014*.ihx
