CFLAGS += -Wall

all: chaseccomp.o

chasc_defs_%.c: %.chasc common.chasc gen_defs chaseccomp.h
	./gen_defs <$< >$@

chasc_defs_%: chasc_defs_%.c
	$(CC) $< -o $@

%.chasc.expanded: chasc_defs_%
	./$< >$@

chasc_%.h: %.chasc.expanded gen_syscalls
	./gen_syscalls $< >$@

chaseccomp.o: chaseccomp.c chaseccomp.h chasc_network.h chasc_buffer.h
	$(CC) $(CFLAGS) chaseccomp.c -c -o $@

clean:
	rm -f *.d *.o
	rm -f *.chasc.expanded chasc_*.h chasc_*.c
