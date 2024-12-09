
mini: utility.img

clean:
	rm -f loader.lst loader.bin
	rm -f utility.lst utility.bin utility.zx1 utility.img

utility.img: loader.bin utility.zx1
	cat loader.bin utility.zx1 > utility.img

loader.bin: utility.bin loader.asm
	asm02 -L -b loader.asm
	rm -f loader.build

utility.zx1: utility.bin
	zx1 -f utility.bin utility.zx1

utility.bin: utility.asm
	asm02 -L -b utility.asm
	rm -f utility.build

