CFLAGS += -Wall -Wextra

all: chaseccomp.o

chasc_defs_%.c: %.chasc common.chasc gen_defs chaseccomp.h
	./gen_defs <$< >$@~
	mv $@~ $@

chasc_defs_%: chasc_defs_%.c
	$(CC) $(CFLAGS) $< -o $@ $(LDFLAGS)

%.chasc.expanded: chasc_defs_%
	./$< >$@~
	mv $@~ $@

chasc_%.h: %.chasc.expanded gen_syscalls
	./gen_syscalls $< >$@~
	mv $@~ $@

chaseccomp.o: chaseccomp.h chasc_network.h chasc_buffer.h

clean:
	rm -f *.d *.o
	rm -f *.chasc.expanded chasc_*.h chasc_*.c
