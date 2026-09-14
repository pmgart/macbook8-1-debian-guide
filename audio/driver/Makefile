# MacBook8,1 speaker driver: patched snd-hda-codec-cirrus, built out of tree by audio/scripts/build-driver.sh.
KDIR ?= /lib/modules/$(shell uname -r)/build
obj-m := snd-hda-codec-cirrus.o
snd-hda-codec-cirrus-y := patch_cirrus.o

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean
