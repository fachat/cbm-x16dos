

dosromldr: dosromldr.a65 dosromcomp dos.bin
	xa -w -XMASM -o $@ $<

dosromcomp: dosromcomp.a65
	xa -XMASM -o $@ $<

dos.bin:
	make -C ..

clean:
	rm -f dosromldr dosromcomp
