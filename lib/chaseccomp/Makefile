CFLAGS += -Wall -Wextra

all: chaseccomp.o

dummy: dummy.c

audit_nr.h: dummy read_nr
	./read_nr dummy > $@~
	mv $@~ $@

chasc_defs_buffer.c: common.chasc.expanded
chasc_defs_network.c: common.chasc.expanded

chasc_defs_%.c: %.chasc gen_defs chaseccomp.h audit_nr.h
	./gen_defs <$< >$@~
	mv $@~ $@

%.chasc.expanded: chasc_defs_%.c
	$(CC) $(CFLAGS) $(LDFLAGS) -E -P $< -o $@

chasc_%.h: %.chasc.expanded gen_syscalls
	./gen_syscalls $< $@

chaseccomp.o: chaseccomp.h chasc_network.h chasc_buffer.h

clean:
	rm -f *.d *.o
	rm -f *.chasc.expanded chasc_*.h chasc_*.c dummy
