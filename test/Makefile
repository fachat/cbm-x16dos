

dosromldr: dosromldr.a65 dosromcomp.a65 dos.bin
	xa -w -XMASM -P $@.lst -o $@ $<

dos.bin:
	make -C ..

clean:
	rm -f dosromldr dosromcomp
