
none:
	@echo Specify target as one of mini, superelf, rc1802

mini: .utility-mini
superelf: .utility-superelf
rc1802: .utility-rc1802

.utility-mini: utility.asm
	@rm -f .utility-*
	asm02 -L -b -D1802MINI utility.asm
	@rm -f utility.build
	@touch .utility-mini

.utility-superelf: utility.asm
	@rm -f .utility-*
	asm02 -L -b -DSUPERELF utility.asm
	@rm -f utility.build
	@touch .utility-superelf

.utility-rc1802: utility.asm
	@rm -f .utility-*
	asm02 -L -b -DRC1802 utility.asm
	@rm -f utility.build
	@touch .utility-rc1802

clean:
	@rm -f utility.bin utility.lst .utility-*
